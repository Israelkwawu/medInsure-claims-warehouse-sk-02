$ErrorActionPreference = 'Stop'

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw 'psql was not found on PATH. Start Docker Desktop, or install PostgreSQL client tools.'
}

$root = Split-Path -Parent $PSScriptRoot
$sqlFiles = Get-ChildItem -Path (Join-Path $root 'sql') -Filter '*.sql' -File -Recurse |
    Sort-Object FullName

if ($sqlFiles.Count -eq 0) {
    throw 'No SQL files were found under sql/.'
}

foreach ($sqlFile in $sqlFiles) {
    Write-Host "Applying $($sqlFile.FullName)"
    & psql --set ON_ERROR_STOP=1 --file $sqlFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed while applying $($sqlFile.FullName)."
    }
}

Write-Host 'Database setup completed.'