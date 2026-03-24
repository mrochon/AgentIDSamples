const express = require("express");
const path = require("path");
const http = require("http");
const https = require("https");

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

function httpGet(url, headers) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith("https") ? https : http;
    const req = mod.get(url, { headers }, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => {
        try { resolve({ statusCode: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ statusCode: res.statusCode, body: data }); }
      });
    });
    req.on("error", reject);
    req.setTimeout(10000, () => { req.destroy(new Error("Request timed out")); });
  });
}

function httpPost(url, bodyStr) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(bodyStr)
      }
    };
    const mod = parsed.protocol === "https:" ? https : http;
    const req = mod.request(options, (res) => {
      let data = "";
      res.on("data", (c) => { data += c; });
      res.on("end", () => {
        try { resolve({ statusCode: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ statusCode: res.statusCode, body: data }); }
      });
    });
    req.on("error", reject);
    req.setTimeout(15000, () => { req.destroy(new Error("Request timed out")); });
    req.write(bodyStr);
    req.end();
  });
}

function decodeJwt(token) {
  const parts = token.split(".");
  if (parts.length < 2) return { error: "Not a valid JWT." };
  const seg = parts[1].replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
  try { return JSON.parse(Buffer.from(seg, "base64").toString("utf8")); }
  catch (e) { return { error: "Failed to decode", details: String(e) }; }
}

// Returns all config values so the UI can build and display request URLs
app.get("/api/config", (_req, res) => {
  res.json({
    endpoint:          process.env.IDENTITY_ENDPOINT || "",
    managedIdentityId: process.env.AZURE_CLIENT_ID   || "",
    blueprintAppId:    process.env.BLUEPRINT_APP_ID  || "",
    agentObjectId:     process.env.AGENT_APP_ID      || "",
    miObjectId:        process.env.MI_OBJECT_ID      || "",
    hostingAppSecret:  process.env.HOSTING_APP_SECRET || "",
    tenantId:          process.env.TENANT_ID         || ""
  });
});

// Step 1 — GET assertion token from App Service MSI endpoint
app.get("/api/step1", async (req, res) => {
  try {
    const endpoint       = process.env.IDENTITY_ENDPOINT;
    const identityHeader = process.env.IDENTITY_HEADER;
    if (!endpoint) return res.status(500).json({ error: "IDENTITY_ENDPOINT not set. Ensure a managed identity is attached." });

    const managedIdentityId = req.query.managedIdentityId || process.env.AZURE_CLIENT_ID;

    if (!managedIdentityId) return res.status(400).json({ error: "managedIdentityId (AZURE_CLIENT_ID) is required." });

    const params = new URLSearchParams({
      resource:      "api://AzureADTokenExchange",
      client_id:     managedIdentityId,
      "api-version": "2019-08-01"
    });

    const url = `${endpoint}?${params}`;
    console.log("Step 1 GET:", url);
    const { statusCode, body } = await httpGet(url, { "X-IDENTITY-HEADER": identityHeader || "" });
    console.log("Step 1 response:", statusCode);

    if (statusCode !== 200 || !body.access_token) {
      return res.status(500).json({ error: "Step 1 failed.", details: { statusCode, raw: body } });
    }
    return res.json({ token: body.access_token, decoded: decodeJwt(body.access_token) });
  } catch (err) {
    return res.status(500).json({ error: "Step 1 failed.", details: { message: err.message, stack: err.stack } });
  }
});

// Step 2 — POST assertion to Entra to get a blueprint app token
app.post("/api/step2", async (req, res) => {
  try {
    const { tenantId, blueprintAppId, agentObjectId, assertion } = req.body;
    if (!tenantId || !blueprintAppId || !assertion) {
      return res.status(400).json({ error: "Missing required fields: tenantId, blueprintAppId, assertion." });
    }

    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const form = new URLSearchParams({
      grant_type:            "client_credentials",
      client_id:             blueprintAppId,
      scope:                 "api://AzureADTokenExchange/.default",
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      client_assertion:      assertion,
      fmi_path:              agentObjectId || blueprintAppId
    });

    console.log("Step 2 POST:", tokenUrl);
    const { statusCode, body } = await httpPost(tokenUrl, form.toString());
    console.log("Step 2 response:", statusCode);

    if (statusCode !== 200 || !body.access_token) {
      return res.status(500).json({ error: "Step 2 failed.", details: { statusCode, raw: body } });
    }
    return res.json({ token: body.access_token, decoded: decodeJwt(body.access_token) });
  } catch (err) {
    return res.status(500).json({ error: "Step 2 failed.", details: { message: err.message, stack: err.stack } });
  }
});

