param location string = resourceGroup().location
param appName string = 'operation-web-${uniqueString(resourceGroup().id)}'
param planName string = '${appName}-plan'
param identityName string = '${appName}-uami'
param ficPathGuid string = '63a2d916-7e98-4f46-8979-68a479900b7d'
param agentAppId string = '1eeb2aed-e2f8-4056-b780-70ce54b59c6a'
param tenantId string = '1165490c-89b5-463b-b203-8b77e01597d2'
param blueprintAppId string = '02c162cb-cfd5-445e-9517-b6dbd2309259'

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
          value: agentAppId
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
