param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $true)]
  [string]$AppName,
  [string]$BlueprintAppId        = "",
  [string]$FicPathGuid           = "",
  [string]$AgentIdentityObjectId = "",
  [string]$TenantId              = ""
)

$ErrorActionPreference = "Stop"

Write-Host "Deploying infrastructure..."
$deployParams = @(
  "--resource-group", $ResourceGroup,
  "--template-file", "main.bicep"
)
if ($BlueprintAppId)        { $deployParams += "--parameters"; $deployParams += "blueprintAppId=$BlueprintAppId" }
if ($FicPathGuid)           { $deployParams += "--parameters"; $deployParams += "ficPathGuid=$FicPathGuid" }
if ($AgentIdentityObjectId) { $deployParams += "--parameters"; $deployParams += "agentIdentityObjectId=$AgentIdentityObjectId" }
if ($TenantId)              { $deployParams += "--parameters"; $deployParams += "tenantId=$TenantId" }
az deployment group create @deployParams | Out-Null

Write-Host "Creating deployment package..."
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
