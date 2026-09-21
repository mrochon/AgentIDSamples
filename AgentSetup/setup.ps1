<#
.SYNOPSIS
    Registers the Entra ID applications needed to run createObjects.http and writes
    their properties into .env.

.DESCRIPTION
    - Copies .env.sample to .env (if .env does not already exist).
    - Registers a confidential client app, "AI Agent ID Tester", with the Microsoft
      Graph application permissions used by createObjects.http, grants admin consent
      for whichever of those permissions exist in the tenant, and creates a client
      secret. TENANT_ID, CLIENT_ID and CLIENT_SECRET are written to .env.
    - Registers a public client app, "AI Test Public App" (used for the device-code
      flow in createObjects.http), and writes its app id to PUBLIC_CLIENT_ID in .env.

    Some AgentIdentityBlueprint* permissions are part of the Agent ID preview and may
    not exist as Microsoft Graph app roles in every tenant. When one can't be found,
    the script warns and continues; add it by hand later once it becomes available.

.NOTES
    Requires the Microsoft.Graph.Authentication and Microsoft.Graph.Applications
    PowerShell modules, and a signed-in account allowed to create app registrations
    and grant admin consent (e.g. Application Administrator + Privileged Role
    Administrator, or Global Administrator).

.PARAMETER Force
    Overwrite an existing .env with a fresh copy of .env.sample before filling it in.
    Without this switch, an existing .env is updated in place.

.PARAMETER TenantId
    Tenant id or domain of your Entra test tenant. Strongly recommended: without it the
    sign-in can silently pick a personal Microsoft account, which has no tenant.

.EXAMPLE
    ./setup.ps1 -TenantId contoso.onmicrosoft.com
#>
[CmdletBinding()]
param(
    [string]$AgentAppDisplayName = 'AI Agent ID Tester',
    [string]$PublicAppDisplayName = 'AI Test Public App',
    [string]$EnvSamplePath = (Join-Path $PSScriptRoot '.env.sample'),
    [string]$EnvPath = (Join-Path $PSScriptRoot '.env'),
    [switch]$Force,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'

$GraphResourceAppId = '00000003-0000-0000-c000-000000000000'
$RequiredGraphAppRoles = @(
    'AgentIdentityBlueprint.AddRemoveCreds.All',
    'AgentIdentityBlueprint.Create',
    'AgentIdentityBlueprint.DeleteRestore.All',
    'AgentIdentityBlueprint.Read.All',
    'AgentIdentityBlueprint.UpdateAuthProperties.All',
    'AgentIdentityBlueprint.UpdateBranding.All',
    'AgentIdentityBlueprintPrincipal.Create',
    'AgentIdentityBlueprintPrincipal.DeleteRestore.All',
    'AgentIdUser.ReadWrite.IdentityParentedBy',
    'Application.Read.All',
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All'
)

function Assert-Module {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module $Name (CurrentUser scope)..." -ForegroundColor Yellow
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module -Name $Name -ErrorAction Stop
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $lines = @(Get-Content -Path $Path)
    $pattern = "^$Name="
    $newLine = "$Name=$Value"
    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match $pattern) {
            $found = $true
            $newLine
        } else {
            $line
        }
    }
    if (-not $found) {
        $updated = @($updated) + $newLine
    }
    Set-Content -Path $Path -Value $updated
}

Assert-Module -Name Microsoft.Graph.Authentication
Assert-Module -Name Microsoft.Graph.Applications

# --- 1. .env -----------------------------------------------------------------
if (-not (Test-Path $EnvSamplePath)) {
    throw "Sample env file not found at $EnvSamplePath"
}
if ((Test-Path $EnvPath) -and -not $Force) {
    Write-Host ".env already exists at $EnvPath - existing values will be updated in place. Use -Force to start again from .env.sample." -ForegroundColor Yellow
} else {
    Copy-Item -Path $EnvSamplePath -Destination $EnvPath -Force
    Write-Host "Copied $EnvSamplePath -> $EnvPath"
}

# --- 2. Connect ----------------------------------------------------------------
Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
$connectArgs = @{
    Scopes    = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')
    NoWelcome = $true
}
if ($TenantId) { $connectArgs['TenantId'] = $TenantId }
if ($UseDeviceCode) { $connectArgs['UseDeviceCode'] = $true }
Connect-MgGraph @connectArgs

# Get-MgContext can occasionally come back with an empty TenantId right after an
# interactive sign-in (seen with the Windows WAM broker in embedded/VS Code terminals,
# where the sign-in window can end up hidden). Retry briefly before giving up.
$context = $null
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $context = Get-MgContext
    if ($context -and $context.TenantId) { break }
    Start-Sleep -Seconds 2
}
if (-not $context -or -not $context.TenantId) {
    if ($context -and $context.HomeAccountId -like '*9188040d-6c67-4c5b-b112-36a304b66dad') {
        throw 'You signed in with a personal Microsoft account (MSA), which has no Entra tenant. Re-run with -TenantId <your test tenant id or domain, e.g. contoso.onmicrosoft.com> and sign in with a work/school account from that tenant.'
    }
    throw 'Connect-MgGraph did not return a tenant id. The sign-in may have been interrupted or hidden behind other windows. Re-run with -TenantId <your test tenant id or domain> and complete the sign-in fully.'
}
$TenantId = $context.TenantId
Set-EnvValue -Path $EnvPath -Name 'TENANT_ID' -Value $TenantId
Write-Host "Tenant: $TenantId"

