<# =====================================================================
  Setup Azure Deployment for Open WebUI
  This script configures Azure resources and GitHub secrets for 
  automated deployment using OIDC authentication
  ===================================================================== #>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "lojoweb-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

# Hardcoded GitHub org and repo
$GitHubOrg = "lojones"
$GitHubRepo = "open-webui"

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

# Verify prerequisites
Log "Checking prerequisites..."

# Check if Azure CLI is installed
try {
    $azCheck = az --version 2>&1 | Select-String -Pattern "azure-cli\s+(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
    if ($azCheck) {
        Log "Azure CLI version: $azCheck" -Level "SUCCESS"
    } else {
        throw "Could not determine Azure CLI version"
    }
} catch {
    Log "Azure CLI is not installed. Please install it from https://aka.ms/installazurecli" -Level "ERROR"
    exit 1
}

# Check if GitHub CLI is installed
try {
    $ghVersion = gh --version | Select-String -Pattern "gh version (\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
    Log "GitHub CLI version: $ghVersion" -Level "SUCCESS"
} catch {
    Log "GitHub CLI is not installed. Please install it from https://cli.github.com/" -Level "ERROR"
    exit 1
}

# Login to Azure
Log "Logging into Azure..."
$account = az account show 2>$null
if (-not $account) {
    az login
}

# Get subscription info
$subscription = az account show --query "{id:id, name:name}" -o json | ConvertFrom-Json
Log "Using subscription: $($subscription.name) ($($subscription.id))" -Level "SUCCESS"

# Create resource group if it doesn't exist
Log "Ensuring resource group exists..."
$rgExists = az group exists -n $ResourceGroup -o tsv
if ($rgExists -eq 'false') {
    Log "Creating resource group: $ResourceGroup in $Location"
    az group create -n $ResourceGroup -l $Location | Out-Null
    Log "Resource group created" -Level "SUCCESS"
} else {
    Log "Resource group already exists" -Level "SUCCESS"
}

# Create service principal and configure OIDC
Log "Creating Azure AD application and service principal..."
$appName = "openwebui-github-deploy"

# Check if app already exists
$existingApp = az ad app list --display-name $appName --query "[0].appId" -o tsv 2>$null

if ($existingApp) {
    $appId = $existingApp
    Log "Using existing app: $appId" -Level "WARNING"
} else {
    # Create new app
    $app = az ad app create --display-name $appName --query "{appId:appId}" -o json | ConvertFrom-Json
    $appId = $app.appId
    Log "Created app: $appId" -Level "SUCCESS"
}

# Create service principal if it doesn't exist
$spExists = az ad sp show --id $appId 2>$null
if (-not $spExists) {
    az ad sp create --id $appId | Out-Null
    Log "Created service principal" -Level "SUCCESS"
}

# Configure federated credentials for GitHub OIDC
Log "Configuring GitHub OIDC federation..."

# Check existing federated credentials
$existingCreds = az ad app federated-credential list --id $appId --query "[].name" -o tsv 2>$null

