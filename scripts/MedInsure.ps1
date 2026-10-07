$ErrorActionPreference = 'Stop'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

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
        & docker compose --project-directory $script:RepoRoot up -d
        if ($LASTEXITCODE -ne 0) {
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
    if (Test-MedInsureDocker) {
        if ($File) {
            $containerPath = Get-MedInsureContainerPath -FullPath (Resolve-Path $File).Path
            & docker compose --project-directory $script:RepoRoot exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -f $containerPath
        }
        else {
            & docker compose --project-directory $script:RepoRoot exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -c $Sql
        }

        if ($LASTEXITCODE -ne 0) {
            throw 'psql failed.'
        }
        return
    }

    if ($File) {
        & psql --set ON_ERROR_STOP=1 --file $File
    }
    else {
        & psql --set ON_ERROR_STOP=1 --command $Sql
    }

    if ($LASTEXITCODE -ne 0) {
        throw 'psql failed.'
    }
}

function Invoke-MedInsureSetup {
    Start-MedInsureDatabase
    $sqlRoot = Join-Path $script:RepoRoot 'sql'
    $files = Get-ChildItem -Path $sqlRoot -Filter '*.sql' -File -Recurse | Sort-Object FullName
    if ($files.Count -eq 0) {
        throw 'No SQL files were found under sql/.'
    }

    foreach ($file in $files) {
        Write-Host "Applying $($file.FullName)"
        Invoke-MedInsureSql -File $file.FullName
    }

    Write-Host 'Database setup completed.'
}
