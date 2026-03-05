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
