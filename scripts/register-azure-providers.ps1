<# =====================================================================
  Register Azure Resource Providers for Container Apps
  Run this once with subscription-level permissions
  ===================================================================== #>

Write-Host "Registering Azure Resource Providers..." -ForegroundColor Cyan
Write-Host "This requires subscription-level permissions" -ForegroundColor Yellow
Write-Host ""

# Check current registration status
Write-Host "Checking Microsoft.App provider..." -ForegroundColor White
$appProvider = az provider show --namespace Microsoft.App --query "registrationState" -o tsv
if ($appProvider -eq "Registered") {
    Write-Host "✓ Microsoft.App is already registered" -ForegroundColor Green
} else {
    Write-Host "Registering Microsoft.App..." -ForegroundColor Yellow
    az provider register --namespace Microsoft.App
    Write-Host "✓ Microsoft.App registration initiated" -ForegroundColor Green
}

Write-Host ""
Write-Host "Checking Microsoft.OperationalInsights provider..." -ForegroundColor White
$logsProvider = az provider show --namespace Microsoft.OperationalInsights --query "registrationState" -o tsv
if ($logsProvider -eq "Registered") {
    Write-Host "✓ Microsoft.OperationalInsights is already registered" -ForegroundColor Green
} else {
    Write-Host "Registering Microsoft.OperationalInsights..." -ForegroundColor Yellow
    az provider register --namespace Microsoft.OperationalInsights
    Write-Host "✓ Microsoft.OperationalInsights registration initiated" -ForegroundColor Green
}

Write-Host ""
Write-Host "Provider registration complete!" -ForegroundColor Green
Write-Host "Note: Registration may take a few minutes to complete." -ForegroundColor Yellow
