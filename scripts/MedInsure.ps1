$ErrorActionPreference = 'Stop'
# This file lives in scripts/. Callers in tests/ still resolve the repo from here, not from their own folder.
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Write-MedInsureLog {
    param(
        [string]$Level = 'INFO',
        [AllowEmptyString()][string]$Message
    )

    if (-not $script:MedInsureLog -or [string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $line = '{0:yyyy-MM-dd HH:mm:ss} {1,-5} {2}' -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $script:MedInsureLog -Value $line -Encoding utf8
}

function Start-MedInsureLog {
    if ($script:MedInsureLog) {
        return
    }

    Initialize-MedInsureEnvironment
    $logDir = Join-Path $script:RepoRoot 'logs'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $script:MedInsureLog = Join-Path $logDir ('pipeline-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    Write-MedInsureHost "Logging to $($script:MedInsureLog)"
    Write-MedInsureLog -Message "repo $($script:RepoRoot)"
    Write-MedInsureLog -Message "database $($env:PGDATABASE) on $($env:PGHOST):$($env:PGPORT) user $($env:PGUSER)"
}

function Write-MedInsureHost {
    param([Parameter(ValueFromPipeline = $true)][AllowNull()][object]$Message)

    process {
        if ($null -eq $Message) {
            return
        }

        $text = $Message.ToString()
        Write-Host $text
        Write-MedInsureLog -Message $text
    }
}

function Invoke-MedInsureNative {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Command 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    foreach ($item in @($output)) {
        if ($null -eq $item) {
            continue
        }

        $text = $item.ToString()
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        Write-Host $text
        $level = 'INFO'
        if ($text -match '(^|\s)(ERROR|FATAL):') {
            $level = 'ERROR'
        }
        elseif ($text -match '(^|\s)WARNING:') {
            $level = 'WARN'
        }
        Write-MedInsureLog -Level $level -Message $text
    }

    return $code
}

function Initialize-MedInsureEnvironment {
    if (-not $script:RepoRoot) {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    }
    $envFile = Join-Path $script:RepoRoot '.env'
    $example = Join-Path $script:RepoRoot '.env.example'
    if (-not (Test-Path $envFile) -and (Test-Path $example)) {
        Copy-Item $example $envFile
    }

    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
            $pair = $_.Split('=', 2)
            if ($pair.Length -eq 2) {
                Set-Item -Path ("Env:" + $pair[0].Trim()) -Value $pair[1].Trim()
            }
        }
    }
}

function Test-MedInsureDocker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }

    & docker info --format "{{.ServerVersion}}" 1>$null 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-MedInsureContainerPath {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $roots = @{
        ((Join-Path $script:RepoRoot 'sql') + '\')   = '/workspace/sql'
        ((Join-Path $script:RepoRoot 'tests') + '\') = '/workspace/tests'
    }

    foreach ($prefix in $roots.Keys) {
        if ($FullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $FullPath.Substring($prefix.Length)
            return $roots[$prefix] + '/' + ($relative -replace '\\', '/')
        }
    }

    throw "SQL file must live under sql/ or tests/: $FullPath"
}

function Start-MedInsureDatabase {
    Initialize-MedInsureEnvironment
    if (Test-MedInsureDocker) {
        $code = Invoke-MedInsureNative { & docker compose --project-directory $script:RepoRoot up -d }
        if ($code -ne 0) {
            throw 'docker compose up failed.'
        }

        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            & docker compose --project-directory $script:RepoRoot exec -T postgres pg_isready -U $env:POSTGRES_USER -d $env:POSTGRES_DB | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 2
        }

        if (-not $ready) {
            Write-MedInsureLog -Level 'ERROR' -Message 'PostgreSQL did not become ready after 30 attempts.'
            throw 'PostgreSQL did not become ready.'
        }
        return
    }

    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        throw 'Neither Docker nor psql is available.'
    }
}

function Invoke-MedInsureSql {
    param(
        [string]$Sql,
        [string]$File
    )

    Initialize-MedInsureEnvironment
    Start-MedInsureLog
    $started = Get-Date
    $target = if ($File) { $File } else { $Sql }
    Write-MedInsureLog -Message "begin $target"

    if (Test-MedInsureDocker) {
        if ($File) {
            $containerPath = Get-MedInsureContainerPath -FullPath (Resolve-Path $File).Path
            $code = Invoke-MedInsureNative {
                & docker compose --project-directory $script:RepoRoot exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -f $containerPath
            }
        }
        else {
            $code = Invoke-MedInsureNative {
                & docker compose --project-directory $script:RepoRoot exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -c $Sql
            }
        }
    }
    elseif ($File) {
        $code = Invoke-MedInsureNative { & psql --set ON_ERROR_STOP=1 --file $File }
    }
    else {
        $code = Invoke-MedInsureNative { & psql --set ON_ERROR_STOP=1 --command $Sql }
    }

    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    if ($code -ne 0) {
        $failure = "psql exit $code after ${elapsed}s: $target"
        Write-MedInsureLog -Level 'ERROR' -Message $failure
        throw $failure
    }

    Write-MedInsureLog -Message "end exit 0 in ${elapsed}s: $target"
}

function Invoke-MedInsureSetup {
    Start-MedInsureLog
    Start-MedInsureDatabase
    $sqlRoot = Join-Path $script:RepoRoot 'sql'
    $files = Get-ChildItem -Path $sqlRoot -Filter '*.sql' -File -Recurse | Sort-Object FullName
    if ($files.Count -eq 0) {
        throw 'No SQL files were found under sql/.'
    }

    foreach ($file in $files) {
        Write-MedInsureHost "Applying $($file.FullName)"
        Invoke-MedInsureSql -File $file.FullName
    }

    Write-MedInsureHost 'Database setup completed.'
}
