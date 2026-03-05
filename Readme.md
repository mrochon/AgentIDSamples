# Entra Agent ID REST exercises

## Description

Playground for experimenting and demonstrating Entra Agent ID related APIs.

U to execute various Entra Agent ID related http calls (create blueprint, agent, acquire token)

## Prerequisites

1. Install VSCode with [REST extension](https://marketplace.visualstudio.com/items?itemName=humao.rest-client).

1. Register an application in your Entra test tenant and copy its properties to .env (tenant id, app id, secret). Grant it Microsoft Graph AgentIdentityBlueprint application permissions as well as Application.ReadWrite.All and AppRoleAssignment.ReadWrite.All permissions. This will be the client app used to acquire tokens to call a variety of MS Graph APIs.

2. Copy .env.sample to .env and update it with the app registration details.

## Create an Agent

Open the craeteBlueprint.http file.use the following http cals:

- *login* to acquire application token
- *createBlueprint* to create a new agent blueprint
- *createBlueprintServicePrincipal* to create a new Service Principal
- *updateBlueprintAddPermission* to provide permission for creating delegated agent tokens (on behalf of a user)
- *createBlueprintCredential* to create a new secret for the blueprint 
- *assignApplicationUri* to assign a valid app Uri to the blueprint
- *blueprintLogin* to acquire a blueprint token needed for the subsequent operation
- *createAgent* to create an agent from this blueprint

The other http requests in this file are for cleanup and reporting.

## Acquire token

Open the *acquireToken.http* file and use the following named requests:

- *login* to acquire application token
- *listBlueprints* to list existing blueprints. Response data is used in subsequent calls to reference the appropriate blueprint id.
- use *listBlueprintCredentials, *removePassword* and &createBlueprintCredential* to delete old and create a new secret for the blueprint. That way you do not save the secret after it is created but can reference it in same session.
- *listAgents* to find the agent you will use in subsequent calls
- *requestBlueprintToken* to get a blueprint token
*requestAgentIdentityToken* to request an autonomous agent token - this seems (like described in the docs)[https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api#request-a-token-for-the-agent-identity-blueprint] yet returns an error that the agent does not have a federated credential. **Issue is then what IdP** to use locally here to provide a federated credential.

## Operation

### Run locally

1. Install dependencies:

	npm install

2. Start the server:

	npm start

3. Browse to http://localhost:3000.

### Deploy with Bicep

The template creates an App Service plan, a Web App, and a user-assigned managed identity.

Example deployment:

az deployment group create \
  --resource-group <rg> \
  --template-file main.bicep

After deployment, assign Microsoft Graph API permissions to the managed identity in Entra ID if needed, then browse to the Web App URL output.

### Deploy with script

From the Operation folder:

powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ResourceGroup <rg> -AppName <appName>

The script installs production dependencies, packages the app, and deploys using az webapp deploy with run-from-package settings to avoid build loops.



## Application permissions
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

