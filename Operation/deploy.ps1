param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $true)]
  [string]$AppName,
  [string]$BlueprintAppId        = "",
  [string]$AgentAppId            = "",
  [string]$TenantId              = "",
  [string]$HostingAppId          = "",
  [string]$HostingAppSecret      = "",
  [string]$AgentUserUpn          = "",
  # Name of an existing user-assigned managed identity in $ResourceGroup to use instead of creating one
  [string]$IdentityName          = "",
  [switch]$AppOnly
)

$ErrorActionPreference = "Stop"

# Read .env (same file the app uses locally) so it is the single source of configuration.
# Explicit parameters take precedence over .env values.
$envValues = @{}
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
  Get-Content $envFile | Where-Object { $_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$' } | ForEach-Object {
    $envValues[$Matches[1]] = $Matches[2].Trim('"', "'")
  }
}
if (-not $BlueprintAppId)   { $BlueprintAppId   = $envValues['BLUEPRINT_APP_ID'] }
if (-not $AgentAppId)       { $AgentAppId       = $envValues['AGENT_APP_ID'] }
if (-not $TenantId)         { $TenantId         = $envValues['TENANT_ID'] }
if (-not $HostingAppId)     { $HostingAppId     = $envValues['HOSTING_APP_ID'] }
if (-not $HostingAppSecret) { $HostingAppSecret = $envValues['HOSTING_APP_SECRET'] }
if (-not $AgentUserUpn)     { $AgentUserUpn     = $envValues['AGENT_USER_UPN'] }

if (-not $AppOnly) {
  $missing = @()
  if (-not $BlueprintAppId) { $missing += 'BLUEPRINT_APP_ID (-BlueprintAppId)' }
  if (-not $AgentAppId)     { $missing += 'AGENT_APP_ID (-AgentAppId)' }
  if (-not $TenantId)       { $missing += 'TENANT_ID (-TenantId)' }
  if ($missing) {
    throw "Missing required values for infrastructure deployment: $($missing -join ', '). Set them in .env or pass the parameter."
  }
  if ($HostingAppId -and -not $HostingAppSecret) {
    throw "HOSTING_APP_ID is set but HOSTING_APP_SECRET (-HostingAppSecret) is missing. Both are needed to enable authentication."
  }
  if (-not $HostingAppId) {
    Write-Warning "HOSTING_APP_ID (-HostingAppId) is not set - App Service authentication (EasyAuth) will not be enabled and the site will be open to anyone."
  }

  if ($IdentityName) {
    az identity show --resource-group $ResourceGroup --name $IdentityName --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
      throw "Managed identity '$IdentityName' was not found in resource group '$ResourceGroup'."
    }
  }

  Write-Host "Deploying infrastructure..."
  $deployParams = @(
    "--resource-group", $ResourceGroup,
    "--template-file", "main.bicep",
    "--parameters", "appName=$AppName",
    "--parameters", "blueprintAppId=$BlueprintAppId",
    "--parameters", "agentAppId=$AgentAppId",
    "--parameters", "tenantId=$TenantId"
  )
  if ($HostingAppId)          { $deployParams += "--parameters"; $deployParams += "hostingAppId=$HostingAppId" }
  if ($HostingAppSecret)      { $deployParams += "--parameters"; $deployParams += "hostingAppSecret=$HostingAppSecret" }
  if ($AgentUserUpn)          { $deployParams += "--parameters"; $deployParams += "agentUserUpn=$AgentUserUpn" }
  if ($IdentityName)          { $deployParams += "--parameters"; $deployParams += "existingIdentityName=$IdentityName" }
  $outputsJson = az deployment group create @deployParams --query "properties.outputs" --output json
  if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }
  $outputs = $outputsJson | ConvertFrom-Json
  if ($outputs.authEnabled.value) {
    Write-Host "Authentication (EasyAuth) is enabled. Make sure the hosting app registration $HostingAppId has this Web redirect URI and ID token issuance enabled (see Readme.md):" -ForegroundColor Yellow
    Write-Host "  $($outputs.authRedirectUri.value)" -ForegroundColor Yellow
  }
} else {
  Write-Host "Skipping infrastructure deployment (-AppOnly)."
}

Write-Host "Creating deployment package (with dependencies)..."
$zipPath = Join-Path $PSScriptRoot "app.zip"
if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

$excludeNames = @("node_modules", ".git", ".env", "app.zip", "deploy.ps1")

# Stage files in a temp directory so the zip root maps exactly to the app root
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "webapp-deploy-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
  Get-ChildItem -Path $PSScriptRoot -Recurse | Where-Object {
    $relative = $_.FullName.Substring($PSScriptRoot.Length).TrimStart("\")
    $segments  = $relative.Split("\")
    -not ($segments | Where-Object { $excludeNames -contains $_ })
  } | ForEach-Object {
    $dest = Join-Path $tempDir $_.FullName.Substring($PSScriptRoot.Length).TrimStart("\")
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Path $dest -Force | Out-Null
    } else {
      New-Item -ItemType File -Path $dest -Force | Out-Null
      Copy-Item -Path $_.FullName -Destination $dest -Force
    }
  }

  Write-Host "Installing production dependencies..."
  Push-Location $tempDir
  try { npm install --omit=dev --silent } finally { Pop-Location }

  Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
} finally {
  Remove-Item -Recurse -Force $tempDir
}

Write-Host "Deploying app content..."
az webapp deploy --resource-group $ResourceGroup --name $AppName --src-path $zipPath --type zip | Out-Null
Write-Host "Deployment complete."