# --- 3. Resolve the Microsoft Graph app roles we need ---------------------------
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphResourceAppId'"
if (-not $graphSp) { throw 'Could not find the Microsoft Graph service principal in this tenant.' }

$resourceAccess = @()
foreach ($roleName in $RequiredGraphAppRoles) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }
    if ($null -eq $role) {
        Write-Warning "Permission '$roleName' was not found as a Microsoft Graph application permission in this tenant - skipping. Add it manually later once it is available."
        continue
    }
    $resourceAccess += @{ Id = $role.Id; Type = 'Role' }
}
if ($resourceAccess.Count -eq 0) {
    throw 'None of the requested Microsoft Graph permissions were found - aborting.'
}

# --- 4. "AI Agent ID Tester" app ------------------------------------------------
Write-Host "Registering application '$AgentAppDisplayName'..." -ForegroundColor Cyan
$agentApp = Get-MgApplication -Filter "displayName eq '$AgentAppDisplayName'" | Select-Object -First 1
$requiredResourceAccess = @(@{ ResourceAppId = $GraphResourceAppId; ResourceAccess = $resourceAccess })
if ($agentApp) {
    Write-Host "Application '$AgentAppDisplayName' already exists (appId $($agentApp.AppId)) - reusing it and refreshing its required permissions."
    Update-MgApplication -ApplicationId $agentApp.Id -RequiredResourceAccess $requiredResourceAccess
} else {
    $agentApp = New-MgApplication -DisplayName $AgentAppDisplayName -SignInAudience 'AzureADMyOrg' -RequiredResourceAccess $requiredResourceAccess
}

$agentSp = Get-MgServicePrincipal -Filter "appId eq '$($agentApp.AppId)'"
if (-not $agentSp) {
    $agentSp = New-MgServicePrincipal -AppId $agentApp.AppId
}

Set-EnvValue -Path $EnvPath -Name 'CLIENT_ID' -Value $agentApp.AppId
Write-Host "CLIENT_ID: $($agentApp.AppId)"

# --- 5. Grant admin consent (application permissions) ---------------------------
Write-Host 'Granting admin consent for application permissions...' -ForegroundColor Cyan
$existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $agentSp.Id -All
foreach ($access in $resourceAccess) {
    if ($existingAssignments | Where-Object { $_.AppRoleId -eq $access.Id -and $_.ResourceId -eq $graphSp.Id }) {
        continue
    }
    try {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $agentSp.Id -PrincipalId $agentSp.Id -ResourceId $graphSp.Id -AppRoleId $access.Id | Out-Null
    } catch {
        Write-Warning "Could not grant admin consent for app role $($access.Id): $($_.Exception.Message). Grant it manually instead (Entra portal -> Enterprise applications -> $AgentAppDisplayName -> Permissions -> Grant admin consent)."
    }
}

# --- 6. Client secret -------------------------------------------------------------
Write-Host 'Creating client secret...' -ForegroundColor Cyan
$passwordCred = Add-MgApplicationPassword -ApplicationId $agentApp.Id -PasswordCredential @{
    DisplayName = 'setup.ps1'
    EndDateTime = (Get-Date).AddMonths(12)
}
Set-EnvValue -Path $EnvPath -Name 'CLIENT_SECRET' -Value $passwordCred.SecretText
Write-Host "CLIENT_SECRET generated (expires $($passwordCred.EndDateTime))."

# --- 7. "AI Test Public App" -------------------------------------------------------
Write-Host "Registering application '$PublicAppDisplayName'..." -ForegroundColor Cyan
$publicApp = Get-MgApplication -Filter "displayName eq '$PublicAppDisplayName'" | Select-Object -First 1
if ($publicApp) {
    Write-Host "Application '$PublicAppDisplayName' already exists (appId $($publicApp.AppId)) - reusing it."
} else {
    $publicApp = New-MgApplication -DisplayName $PublicAppDisplayName -SignInAudience 'AzureADMyOrg' -IsFallbackPublicClient -PublicClient @{
        RedirectUris = @('https://login.microsoftonline.com/common/oauth2/nativeclient')
    }
    New-MgServicePrincipal -AppId $publicApp.AppId | Out-Null
}
Set-EnvValue -Path $EnvPath -Name 'PUBLIC_CLIENT_ID' -Value $publicApp.AppId
Write-Host "PUBLIC_CLIENT_ID: $($publicApp.AppId)"

Write-Host "`nDone. $EnvPath now has TENANT_ID, CLIENT_ID, CLIENT_SECRET and PUBLIC_CLIENT_ID filled in." -ForegroundColor Green
Write-Host 'USER_OBJECT_ID and BLUEPRINT_ORDINAL still need to be filled in manually - see readme.md.' -ForegroundColor Yellow
