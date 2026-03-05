const express = require("express");
const path = require("path");
const { ManagedIdentityCredential } = require("@azure/identity");

const app = express();
const port = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, "public")));

function decodeJwt(token) {
  const parts = token.split(".");
  if (parts.length < 2) {
    return { error: "Token does not look like a JWT." };
  }

  const payload = parts[1]
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");

  try {
    const json = Buffer.from(payload, "base64").toString("utf8");
    return JSON.parse(json);
  } catch (err) {
    return { error: "Failed to decode token body.", details: String(err) };
  }
}

app.get("/api/token", async (_req, res) => {
  try {
    const clientId = process.env.AZURE_CLIENT_ID;
    const credential = clientId
      ? new ManagedIdentityCredential({ clientId })
      : new ManagedIdentityCredential();
    const accessToken = await credential.getToken(
      "https://graph.microsoft.com/.default"
    );

    if (!accessToken || !accessToken.token) {
      return res.status(500).json({ error: "No token received." });
    }

    const decoded = decodeJwt(accessToken.token);
    return res.json({ token: accessToken.token, decoded });
  } catch (err) {
    const details = {
      message: err.message || String(err),
      name: err.name,
      statusCode: err.statusCode,
      errorCode: err.errorCode,
      stack: err.stack
    };
    return res.status(500).json({
      error: "Token request failed.",
      details
    });
  }
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
