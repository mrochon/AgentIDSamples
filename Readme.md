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
- *createBlueprint*
- *listBlueprints*
- *createBlueprintServicePrincipal*
- *createBlueprintPasswordCredential*
- *assignApplicationUri*

5. Update Operation/main.bicep with values from your application registration.

5. Deploy the Operations web app

The template creates an App Service plan, a Web App, and a user-assigned managed identity.

```
az login --tenant <your tenant>

# Full deployment (infrastructure + app code) — run when main.bicep changes
cd Operation
.\deploy.ps1  -ResourceGroup <rg> -AppName <app name from bicep>

# App code only — run when only server.js / public/* / package.json change
.\deploy.ps1  -ResourceGroup <rg> -AppName <app name from bicep> -AppOnly
```

Example:
```
cd Operation
.\deploy.ps1  -ResourceGroup agentid -AppName operation-web-igzu6xvzldpys
.\deploy.ps1  -ResourceGroup agentid -AppName operation-web-igzu6xvzldpys -AppOnly
```

7. Open the createBlueprint.http file. Update the *createdFederatedCredential* json body by replacing the current value of the *subject* claim with the Object ID value of the managed identity created for the web app. Then execute the following *Send* actions:

- *login*
- *createFederatedIdentityCredential*

8. Navigate to the web app, Execute the 3 steps to get a Graph token for the Agent.

[Based on this document](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api).
