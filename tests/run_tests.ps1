# Runs the warehouse assertions against an already loaded database.
# Explain plans stay in explain.sql; they measure cost and are not a pass/fail gate.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/MedInsure.ps1')

$tests = @(
    'data_quality.sql',
    'assert_integrity.sql',
    'analytics_smoke.sql'
)

Start-MedInsureLog

foreach ($name in $tests) {
    $path = Join-Path $PSScriptRoot $name
    Write-MedInsureHost "Running $name"
    Invoke-MedInsureSql -File $path
}

Write-MedInsureHost 'Warehouse tests passed.'
