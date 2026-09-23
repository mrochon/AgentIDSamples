# Microsoft Agent ID deep dive

**Note:** to execute the code in this repo you **must** use a test Entra tenant. Its operation requires an extensive set of permissions that you would never want to give to a single application in the production environment.

## Description
These samples show:

1. Graph http calls needed to [create Entra Agent ID artifacts](AgentSetup): blueprints, agent identities and agent users. They expose what toolkits and tools do behind the scene to manage Agent ID data.

2. A simple [web application](Operation) obtaining OAuth2 tokens for agents. Again, the application exposes the raw https calls needed for that purpose. Deployed version of this app [can be accessed here](https://agentidtokens.azurewebsites.net/). However, it requires authentication with my tenant to actualy request and display tokens. The UI shows
what inputs it would use and the syntax of the token requests.

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
| `MI_CLIENT_ID` | Client ID of the user-assigned managed identity (see below) |
| `MI_OBJECT_ID` | Object (principal) ID of the managed identity |
| `HOSTING_APP_ID` | Client (app) ID of the hosting app registration. Used only by `deploy.ps1` to enable authentication on the Web App (see [Authentication](#authentication-easyauth)) |
| `HOSTING_APP_SECRET` | Client secret of the hosting app registration (see below) |
| `AGENT_USER_UPN` | User principal name of the agent user, e.g. `agentuser@yourdomain.com`. Pre-fills the **Username** field in Step 5b |

`IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are injected by App Service when a managed identity is attached, so they are not set in `.env`.

##### AGENT_USER_UPN

The UPN of the agent user that Step 5b acquires a token for (the `username` sent in the `user_fic` request). It is no longer hard-coded: the page pre-fills the **Username** field from this setting, and you can still edit the field before running the step. If it is empty, Step 5b requires you to type a username.

For a deployed app, `deploy.ps1` reads `AGENT_USER_UPN` from `.env` (or takes `-AgentUserUpn <upn>`) and passes it to `main.bicep` as the `agentUserUpn` parameter, which sets the app setting. It is applied only on a full deployment, not with `-AppOnly`.

##### MI_CLIENT_ID

This is the client ID of the user-assigned managed identity created by `main.bicep`. The template sets it on the Web App automatically, so you only need it in `.env` for local runs. To look it up:

- Azure CLI: `az identity show -g <rg> -n <appName>-uami --query clientId -o tsv`
- Portal: open the managed identity resource, then **Overview** > **Client ID**. Do not use **Object (principal) ID**; that is `MI_OBJECT_ID`.
- Deployed app: `az webapp config appsettings list -g <rg> -n <appName> --query "[?name=='MI_CLIENT_ID'].value" -o tsv`

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

The template creates an App Service plan and a Web App. It also creates a user-assigned managed identity, unless you tell it to use an existing one (see below).

**Prerequisites:** the resource group must already exist (`deploy.ps1` does not create it), and you must be signed in with `az login`.

**Configuration.** `main.bicep` has no hard-coded tenant or app ids. `deploy.ps1` reads `TENANT_ID`, `BLUEPRINT_APP_ID`, `AGENT_APP_ID`, `HOSTING_APP_SECRET` and `AGENT_USER_UPN` from `.env` and passes them to the template, so `.env` is the single source of configuration for both local runs and deployments. You can override any of them with `-TenantId`, `-BlueprintAppId`, `-AgentAppId`, `-HostingAppSecret` or `-AgentUserUpn`. A full deployment stops with an error if the tenant, blueprint or agent id is missing. The values are only applied on a full deployment, not with `-AppOnly`.

**Web app name.** `-AppName` is required. It is passed to the template as the name of the Web App, so pick a globally unique name (it becomes `<AppName>.azurewebsites.net`) and use the same name for later `-AppOnly` deployments.

**Managed identity.** By default the template creates an identity named `<AppName>-uami`. The federated credential on your blueprint trusts one specific managed identity (`MANAGED_IDENTITY_OBJ_ID` in `createObjects.http`), so if you already have that identity, pass `-IdentityName <name>`. The identity must be in the same resource group. The template then attaches it to the Web App without creating or changing it, and `MI_CLIENT_ID` and `MI_OBJECT_ID` are taken from it. Either way they are set on the Web App automatically, so they are not passed in. The deployment also outputs `managedIdentityClientId` and `managedIdentityPrincipalId`, which you can copy into `.env` for local runs.

```
az login --tenant <your tenant>

# Full deployment (infrastructure + app code) - run when main.bicep changes
cd Operation
.\deploy.ps1 -ResourceGroup <rg> -AppName <app name>

# Same, using an existing managed identity in the resource group
.\deploy.ps1 -ResourceGroup <rg> -AppName <app name> -IdentityName <identity name>

# App code only - run when only server.js / public/* / package.json change
.\deploy.ps1 -ResourceGroup <rg> -AppName <app name> -AppOnly
```

Example, using an existing resource group `ai` and managed identity `BlueprintIdentity`:
```
cd Operation
.\deploy.ps1 -ResourceGroup ai -AppName operation-web-mysample -IdentityName BlueprintIdentity
.\deploy.ps1 -ResourceGroup ai -AppName operation-web-mysample -AppOnly
```

If you deploy with `az deployment group create` directly instead of `deploy.ps1`, pass `--parameters appName=... tenantId=... blueprintAppId=... agentAppId=...` (the template has no defaults for the last three), and optionally `existingIdentityName=...`.

After deployment, assign Microsoft Graph API permissions to the managed identity in Entra ID if needed, then browse to the Web App URL output.

##### Authentication (EasyAuth)

When `HOSTING_APP_ID` and `HOSTING_APP_SECRET` are both set (in `.env` or as `-HostingAppId` / `-HostingAppSecret`), a full deployment turns on App Service authentication for the Web App:

- Microsoft Entra ID is the identity provider, using the issuer for `TENANT_ID` and the app registration `HOSTING_APP_ID`. The secret is read from the `HOSTING_APP_SECRET` app setting, so it is not stored in the auth configuration.
- Unauthenticated requests are redirected to the sign-in page.
- The token store is enabled, so App Service passes the user's `id_token` to the app in the `X-MS-TOKEN-AAD-ID-TOKEN` header, which the OBO step uses.

If `HOSTING_APP_ID` is not set, `deploy.ps1` warns and deploys **without** authentication, leaving the site open to anyone. If `HOSTING_APP_ID` is set without a secret, it stops with an error. Like the other settings, authentication is only configured on a full deployment, not with `-AppOnly`.

`HOSTING_APP_ID` is the app registration users sign in to, the one `HOSTING_APP_SECRET` belongs to. It is **not** `MI_CLIENT_ID` (the managed identity) or the blueprint or agent app id. The deployment does not change the app registration, so configure it once:

1. Under **Authentication**, add a **Web** redirect URI: `https://<AppName>.azurewebsites.net/.auth/login/aad/callback`. `deploy.ps1` prints the exact URI after deployment.
2. On the same page, under **Implicit grant and hybrid flows**, tick **ID tokens**. Without this, sign-in fails or no `id_token` is issued.
3. Allow the hosting app to call the blueprint on the user's behalf (see below).

From the Azure CLI, steps 1 and 2 are (`--web-redirect-uris` replaces the existing list, so include any you already have):

```
az ad app update --id <HOSTING_APP_ID> --enable-id-token-issuance true --web-redirect-uris https://<AppName>.azurewebsites.net/.auth/login/aad/callback
```

###### Letting the hosting app call the blueprint (OBO)

The hosting app registration and the agent identity blueprint are two different applications. In the OBO step the hosting app sends the signed-in user's token to Entra, authenticating with its own `HOSTING_APP_ID` and `HOSTING_APP_SECRET`, and asks for a token for the blueprint's `access_as_user` scope (`api://<BLUEPRINT_APP_ID>/access_as_user`). Entra only issues that token if the hosting app has been allowed to call the blueprint's API. Otherwise the step fails with a consent error (`AADSTS65001`). Do one of the following, once:

- **Option A - on the hosting app.** Add the blueprint's `access_as_user` as an API permission on the hosting app registration and grant admin consent. In the portal, use **API permissions** > **Add a permission** > **APIs my organization uses**. If the blueprint is not listed there, use the CLI, which takes the ids directly. Get the scope id (`<SCOPE_ID>`) from `api.oauth2PermissionScopes[0].id` in the `listBlueprints` response in `AgentSetup/createObjects.http`:

  ```
  az ad app permission add --id <HOSTING_APP_ID> --api <BLUEPRINT_APP_ID> --api-permissions <SCOPE_ID>=Scope
  az ad app permission admin-consent --id <HOSTING_APP_ID>
  ```

- **Option B - on the blueprint.** Pre-authorize the hosting app as a client of the blueprint's `access_as_user` scope (in the blueprint's **Expose an API** settings, or through `api.preAuthorizedApplications` on the blueprint). Users then don't need to consent, and the hosting app registration is not changed. Setting `preAuthorizedApplications` replaces the whole list, so include any clients already in it.

Option B keeps the trust with the blueprint, which you manage through `createObjects.http`. Option A keeps it with the hosting app. The result is the same, so choose whichever fits how you manage the two registrations.
