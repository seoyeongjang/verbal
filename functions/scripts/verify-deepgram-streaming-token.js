const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const googleServices = JSON.parse(
  fs.readFileSync(
    path.join(
      repoRoot,
      "apps",
      "mobile",
      "android",
      "app",
      "google-services.json",
    ),
    "utf8",
  ),
);
const projectId = googleServices.project_info.project_id;
const apiKey = googleServices.client[0].api_key[0].current_key;
const region = process.env.FIREBASE_FUNCTIONS_REGION || "asia-northeast3";
const phoneNumber = process.env.SMOKE_SENDER_PHONE || "+16505550102";
const smsCode = process.env.SMOKE_SENDER_CODE || "123456";
const defaultRelayUrl =
  "https://verbal-deepgram-relay-uhnknahebq-du.a.run.app";

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

async function main() {
  const auth = await signInTestPhone(phoneNumber, smsCode);
  const relayReport = await verifyRelayStreamingPath();
  if (relayReport.available) {
    console.log(JSON.stringify(relayReport, null, 2));
    return;
  }

  const result = await callFunction(auth.idToken, "createDeepgramStreamingToken", {
    language: process.env.DEEPGRAM_LANGUAGE || "ko-KR",
  });
  const available = result.available !== false && Boolean(result.accessToken);
  const report = {
    available,
    source: "callable-token",
    reason: result.reason || null,
    relayReason: relayReport.reason,
    expiresIn: result.expiresIn || null,
    hasUrl: Boolean(result.url),
    urlHost: result.url ? new URL(result.url).host : null,
    model: result.model || null,
    language: result.language || null,
    sampleRate: result.sampleRate || null,
    channels: result.channels || null,
    encoding: result.encoding || null,
  };
  console.log(JSON.stringify(report, null, 2));
  if (!available) {
    process.exitCode = 2;
  }
}

async function verifyRelayStreamingPath() {
  const relayUrl = (process.env.VERBAL_DEEPGRAM_RELAY_URL || defaultRelayUrl).trim();
  if (!relayUrl) {
    return {
      available: false,
      source: "relay",
      reason: "relay_url_not_configured",
    };
  }
  let healthUrl;
  try {
    const parsed = new URL(relayUrl);
    const scheme =
      parsed.protocol === "wss:"
        ? "https:"
        : parsed.protocol === "ws:"
          ? "http:"
          : parsed.protocol;
    parsed.protocol = scheme;
    parsed.pathname = "/";
    parsed.search = "";
    parsed.hash = "";
    healthUrl = parsed.toString();
  } catch {
    return {
      available: false,
      source: "relay",
      reason: "relay_url_invalid",
      url: relayUrl,
    };
  }

  try {
    const response = await fetch(healthUrl, { method: "GET" });
    const raw = await response.text();
    const health = raw ? safeJson(raw) : {};
    const available =
      response.ok && health.ok === true && health.providers?.deepgram === true;
    return {
      available,
      source: "relay",
      reason: available ? null : "relay_deepgram_unavailable",
      hasUrl: true,
      urlHost: new URL(healthUrl).host,
      model: health.defaults?.deepgramModel || null,
      language: process.env.DEEPGRAM_LANGUAGE || "ko-KR",
      sampleRate: health.defaults?.inputSampleRate || null,
      channels: 1,
      encoding: "linear16",
      health,
    };
  } catch (error) {
    return {
      available: false,
      source: "relay",
      reason: "relay_health_failed",
      error: error.message || String(error),
      hasUrl: true,
      urlHost: new URL(healthUrl).host,
    };
  }
}

async function signInTestPhone(number, code) {
  const sendResponse = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=${apiKey}`,
    {
      phoneNumber: number,
      recaptchaToken: "ignored-for-firebase-test-phone",
    },
  );
  return postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=${apiKey}`,
    {
      sessionInfo: sendResponse.sessionInfo,
      code,
    },
  );
}

async function callFunction(idToken, name, data) {
  const response = await fetch(
    `https://${region}-${projectId}.cloudfunctions.net/${name}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${idToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ data }),
    },
  );
  const raw = await response.text();
  const body = raw ? safeJson(raw) : {};
  if (!response.ok || body.error) {
    throw new Error(
      `Callable ${name} failed (${response.status}): ${JSON.stringify(
        body.error || body,
      )}`,
    );
  }
  return body.result || {};
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const raw = await response.text();
  const json = raw ? safeJson(raw) : {};
  if (!response.ok || json.error) {
    throw new Error(`HTTP ${response.status}: ${JSON.stringify(json.error || json)}`);
  }
  return json;
}

function safeJson(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return { raw: raw.slice(0, 500) };
  }
}
