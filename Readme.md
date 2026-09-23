# Microsoft Agent ID deep dive

**Note:** to execute the code in this repo you **must** use a test Entra tenant. Its operation requires an extensive set of permissions that you would never want to give to a single application in the production environment.

## Description
These samples show:

1. Graph http calls needed to [create Entra Agent ID artifacts](AgentSetup): blueprints, agent identities and agent users. They expose what toolkits and tools do behind the scene to manage Agent ID data.

2. A simple [web application](Operation) obtaining OAuth2 tokens for agents. Again, the application exposes the raw https calls needed for that purpose.

Hopefully, the use of low-level http calls will help the user to better understand how the Agent ID operates even if in production systems these are embedded in Microsoft or 3rd party tools or toolkits. 

This code was developed using Microsoft's [Entra Agent ID documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api).

## Operation

### Create

To run individual commands in the [CreateObjects.http](AgentSetup/CreateObjects.http) you will need to register and consent to an application with the following **application** permissions. Cope .env.sample and update it with the app registration data.

- AgentIdentityBlueprint.AddRemoveCreds.All
- AgentIdentityBlueprint.Create
- AgentIdentityBlueprint.DeleteRestore.All
- AgentIdentityBlueprint.ReadWrite.All
- AgentIdentityBlueprint.UpdateAuthProperties.All
- AgentIdentityBlueprintPrincipal.Create
- AgentIdentityBlueprintPrincipal.DeleteRestore.All
- AgentIdentityBlueprintPrincipal.Read.All
- AgentIdentity.Read.All
- AgentIdUser.ReadWrite.All
- AgentInstance.Read.All
- Application.Read.All
- Application.ReadWrite.All
- Directory.Read.All

Install the [REST Client VS Code extension](https://marketplace.visualstudio.com/items?itemName=humao.rest-client) to execute the http commands in VSCode.

### Audit

Once yo have used the above to create the various Agent ID artifacts, you can use [Agent ID Audit](https://www.powershellgallery.com/packages?q=agentidaudit) PowerShell module
to get a view on the security posture of your agents.

### Get tokens

#### Run locally

1. Install dependencies:

   npm install

2. Start the server:

   npm start

3. Browse to `http://localhost:3000`.

#### Configuration (`.env`)

The app loads its settings from a `.env` file in this folder (git-ignored) using `dotenv`. `deploy.ps1` also reads `HOSTING_APP_SECRET` from it.

| Variable | Description |
| --- | --- |
| `TENANT_ID` | Entra tenant ID |
| `BLUEPRINT_APP_ID` | App (client) ID of the agent identity blueprint |
| `AGENT_APP_ID` | App ID of the agent identity |
| `AZURE_CLIENT_ID` | Client ID of the user-assigned managed identity (see below) |
| `MI_OBJECT_ID` | Object (principal) ID of the managed identity |
| `HOSTING_APP_SECRET` | Client secret of the hosting app registration (see below) |
| `AGENT_USER_UPN` | User principal name of the agent user, e.g. `agentuser@yourdomain.com`. Pre-fills the **Username** field in Step 5b |

`IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are injected by App Service when a managed identity is attached, so they are not set in `.env`.

##### AGENT_USER_UPN

The UPN of the agent user that Step 5b acquires a token for (the `username` sent in the `user_fic` request). It is no longer hard-coded: the page pre-fills the **Username** field from this setting, and you can still edit the field before running the step. If it is empty, Step 5b requires you to type a username.

For a deployed app, `deploy.ps1` reads `AGENT_USER_UPN` from `.env` (or takes `-AgentUserUpn <upn>`) and passes it to `main.bicep` as the `agentUserUpn` parameter, which sets the app setting. It is applied only on a full deployment, not with `-AppOnly`.

##### AZURE_CLIENT_ID

This is the client ID of the user-assigned managed identity created by `main.bicep`. The template sets it on the Web App automatically, so you only need it in `.env` for local runs. To look it up:

- Azure CLI: `az identity show -g <rg> -n <appName>-uami --query clientId -o tsv`
- Portal: open the managed identity resource, then **Overview** > **Client ID**. Do not use **Object (principal) ID**; that is `MI_OBJECT_ID`.
- Deployed app: `az webapp config appsettings list -g <rg> -n <appName> --query "[?name=='AZURE_CLIENT_ID'].value" -o tsv`

##### HOSTING_APP_SECRET

This is a client secret on the app registration that the web app signs users in with (the registration configured for EasyAuth on the App Service; see the app's **Authentication** page). The OBO step sends it to the token endpoint together with the user's `id_token`.

The `client_id` that goes with this secret is not configured anywhere. `/api/obo1` takes it from the `aud` claim of the user's `id_token`, which is the client ID of the app registration that signed the user in. The secret must therefore belong to that registration.

Secret values are only shown when they are created. To get a new one:

- Portal: app registration > **Certificates & secrets** > **New client secret**, then copy the **Value** (not the Secret ID).
- Azure CLI: `az ad app credential reset --id <hosting-app-id> --append`

#### Limitations when running on localhost

The on-behalf-of (OBO) step does not work from `localhost`. The user's `id_token` comes from the `x-ms-token-aad-id-token` header, which only App Service EasyAuth injects. Locally, `/api/usertoken` returns 401 and `/api/obo1` cannot run, so `HOSTING_APP_SECRET` is unused. Test OBO against the deployed App Service.

Step 1 also needs a managed identity, so it fails locally with "IDENTITY_ENDPOINT not set".

#### Deploy with Bicep

The template creates an App Service plan, a Web App, and a user-assigned managed identity.

Example deployment:

az deployment group create \
  --resource-group <rg> \
  --template-file main.bicep

After deployment, assign Microsoft Graph API permissions to the managed identity in Entra ID if needed, then browse to the Web App URL output.

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

.\deploy.ps1 -ResourceGroup <rg> -AppName <appName> -AppOnly
