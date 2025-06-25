# Build and push Open WebUI Docker image for Azure Container Apps
# Usage: Run this script from the root of your repo

param(
    [string]$ImageName = "lojodev/lojoai",
    [string]$Tag = "latest"
)

function Log($msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$ts] $msg"
}

$fullTag = "$ImageName`:$Tag"

# Check if logged in to Docker Hub
Log "Checking Docker Hub login status..."
$dockerConfigPath = Join-Path $env:USERPROFILE ".docker\config.json"
$loggedIn = $false
if (Test-Path $dockerConfigPath) {
    $config = Get-Content $dockerConfigPath | ConvertFrom-Json
    if ($config.auths.PSObject.Properties.Name -contains "https://index.docker.io/v1/") {
        $loggedIn = $true
    }
}

if (-not $loggedIn) {
    Log "Not logged in to Docker Hub. Please log in."
    docker login
    if ($LASTEXITCODE -ne 0) {
        Log "❌ Docker login failed."
        exit 1
    }
} else {
    Log "Already logged in to Docker Hub."
}

Log "Building image for linux/amd64: $fullTag ..."
docker build --platform=linux/amd64 -t $fullTag .

if ($LASTEXITCODE -ne 0) {
    Log "❌ Docker build failed."
    exit 1
}

Log "Pushing image to Docker Hub: $fullTag ..."
docker push $fullTag

if ($LASTEXITCODE -eq 0) {
    Log "✅ Image pushed: $fullTag"
} else {
    Log "❌ Docker push failed."
    exit 1
}
