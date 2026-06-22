class VerbalPluginClient {
  constructor(options) {
    if (!options || typeof options !== "object") {
      throw new Error("VerbalPluginClient options are required.");
    }
    this.coreApiBase = required(options.coreApiBase, "coreApiBase").replace(
      /\/+$/,
      "",
    );
    this.partnerId = required(options.partnerId, "partnerId");
    this.keyId = required(options.keyId, "keyId");
    this.apiKey = required(options.apiKey, "apiKey");
    this.fetchImpl = options.fetch || globalThis.fetch;
    if (typeof this.fetchImpl !== "function") {
      throw new Error("fetch is required in this runtime.");
    }
  }

  transcribeAudio(input) {
    return this.post("/v1/transcriptions", input);
  }

  renderMessageCard(input) {
    return this.post("/v1/message-cards", input);
  }

  parseCalendarIntent(input) {
    return this.post("/v1/calendar-intents", input);
  }

  audioUrl(audioId) {
    return `${this.coreApiBase}/v1/audio/${encodeURIComponent(audioId)}`;
  }

  async post(path, body) {
    const response = await this.fetchImpl(`${this.coreApiBase}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-verbal-partner-id": this.partnerId,
        "x-verbal-key-id": this.keyId,
        "x-verbal-api-key": this.apiKey,
      },
      body: JSON.stringify(body || {}),
    });
    const payload = await response.json();
    if (!response.ok) {
      const message = payload?.error?.message || "Verbal Core API request failed.";
      const error = new Error(message);
      error.status = response.status;
      error.payload = payload;
      throw error;
    }
    return payload;
  }
}

function required(value, field) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${field} is required.`);
  }
  return value.trim();
}

function bufferToBase64(value) {
  if (typeof Buffer !== "undefined" && Buffer.isBuffer(value)) {
    return value.toString("base64");
  }
  if (value instanceof ArrayBuffer) {
    return bytesToBase64(new Uint8Array(value));
  }
  if (ArrayBuffer.isView(value)) {
    return bytesToBase64(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
  }
  throw new Error("Buffer, ArrayBuffer, or typed array is required.");
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  if (typeof btoa === "function") {
    return btoa(binary);
  }
  return Buffer.from(binary, "binary").toString("base64");
}

module.exports = {
  VerbalPluginClient,
  bufferToBase64,
};
