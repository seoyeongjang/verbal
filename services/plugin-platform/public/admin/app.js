const els = {
  partnerId: document.querySelector("#partnerId"),
  partnerName: document.querySelector("#partnerName"),
  keyId: document.querySelector("#keyId"),
  rawApiKey: document.querySelector("#rawApiKey"),
  retentionDays: document.querySelector("#retentionDays"),
  coreApiBase: document.querySelector("#coreApiBase"),
  generateButton: document.querySelector("#generateButton"),
  docOutput: document.querySelector("#docOutput"),
  curlOutput: document.querySelector("#curlOutput"),
  copyDocsButton: document.querySelector("#copyDocsButton"),
  copyCurlButton: document.querySelector("#copyCurlButton"),
};

let currentDocs = "";
let currentCurl = "";

window.addEventListener("unhandledrejection", (event) => {
  els.docOutput.textContent = event.reason?.message || "Request failed.";
});
window.addEventListener("error", (event) => {
  els.docOutput.textContent = event.message || "Unexpected error.";
});

els.generateButton.addEventListener("click", generate);
els.copyDocsButton.addEventListener("click", () => copy(currentDocs));
els.copyCurlButton.addEventListener("click", () => copy(currentCurl));

async function generate() {
  const partnerId = cleanId(els.partnerId.value, "partnerId");
  const keyId = cleanId(els.keyId.value, "keyId");
  const rawApiKey = els.rawApiKey.value.trim();
  if (!rawApiKey) {
    throw new Error("Raw API key is required.");
  }
  const keyHash = await sha256(rawApiKey);
  const retentionDays = Math.min(30, Math.max(1, Number(els.retentionDays.value) || 1));
  const docs = {
    [`pluginPartners/${partnerId}`]: {
      name: els.partnerName.value.trim() || partnerId,
      status: "active",
      enabledFeatures: [
        "voiceTranscription",
        "messageCards",
        "calendarIntents",
        "audioPlayback",
      ],
      defaultAudioRetentionDays: retentionDays,
      createdAt: "SERVER_TIMESTAMP",
      updatedAt: "SERVER_TIMESTAMP",
    },
    [`pluginPartners/${partnerId}/apiKeys/${keyId}`]: {
      keyHash,
      status: "active",
      createdAt: "SERVER_TIMESTAMP",
      lastUsedAt: null,
    },
  };
  currentDocs = JSON.stringify(docs, null, 2);
  currentCurl = buildCurl({ partnerId, keyId, rawApiKey });
  els.docOutput.textContent = currentDocs;
  els.curlOutput.textContent = currentCurl;
  els.copyDocsButton.disabled = false;
  els.copyCurlButton.disabled = false;
}

function buildCurl({ partnerId, keyId, rawApiKey }) {
  const base = els.coreApiBase.value.trim().replace(/\/+$/, "") || "https://YOUR_FUNCTION_URL/pluginCoreApi";
  return [
    "curl -X POST",
    `  ${quote(`${base}/v1/message-cards`)}`,
    "  -H 'content-type: application/json'",
    `  -H ${quote(`x-verbal-partner-id: ${partnerId}`)}`,
    `  -H ${quote(`x-verbal-key-id: ${keyId}`)}`,
    `  -H ${quote(`x-verbal-api-key: ${rawApiKey}`)}`,
    "  -d '{\"platform\":\"slack\",\"transcript\":\"Can we talk at 8 PM?\"}'",
  ].join(" \\\n");
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function cleanId(value, field) {
  const cleaned = value.trim();
  if (!/^[A-Za-z0-9_-]{3,80}$/.test(cleaned)) {
    throw new Error(`${field} must be 3-80 characters using letters, numbers, underscore, or dash.`);
  }
  return cleaned;
}

async function copy(value) {
  await navigator.clipboard.writeText(value);
}

function quote(value) {
  return `'${value.replace(/'/g, "'\\''")}'`;
}
