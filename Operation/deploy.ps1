param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $true)]
  [string]$AppName,
  [string]$BlueprintAppId        = "",
  [string]$FicPathGuid           = "",
  [string]$AgentObjectId = "",
  [string]$TenantId              = "",
  [string]$HostingAppSecret      = "",
  [switch]$AppOnly
)

$ErrorActionPreference = "Stop"

# Load secrets from .env if present and parameter not supplied
$envFile = Join-Path $PSScriptRoot ".env"
if ((Test-Path $envFile) -and -not $HostingAppSecret) {
  Get-Content $envFile | Where-Object { $_ -match '^\s*([^#=]+?)\s*=\s*(.*)\s*$' } | ForEach-Object {
    $key, $val = $Matches[1], $Matches[2]
    if ($key -eq 'HOSTING_APP_SECRET') { $HostingAppSecret = $val }
  }
}

if (-not $AppOnly) {
  Write-Host "Deploying infrastructure..."
  $deployParams = @(
    "--resource-group", $ResourceGroup,
    "--template-file", "main.bicep"
  )
  if ($BlueprintAppId)        { $deployParams += "--parameters"; $deployParams += "blueprintAppId=$BlueprintAppId" }
  if ($FicPathGuid)           { $deployParams += "--parameters"; $deployParams += "ficPathGuid=$FicPathGuid" }
  if ($AgentObjectId) { $deployParams += "--parameters"; $deployParams += "agentObjectId=$AgentObjectId" }
  if ($TenantId)              { $deployParams += "--parameters"; $deployParams += "tenantId=$TenantId" }
  if ($HostingAppSecret)      { $deployParams += "--parameters"; $deployParams += "hostingAppSecret=$HostingAppSecret" }
  az deployment group create @deployParams | Out-Null
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

Write-Host "Deploying app content (server will install dependencies)..."
az webapp deploy --resource-group $ResourceGroup --name $AppName --src-path $zipPath --type zip --async true | Out-Null
Write-Host "Waiting for deployment to complete..."
Start-Sleep -Seconds 60
az webapp start --resource-group $ResourceGroup --name $AppName | Out-Null

Write-Host "Deployment complete."
