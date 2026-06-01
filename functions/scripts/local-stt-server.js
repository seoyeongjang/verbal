const http = require("node:http");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
loadEnvFile(path.join(repoRoot, ".env"));
loadEnvFile(path.join(repoRoot, ".env.local"));
loadEnvFile(path.join(repoRoot, "functions", ".env"));
loadEnvFile(path.join(repoRoot, "functions", ".env.local"));

const port = Number(process.env.LOCAL_STT_PORT || 8787);
const host = process.env.LOCAL_STT_HOST || "127.0.0.1";
const model = process.env.DEEPGRAM_MODEL || "nova-3";
const maxBytes = Number(process.env.LOCAL_STT_MAX_BYTES || 0);
const transcriptCache = new Map();

const server = http.createServer(async (request, response) => {
  setCorsHeaders(response);

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && request.url === "/health") {
    writeJson(response, 200, {
      ok: true,
      provider: "deepgram",
      model,
      maxDurationMs: null,
      maxBytes: maxBytes > 0 ? maxBytes : null,
      hasDeepgramKey: Boolean(process.env.DEEPGRAM_API_KEY),
    });
    return;
  }

  if (request.method !== "POST" || request.url !== "/transcribe") {
    writeJson(response, 404, {error: "Not found."});
    return;
  }

  try {
    if (!process.env.DEEPGRAM_API_KEY) {
      writeJson(response, 500, {
        error: "DEEPGRAM_API_KEY is not configured. Add DEEPGRAM_API_KEY=... to the repo root .env.local file.",
      });
      return;
    }

    const body = await readRequestBody(request, maxBytes > 0 ? maxBytes * 2 : null);
    const payload = JSON.parse(body);
    const audioBase64 = String(payload.audioBase64 || "").replace(/^data:[^,]+,/, "");
    if (!audioBase64) {
      writeJson(response, 400, {error: "audioBase64 is required."});
      return;
    }

    const audioBytes = Buffer.from(audioBase64, "base64");
    if (audioBytes.length === 0) {
      writeJson(response, 400, {error: "Audio payload is empty."});
      return;
    }
    if (maxBytes > 0 && audioBytes.length > maxBytes) {
      writeJson(response, 413, {error: `Audio payload is too large. Max ${maxBytes} bytes.`});
      return;
    }
    const durationMs = Number(payload.durationMs || 0);
    if (!Number.isFinite(durationMs) || durationMs < 500) {
      writeJson(response, 400, {error: "Voice message must be at least 0.5 seconds."});
      return;
    }

    const language = String(payload.language || "ko");
    const mimeType = String(payload.mimeType || "audio/wav");
    const normalizedLanguage = normalizeDeepgramLanguage(language);
    const audioHash = crypto.createHash("sha256").update(audioBytes).digest("hex");
    const cacheKey = `${normalizedLanguage}:${audioHash}`;
    const cachedTranscript = transcriptCache.get(cacheKey);
    if (cachedTranscript) {
      writeJson(response, 200, {
        transcript: cachedTranscript,
        provider: "deepgram",
        model,
        durationMs: 0,
        audioBytes: audioBytes.length,
        audioHash,
        cacheHit: true,
      });
      return;
    }
    const startedAt = Date.now();
    const transcript = await transcribeWithDeepgram({
      apiKey: process.env.DEEPGRAM_API_KEY,
      audioBytes,
      mimeType,
      language: normalizedLanguage,
      model,
    });
    transcriptCache.set(cacheKey, transcript);

    writeJson(response, 200, {
      transcript,
      provider: "deepgram",
      model,
      durationMs: Date.now() - startedAt,
      audioBytes: audioBytes.length,
      audioHash,
      cacheHit: false,
    });
  } catch (error) {
    const message = error && error.message ? error.message : String(error);
    console.error("[local-stt] transcription failed", error);
    writeJson(response, 500, {error: message});
  }
});

server.listen(port, host, () => {
  console.log(`[local-stt] listening on http://${host}:${port}`);
  console.log(`[local-stt] health check: http://${host}:${port}/health`);
  console.log("[local-stt] provider: deepgram");
  console.log(`[local-stt] model: ${model}`);
});

function setCorsHeaders(response) {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function writeJson(response, statusCode, payload) {
  response.writeHead(statusCode, {"Content-Type": "application/json; charset=utf-8"});
  response.end(JSON.stringify(payload));
}

function readRequestBody(request, limitBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on("data", (chunk) => {
      size += chunk.length;
      if (limitBytes !== null && size > limitBytes) {
        reject(new Error("Request body is too large."));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const index = trimmed.indexOf("=");
    if (index === -1) {
      continue;
    }
    const key = trimmed.slice(0, index).trim();
    const rawValue = trimmed.slice(index + 1).trim();
    if (!key || process.env[key]) {
      continue;
    }
    process.env[key] = rawValue.replace(/^['"]|['"]$/g, "");
  }
}

async function transcribeWithDeepgram({apiKey, audioBytes, mimeType, language, model}) {
  const url = new URL(process.env.DEEPGRAM_API_URL || "https://api.deepgram.com/v1/listen");
  url.searchParams.set("model", model || "nova-3");
  url.searchParams.set("language", normalizeDeepgramLanguage(language));
  url.searchParams.set("smart_format", process.env.DEEPGRAM_SMART_FORMAT || "true");
  for (const keyterm of deepgramKeyterms()) {
    url.searchParams.append("keyterm", keyterm);
  }

  const deepgramResponse = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Token ${apiKey}`,
      "Content-Type": mimeType,
    },
    body: audioBytes,
  });
  const raw = await deepgramResponse.text();
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    payload = undefined;
  }
  if (!deepgramResponse.ok) {
    throw new Error(`Deepgram transcription failed: HTTP ${deepgramResponse.status} ${raw.slice(0, 500)}`);
  }
  const transcript = payload?.results?.channels?.[0]?.alternatives?.[0]?.transcript;
  if (typeof transcript !== "string") {
    throw new Error("Deepgram transcription response did not include a transcript.");
  }
  return transcript.trim();
}

function normalizeDeepgramLanguage(language) {
  const normalized = String(language || "").trim().toLowerCase();
  if (!normalized || normalized === "ko" || normalized === "ko-kr") {
    return process.env.DEEPGRAM_LANGUAGE || "ko-KR";
  }
  return normalized;
}

function deepgramKeyterms() {
  return String(process.env.DEEPGRAM_KEYTERMS || "")
    .split(",")
    .map((term) => term.trim())
    .filter(Boolean)
    .slice(0, 100);
}
