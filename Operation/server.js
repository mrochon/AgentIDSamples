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
    endpoint:           process.env.IDENTITY_ENDPOINT        || "",
    managedIdentityId:  process.env.AZURE_CLIENT_ID          || "",
    blueprintAppId:     process.env.BLUEPRINT_APP_ID         || "",
    ficPathGuid:        process.env.FIC_PATH_GUID            || "",
    agentIdentityObjId: process.env.AGENT_IDENTITY_OBJECT_ID || "",
    tenantId:           process.env.TENANT_ID                || ""
  });
});

// Step 1 — GET assertion token from App Service MSI endpoint
app.get("/api/step1", async (req, res) => {
  try {
    const endpoint       = process.env.IDENTITY_ENDPOINT;
    const identityHeader = process.env.IDENTITY_HEADER;
    if (!endpoint) return res.status(500).json({ error: "IDENTITY_ENDPOINT not set. Ensure a managed identity is attached." });

    const managedIdentityId = req.query.managedIdentityId || process.env.AZURE_CLIENT_ID;
    const ficPathGuid       = req.query.ficPathGuid       || process.env.FIC_PATH_GUID;

    if (!managedIdentityId) return res.status(400).json({ error: "managedIdentityId (AZURE_CLIENT_ID) is required." });

    const params = new URLSearchParams({
      resource:      "api://AzureADTokenExchange",
      client_id:     managedIdentityId,
      "api-version": "2019-08-01"
    });
    if (ficPathGuid) params.set("fmi_path", ficPathGuid);

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

// Step 2 — POST assertion to Entra to get a Graph access token
app.post("/api/step2", async (req, res) => {
  try {
    const { tenantId, blueprintAppId, agentIdentityObjId, assertion } = req.body;
    if (!tenantId || !blueprintAppId || !assertion) {
      return res.status(400).json({ error: "Missing required fields: tenantId, blueprintAppId, assertion." });
    }

    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const form = new URLSearchParams({
      grant_type:            "client_credentials",
      client_id:             blueprintAppId,
      scope:                 "https://graph.microsoft.com/.default",
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      client_assertion:      assertion
    });
    if (agentIdentityObjId) form.set("agent_identity_id", agentIdentityObjId);

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

app.listen(port, () => console.log(`Server running on port ${port}`));
