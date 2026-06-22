const crypto = require("node:crypto");

const [, , partnerId, keyId, rawKey] = process.argv;

if (!partnerId || !keyId || !rawKey) {
  console.error(
    "Usage: node functions/scripts/create-plugin-api-key.js <partnerId> <keyId> <rawApiKey>",
  );
  process.exit(1);
}

const keyHash = crypto.createHash("sha256").update(rawKey).digest("hex");

console.log(
  JSON.stringify(
    {
      partnerPath: `pluginPartners/${partnerId}`,
      keyPath: `pluginPartners/${partnerId}/apiKeys/${keyId}`,
      apiKeyDocument: {
        keyHash,
        status: "active",
        createdAt: "SERVER_TIMESTAMP",
      },
      reminder: "Store only keyHash in Firestore. Do not store rawApiKey.",
    },
    null,
    2,
  ),
);