// Step 3 — POST blueprint token to Entra to get an autonomous agent Graph token
app.post("/api/step3", async (req, res) => {
  try {
    const { tenantId, blueprintAppId, agentObjectId, assertion } = req.body;
    if (!tenantId || !blueprintAppId || !assertion) {
      return res.status(400).json({ error: "Missing required fields: tenantId, blueprintAppId, assertion." });
    }

    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const form = new URLSearchParams({
      client_id:             agentObjectId || blueprintAppId,
      scope:                 "https://graph.microsoft.com/.default",
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      client_assertion:      assertion,
      grant_type:            "client_credentials"
    });

    console.log("Step 3 POST:", tokenUrl);
    const { statusCode, body } = await httpPost(tokenUrl, form.toString());
    console.log("Step 3 response:", statusCode);

    if (statusCode !== 200 || !body.access_token) {
      return res.status(500).json({ error: "Step 3 failed.", details: { statusCode, raw: body } });
    }
    return res.json({ token: body.access_token, decoded: decodeJwt(body.access_token) });
  } catch (err) {
    return res.status(500).json({ error: "Step 3 failed.", details: { message: err.message, stack: err.stack } });
  }
});

// User id_token — read from EasyAuth header injected by Azure App Service
app.get("/api/usertoken", (req, res) => {
  const idToken = req.headers["x-ms-token-aad-id-token"];
  if (!idToken) {
    return res.status(401).json({ error: "User id_token not available. Ensure EasyAuth (Azure AD authentication) is enabled on this App Service and you are signed in." });
  }
  return res.json({ token: idToken, tokenType: "id_token", decoded: decodeJwt(idToken) });
});

// OBO Call 1 — exchange id_token for access_as_user token scoped to blueprint app
app.post("/api/obo1", async (req, res) => {
  try {
    const { tenantId, idToken, hostingAppSecret, blueprintAppId } = req.body;
    if (!tenantId || !idToken || !hostingAppSecret || !blueprintAppId) {
      return res.status(400).json({ error: "Missing required fields: tenantId, idToken, hostingAppSecret, blueprintAppId." });
    }
    const idDecoded = decodeJwt(idToken);
    const aud = idDecoded && idDecoded.aud;
    const clientId = Array.isArray(aud) ? aud[0] : aud;
    if (!clientId) {
      return res.status(400).json({ error: "Could not extract aud claim from id_token." });
    }
    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const form = new URLSearchParams({
      grant_type:          "urn:ietf:params:oauth:grant-type:jwt-bearer",
      client_id:           clientId,
      client_secret:       hostingAppSecret,
      assertion:           idToken,
      requested_token_use: "on_behalf_of",
      scope:               `api://${blueprintAppId}/access_as_user`
    });
    console.log("OBO1 POST:", tokenUrl);
    const { statusCode, body } = await httpPost(tokenUrl, form.toString());
    console.log("OBO1 response:", statusCode);
    if (statusCode !== 200 || !body.access_token) {
      return res.status(500).json({ error: "OBO1 failed.", details: { statusCode, raw: body } });
    }
    return res.json({ token: body.access_token, decoded: decodeJwt(body.access_token) });
  } catch (err) {
    return res.status(500).json({ error: "OBO1 failed.", details: { message: err.message, stack: err.stack } });
  }
});

// Step 4 — OBO: acquire agent token on behalf of user
app.post("/api/step4", async (req, res) => {
  try {
    const { tenantId, agentObjectId, blueprintToken, userToken } = req.body;
    if (!tenantId || !agentObjectId || !blueprintToken || !userToken) {
      return res.status(400).json({ error: "Missing required fields: tenantId, agentObjectId, blueprintToken, userToken." });
    }

    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const form = new URLSearchParams({
      grant_type:            "urn:ietf:params:oauth:grant-type:jwt-bearer",
      client_id:             agentObjectId,
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      client_assertion:      blueprintToken,
      assertion:             userToken,
      requested_token_use:   "on_behalf_of",
      scope:                 "https://graph.microsoft.com/mail.read"
    });

    console.log("Step 4 POST:", tokenUrl);
    const { statusCode, body } = await httpPost(tokenUrl, form.toString());
    console.log("Step 4 response:", statusCode);

    if (statusCode !== 200 || !body.access_token) {
      return res.status(500).json({ error: "Step 4 failed.", details: { statusCode, raw: body } });
    }
    return res.json({ token: body.access_token, decoded: decodeJwt(body.access_token) });
  } catch (err) {
    return res.status(500).json({ error: "Step 4 failed.", details: { message: err.message, stack: err.stack } });
  }
});

app.listen(port, () => console.log(`Server running on port ${port}`));