# Production environment
if ($existingCreds -contains "github-deploy-prod-env") {
    Log "Production environment federated credential already exists" -Level "SUCCESS"
} else {
    $prodEnvCredential = @{
        name = "github-deploy-prod-env"
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:${GitHubOrg}/${GitHubRepo}:environment:production"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json

    $prodEnvCredFile = New-TemporaryFile
    $prodEnvCredential | Out-File -FilePath $prodEnvCredFile.FullName -Encoding UTF8

    az ad app federated-credential create --id $appId --parameters $prodEnvCredFile.FullName 2>$null | Out-Null
    Remove-Item $prodEnvCredFile.FullName
    Log "Production environment federated credential created" -Level "SUCCESS"
}

# Main branch credential (for pushes without environment)
if ($existingCreds -contains "github-deploy-main") {
    Log "Main branch federated credential already exists" -Level "SUCCESS"
} else {
    $mainCredential = @{
        name = "github-deploy-main"
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:${GitHubOrg}/${GitHubRepo}:ref:refs/heads/main"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json

    $mainCredFile = New-TemporaryFile
    $mainCredential | Out-File -FilePath $mainCredFile.FullName -Encoding UTF8

    az ad app federated-credential create --id $appId --parameters $mainCredFile.FullName 2>$null | Out-Null
    Remove-Item $mainCredFile.FullName
    Log "Main branch federated credential created" -Level "SUCCESS"
}

# Staging environment (for manual deployments)
if ($existingCreds -contains "github-deploy-staging") {
    Log "Staging federated credential already exists" -Level "SUCCESS"
} else {
    $stagingCredential = @{
        name = "github-deploy-staging"
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:${GitHubOrg}/${GitHubRepo}:environment:staging"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json

    $stagingCredFile = New-TemporaryFile
    $stagingCredential | Out-File -FilePath $stagingCredFile.FullName -Encoding UTF8

    az ad app federated-credential create --id $appId --parameters $stagingCredFile.FullName 2>$null | Out-Null
    Remove-Item $stagingCredFile.FullName
    Log "Staging federated credential created" -Level "SUCCESS"
}

Log "OIDC federation configured" -Level "SUCCESS"

# Assign Contributor role to the service principal
Log "Checking role assignments for service principal..."
$scope = "/subscriptions/$($subscription.id)/resourceGroups/$ResourceGroup"
$existingRole = az role assignment list --assignee $appId --scope $scope --query "[?roleDefinitionName=='Contributor'].roleDefinitionName" -o tsv 2>$null

if ($existingRole) {
    Log "Contributor role already assigned" -Level "SUCCESS"
} else {
    Log "Assigning Contributor role to service principal..."
    $roleAssignment = az role assignment create `
        --role "Contributor" `
        --assignee $appId `
        --scope $scope `
        --query "{role:roleDefinitionName, scope:scope}" -o json | ConvertFrom-Json
    
    Log "Role assigned: $($roleAssignment.role)" -Level "SUCCESS"
}

# Get tenant ID
$tenantId = az account show --query tenantId -o tsv

# Login to GitHub CLI
Log "Authenticating with GitHub..."
$ghAuth = gh auth status 2>&1
if ($ghAuth -match "not logged in") {
    gh auth login
}

# Set GitHub secrets
Log "Setting GitHub repository secrets..."

# Azure credentials
gh secret set AZURE_CLIENT_ID --body $appId --repo "${GitHubOrg}/${GitHubRepo}"
gh secret set AZURE_TENANT_ID --body $tenantId --repo "${GitHubOrg}/${GitHubRepo}"
gh secret set AZURE_SUBSCRIPTION_ID --body $subscription.id --repo "${GitHubOrg}/${GitHubRepo}"

Log "Azure authentication secrets set" -Level "SUCCESS"

# Supabase Configuration
Log "Supabase Configuration"
Write-Host ""
Write-Host "Do you want to set new Supabase secrets or use existing ones?" -ForegroundColor Cyan
Write-Host "1) Set new secrets" -ForegroundColor White
Write-Host "2) Use existing secrets (with verification)" -ForegroundColor White
Write-Host "3) Skip Supabase configuration (secrets already exist)" -ForegroundColor White
Write-Host ""
$secretsChoice = Read-Host "Enter your choice (1, 2, or 3)"

if ($secretsChoice -eq "1") {
    # Prompt for Supabase credentials
    Log "Setting up new Supabase connection secrets..."
    Write-Host ""
    Write-Host "Please provide your Supabase connection details:" -ForegroundColor Cyan
    Write-Host ""

    $supabaseHost = Read-Host "Supabase Host (e.g., aws-0-us-east-2.pooler.supabase.com)"
    $supabasePort = Read-Host "Supabase Port (default: 6543)"
    if (-not $supabasePort) { $supabasePort = "6543" }
    $supabaseUser = Read-Host "Supabase User (e.g., postgres.abcd)"
    $supabaseDatabase = Read-Host "Database Name (default: postgres)"
    if (-not $supabaseDatabase) { $supabaseDatabase = "postgres" }
    $supabasePassword = Read-Host "Supabase Password" -AsSecureString

    # Convert secure string to plain text for GitHub secret
    $supabasePasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($supabasePassword)
    )

    # Validate inputs before setting secrets
    if (-not $supabaseHost) {
        Log "Supabase host is empty!" -Level "ERROR"
        exit 1
    }

    # Set Supabase secrets with proper escaping
    Log "Setting SUPABASE_HOST secret..."
    $supabaseHost | gh secret set SUPABASE_HOST --repo "${GitHubOrg}/${GitHubRepo}"

    Log "Setting SUPABASE_PORT secret..."
    $supabasePort | gh secret set SUPABASE_PORT --repo "${GitHubOrg}/${GitHubRepo}"

    Log "Setting SUPABASE_USER secret..."
    $supabaseUser | gh secret set SUPABASE_USER --repo "${GitHubOrg}/${GitHubRepo}"

    Log "Setting SUPABASE_DATABASE secret..."
    $supabaseDatabase | gh secret set SUPABASE_DATABASE --repo "${GitHubOrg}/${GitHubRepo}"

    Log "Setting SUPABASE_PASSWORD secret..."
    $supabasePasswordPlain | gh secret set SUPABASE_PASSWORD --repo "${GitHubOrg}/${GitHubRepo}"

    Log "Supabase secrets configured" -Level "SUCCESS"
} elseif ($secretsChoice -eq "2") {
    Log "Using existing Supabase secrets from repository" -Level "SUCCESS"
    
    # Verify that secrets exist
    Log "Verifying Supabase secrets exist..."
    
    # Get the list of secrets as JSON for more reliable parsing
    try {
        $secretsJson = gh api repos/${GitHubOrg}/${GitHubRepo}/actions/secrets --jq '.secrets[].name' 2>$null
        $existingSecrets = $secretsJson -split "`n" | Where-Object { $_ -ne "" }
    } catch {
        # Fallback to gh secret list if API fails
        $secretsList = gh secret list --repo "${GitHubOrg}/${GitHubRepo}" 2>$null
        $existingSecrets = @()
        foreach ($line in ($secretsList -split "`n")) {
            if ($line -match "^(\S+)\s+") {
                $existingSecrets += $matches[1]
            }
        }
    }
    
    $requiredSecrets = @("SUPABASE_HOST", "SUPABASE_PORT", "SUPABASE_USER", "SUPABASE_DATABASE", "SUPABASE_PASSWORD")
    $missingSecrets = @()
    
    foreach ($secret in $requiredSecrets) {
        if ($existingSecrets -notcontains $secret) {
            $missingSecrets += $secret
        }
    }
    
    if ($missingSecrets.Count -gt 0) {
        Log "Missing secrets: $($missingSecrets -join ', ')" -Level "ERROR"
        Log "Please run the script again and choose option 1 to set the secrets" -Level "ERROR"
        exit 1
    }
    
    Log "All required Supabase secrets found" -Level "SUCCESS"
} else {
    Log "Skipping Supabase configuration - assuming secrets are already configured" -Level "SUCCESS"
}

# Create environments in GitHub
Log "Creating GitHub environments..."

# Create production environment
$prodEnv = @{
    environment_name = "production"
    deployment_branch_policy = @{
        protected_branches = $true
        custom_branch_policies = $false
    }
} | ConvertTo-Json

# Note: GitHub CLI doesn't support creating environments directly, 
# so we'll use the API
$token = gh auth token
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github.v3+json"
}

$prodEnvUrl = "https://api.github.com/repos/${GitHubOrg}/${GitHubRepo}/environments/production"
try {
    Invoke-RestMethod -Uri $prodEnvUrl -Method PUT -Headers $headers -Body $prodEnv -ContentType "application/json" | Out-Null
    Log "Production environment created" -Level "SUCCESS"
} catch {
    Log "Note: Could not create production environment (may already exist)" -Level "WARNING"
}

# Create staging environment
$stagingEnvUrl = "https://api.github.com/repos/${GitHubOrg}/${GitHubRepo}/environments/staging"
$stagingEnv = @{ environment_name = "staging" } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri $stagingEnvUrl -Method PUT -Headers $headers -Body $stagingEnv -ContentType "application/json" | Out-Null
    Log "Staging environment created" -Level "SUCCESS"
} catch {
    Log "Note: Could not create staging environment (may already exist)" -Level "WARNING"
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "     DEPLOYMENT SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Azure Resources:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "  Service Principal: $appId" -ForegroundColor White
Write-Host ""
Write-Host "GitHub Configuration:" -ForegroundColor Cyan
Write-Host "  Repository: ${GitHubOrg}/${GitHubRepo}" -ForegroundColor White
Write-Host "  Environments: production, staging" -ForegroundColor White
if ($secretsChoice -eq "1") {
    Write-Host "  Secrets: Newly configured" -ForegroundColor White
} elseif ($secretsChoice -eq "2") {
    Write-Host "  Secrets: Verified existing" -ForegroundColor White
} else {
    Write-Host "  Secrets: Skipped verification" -ForegroundColor White
}
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. The deployment workflow is configured to run on merge to 'main'" -ForegroundColor White
Write-Host "2. You can also trigger manual deployments using workflow_dispatch" -ForegroundColor White
Write-Host "3. Monitor deployments in the GitHub Actions tab" -ForegroundColor White
Write-Host ""
Write-Host "To trigger a deployment:" -ForegroundColor Yellow
Write-Host "  - Merge a PR to main branch (automatic)" -ForegroundColor White
Write-Host "  - Go to Actions tab and manually run 'Deploy to Azure Container Apps'" -ForegroundColor White
Write-Host ""
