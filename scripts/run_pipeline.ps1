param(
    [ValidateRange(0.01, 1.0)]
    [double]$Scale = 0.05
)

. "$PSScriptRoot/MedInsure.ps1"

Invoke-MedInsureSetup

$scaleText = $Scale.ToString([System.Globalization.CultureInfo]::InvariantCulture)
Write-Host "Generating source data at scale $scaleText"
Invoke-MedInsureSql -Sql "CALL source.generate_synthetic_data($scaleText);"

Write-Host 'Loading the warehouse'
Invoke-MedInsureSql -Sql 'CALL warehouse.reset_warehouse_data();'
Invoke-MedInsureSql -Sql 'CALL warehouse.run_etl();'
Invoke-MedInsureSql -Sql 'CALL warehouse.refresh_monthly_claim_volume();'

Write-Host 'Running warehouse tests'
& (Join-Path $script:RepoRoot 'tests/run_tests.ps1')
