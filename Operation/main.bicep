param location string = resourceGroup().location
param appName string = 'operation-web-${uniqueString(resourceGroup().id)}'
param planName string = '${appName}-plan'
// Name of the user-assigned managed identity to create when existingIdentityName is not set
param identityName string = '${appName}-uami'
// Name of an existing user-assigned managed identity in this resource group to use instead of creating one
param existingIdentityName string = ''
param agentAppId string
param tenantId string
param blueprintAppId string
// Client (app) id of the hosting app registration used for App Service authentication (EasyAuth).
// Authentication is enabled only when both hostingAppId and hostingAppSecret are set.
param hostingAppId string = ''
@secure()
param hostingAppSecret string = ''
param agentUserUpn string = ''

var enableAuth = !empty(hostingAppId) && !empty(hostingAppSecret)

var useExistingIdentity = !empty(existingIdentityName)

resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (!useExistingIdentity) {
  name: identityName
  location: location
}

// Refers to either the identity created above or the existing one; never modifies it
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: useExistingIdentity ? existingIdentityName : identityName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  dependsOn: [
    newIdentity
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      appCommandLine: 'npm start'
      appSettings: [
        {
          name: 'MI_CLIENT_ID'
          value: userAssignedIdentity.properties.clientId
        }
        {
          name: 'BLUEPRINT_APP_ID'
          value: blueprintAppId
        }
        {
          name: 'AGENT_APP_ID'
          value: agentAppId
        }
        {
          name: 'MI_OBJECT_ID'
          value: userAssignedIdentity.properties.principalId
        }
        {
          name: 'HOSTING_APP_SECRET'
          value: hostingAppSecret
        }
        {
          name: 'AGENT_USER_UPN'
          value: agentUserUpn
        }
        {
          name: 'TENANT_ID'
          value: tenantId
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '22-lts'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

// App Service authentication (EasyAuth) with Microsoft Entra ID. The client secret is read from the
// HOSTING_APP_SECRET app setting. The token store is enabled so the id_token is passed to the app
// in the X-MS-TOKEN-AAD-ID-TOKEN header.
resource authSettings 'Microsoft.Web/sites/config@2023-01-01' = if (enableAuth) {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
          clientId: hostingAppId
          clientSecretSettingName: 'HOSTING_APP_SECRET'
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
  }
}

output webAppName string = webApp.name
// Add this as a Web redirect URI on the hosting app registration
output authRedirectUri string = 'https://${webApp.properties.defaultHostName}/.auth/login/aad/callback'
output authEnabled bool = enableAuth
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output managedIdentityId string = userAssignedIdentity.id
output managedIdentityClientId string = userAssignedIdentity.properties.clientId
output managedIdentityPrincipalId string = userAssignedIdentity.properties.principalId
