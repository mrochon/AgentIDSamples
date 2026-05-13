# Operation Web App

## Run locally

1. Install dependencies:

   npm install

2. Start the server:

   npm start

3. Browse to `http://localhost:3000`.

## Deploy with Bicep

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