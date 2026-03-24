param location string = resourceGroup().location
param appName string = 'operation-web-${uniqueString(resourceGroup().id)}'
param planName string = '${appName}-plan'
param identityName string = '${appName}-uami'
param ficPathGuid string = '63a2d916-7e98-4f46-8979-68a479900b7d'
param agentObjectId string = 'a37e43c1-1b69-427e-83e1-94d6bcc50065'
param miObjectId string = '53b2c0cc-0779-4d4a-a64a-77af97686264'
param tenantId string = '1165490c-89b5-463b-b203-8b77e01597d2'
param blueprintAppId string = 'dbbbac41-d18e-4450-a75a-d49fa0950d9a'
@secure()
param hostingAppSecret string = ''

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
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
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentity.properties.clientId
        }
        {
          name: 'BLUEPRINT_APP_ID'
          value: blueprintAppId
        }
        {
          name: 'FIC_PATH_GUID'
          value: ficPathGuid
        }
        {
          name: 'AGENT_IDENTITY_OBJECT_ID'
          value: agentObjectId
        }
        {
          name: 'AGENT_APP_ID'
          value: agentObjectId
        }
        {
          name: 'MI_OBJECT_ID'
          value: miObjectId
        }
        {
          name: 'HOSTING_APP_SECRET'
          value: hostingAppSecret
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

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output managedIdentityId string = userAssignedIdentity.id
