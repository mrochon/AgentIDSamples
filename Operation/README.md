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

Blueprint V5 created with V1.0 API
"appId": "dfb733ac-fa70-4537-a10f-3def3bcc00c6"
SP "id": "1aaac0d4-0812-4ab9-8ba7-663779a2549e"

Agent:

      "id": "8d07d2d1-2c3c-4199-82e6-7690d6b7b1e8"
