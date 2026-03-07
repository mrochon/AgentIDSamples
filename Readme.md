# Entra Agent ID REST exercises

## Description

Playground for experimenting and demonstrating Entra Agent ID related APIs. Roughly based on this [documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api) (see below for differences).

It consists of a set of http requests to operate on various Agent ID objects (create blueprint, credentials, list agents) and a Node.js web app which needs to be deployed to Azure Web Apps. Agent ID relies on use of Federated Credentials and Azure deployment is a way to support satisfy that requirement through use of Managed Identities.

## Setup

1. Install VSCode with [REST extension](https://marketplace.visualstudio.com/items?itemName=humao.rest-client).

1. Register an application in your Entra test tenant and copy its properties to .env (tenant id, app id, secret). Grant it Microsoft Graph permissions (some of them are not required - they are used in optional operations):

- AgentIdentityBlueprint.AddRemoveCreds.All
- AgentIdentityBlueprint.Create
- AgentIdentityBlueprint.DeleteRestore.All
- AgentIdentityBlueprint.Read.All
- AgentIdentityBlueprint.UpdateAuthProperties.All
- AgentIdentityBlueprint.UpdateBranding.All
- AgentIdentityBlueprintPrincipal.Create
- AgentIdentityBlueprintPrincipal.DeleteRestore.All
- Application.Read.All
- Application.ReadWrite.All
- AppRoleAssignment.ReadWrite.All

3. Copy AgentSetup/.env.sample to .env and update it with the app registration details.

4. Open the createBlueprint.http file and execute the following *Send* actions:

- *login*
- *createBlueprintServicePrincipal*
- *createBlueprint*
- *createAgent*


5. Update Operation/main.bicep with values from your application registration.

5. Deploy the Operations web app

The template creates an App Service plan, a Web App, and a user-assigned managed identity.

```
az login --tenant <your tenant>
az deployment group create \
  --resource-group <rg> \
  --template-file main.bicep
.\deploy.ps1  -ResourceGroup <rg> -AppName <app name from bicep> 
```

7. Open the acquireToken.http file. Update the *createdFederatedCredential* json body by replacing the current value of the *subject* claim with the Object ID value of the managed identity created for the web app. Then execute the following *Send* actions:

- *login*
- *createFederatedIdentityCredential*

8. Naviagte to the web app, update the FIC_PATH_GUID parameter with the object id of the Federated Credential created in step 4 above. Execute the two token acquisition steps in sequence. The 2nd step should return a token to to MS Graph.

## How does it differ from the [documented](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api) flow?

1. Using GET to get the Managed Identity token rather than POST to the /token endpoint.

2. In Managed Identity token acqusition, the code uses the *resource=* rather than *scope=* parameter. The latter may work as well - I was trying to get a token with uri rather than GUID audience claim as part of earlier attempts at fixing another problem.

2. the value of the *fmi_path=* parameter is the *object id* of the Federated Identity Credential created in the above *createFederatedCredential* step rather than *agent-identity-client-id* as documented.

4. In the 2nd step (Request agent identity), added *agent_id_id* parameter, **object id** of the agent created in the *createAgent* step above.