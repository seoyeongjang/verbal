import http from "node:http";
import crypto from "node:crypto";
import { URL } from "node:url";
import admin from "firebase-admin";
import WebSocket, { WebSocketServer } from "ws";

const port = Number(process.env.PORT || 8080);
const deepgramApiKey = normalizeSecret(process.env.DEEPGRAM_API_KEY || "");
const openaiApiKey = normalizeSecret(process.env.OPENAI_API_KEY || "");
const deepgramModel = process.env.DEEPGRAM_MODEL || "nova-3";
const openaiModel =
  process.env.OPENAI_REALTIME_TRANSCRIPTION_MODEL ||
  process.env.OPENAI_REALTIME_MODEL ||
  "gpt-realtime-whisper";
const openaiConnectModel =
  process.env.OPENAI_REALTIME_CONNECT_MODEL || "gpt-realtime-2";
const openaiDelay = normalizeOpenAiDelay(
  process.env.OPENAI_TRANSCRIPTION_DELAY,
  "minimal",
);
const openaiCommitIntervalMs = normalizeBoundedInteger(
  process.env.OPENAI_COMMIT_INTERVAL_MS,
  150,
  100,
  1500,
);
const mockOpenAiRealtime =
  normalizeOptionalBoolean(process.env.MOCK_OPENAI_REALTIME) === "true";
const mockOpenAiTranscript =
  process.env.MOCK_OPENAI_TRANSCRIPT ||
  "\uC624\uB298 \uC624\uD6C4 \uC138\uC2DC\uC5D0 \uD68C\uC758 \uAC00\uB2A5\uD569\uB2C8\uB2E4.";
const defaultLanguage = process.env.DEEPGRAM_LANGUAGE || "ko";
const sampleRate = Number(process.env.DEEPGRAM_SAMPLE_RATE || 16000);
const openaiSampleRate = 24000;
const endpointingMs = normalizePositiveInteger(
  process.env.DEEPGRAM_ENDPOINTING_MS,
  "50",
);
const utteranceEndMs = normalizeUtteranceEndMs(
  process.env.DEEPGRAM_UTTERANCE_END_MS,
);
const defaultNoDelay =
  normalizeOptionalBoolean(process.env.DEEPGRAM_NO_DELAY) || "true";
const defaultSmartFormat = normalizeBoolean(
  process.env.DEEPGRAM_STREAMING_SMART_FORMAT,
  "false",
);
const defaultPunctuate = normalizeBoolean(
  process.env.DEEPGRAM_STREAMING_PUNCTUATE,
  "false",
);
const defaultNumerals = normalizeBoolean(
  process.env.DEEPGRAM_STREAMING_NUMERALS,
  "false",
);

if (!admin.apps.length) {
  admin.initializeApp();
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url || "/", "http://localhost");
  console.log("http request", request.method, url.pathname);
  if (url.pathname === "/healthz" || url.pathname === "/") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        ok: true,
        providers: {
          deepgram: Boolean(deepgramApiKey),
          openai: Boolean(openaiApiKey) || mockOpenAiRealtime,
        },
        defaults: {
          deepgramModel,
          openaiModel,
          openaiConnectModel,
          openaiDelay,
          openaiCommitIntervalMs,
          openaiSampleRate,
          inputSampleRate: sampleRate,
          mockOpenAiRealtime,
        },
      }),
    );
    return;
  }
  response.writeHead(404, { "content-type": "application/json" });
  response.end(JSON.stringify({ error: "not_found" }));
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", async (request, socket, head) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
    if (url.pathname !== "/stt" && url.pathname !== "/openai-stt") {
      socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
      socket.destroy();
      return;
    }
    const requestedProvider = cleanParam(
      url.searchParams.get("provider"),
      url.pathname === "/openai-stt" ? "openai" : "deepgram",
    ).toLowerCase();
    const provider = requestedProvider === "openai" ? "openai" : "deepgram";
    if (provider === "deepgram" && !deepgramApiKey) {
      socket.write("HTTP/1.1 503 Service Unavailable\r\n\r\n");
      socket.destroy();
      return;
    }
    if (provider === "openai" && !openaiApiKey && !mockOpenAiRealtime) {
      socket.write("HTTP/1.1 503 Service Unavailable\r\n\r\n");
      socket.destroy();
      return;
    }
    const token = bearerToken(request.headers.authorization || "");
    if (!token) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }
    const decoded = await admin.auth().verifyIdToken(token);
    wss.handleUpgrade(request, socket, head, (client) => {
      wss.emit("connection", client, request, {
        uid: decoded.uid,
        provider,
        language: cleanParam(url.searchParams.get("language"), defaultLanguage),
        model: cleanParam(
          url.searchParams.get("model"),
          provider === "openai" ? openaiModel : deepgramModel,
        ),
        openaiDelay: normalizeOpenAiDelay(
          url.searchParams.get("delay"),
          openaiDelay,
        ),
        openaiCommitIntervalMs: normalizeBoundedInteger(
          url.searchParams.get("commit_ms"),
          openaiCommitIntervalMs,
          100,
          1500,
        ),
        endpointing: normalizePositiveInteger(
          url.searchParams.get("endpointing"),
          endpointingMs,
        ),
        noDelay:
          normalizeOptionalBoolean(url.searchParams.get("no_delay")) ||
          defaultNoDelay,
        smartFormat: normalizeBoolean(
          url.searchParams.get("smart_format"),
          defaultSmartFormat,
        ),
        punctuate: normalizeBoolean(
          url.searchParams.get("punctuate"),
          defaultPunctuate,
        ),
        numerals: normalizeBoolean(
          url.searchParams.get("numerals"),
          defaultNumerals,
        ),
      });
    });
  } catch (error) {
    console.error("upgrade failed", error);
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
  }
});

wss.on("connection", (client, _request, session) => {
  if (session.provider === "openai") {
    startOpenAiRelay(client, session);
    return;
  }

  const deepgramUrl = new URL("wss://api.deepgram.com/v1/listen");
  deepgramUrl.searchParams.set("model", session.model);
  deepgramUrl.searchParams.set("language", normalizeLanguage(session.language));
  deepgramUrl.searchParams.set("encoding", "linear16");
  deepgramUrl.searchParams.set("sample_rate", String(sampleRate));
  deepgramUrl.searchParams.set("channels", "1");
  deepgramUrl.searchParams.set("interim_results", "true");
  deepgramUrl.searchParams.set("smart_format", session.smartFormat);
  deepgramUrl.searchParams.set("punctuate", session.punctuate);
  deepgramUrl.searchParams.set("numerals", session.numerals);
  if (session.noDelay) {
    deepgramUrl.searchParams.set("no_delay", session.noDelay);
  }
  deepgramUrl.searchParams.set("endpointing", session.endpointing);
  if (utteranceEndMs) {
    deepgramUrl.searchParams.set("utterance_end_ms", utteranceEndMs);
  }
  deepgramUrl.searchParams.set("vad_events", "true");

  const deepgram = new WebSocket(deepgramUrl, {
    headers: { Authorization: `Token ${deepgramApiKey}` },
  });
  let opened = false;
  let audioBytes = 0;
  const queued = [];

  deepgram.on("open", () => {
    opened = true;
    console.log("deepgram relay connected", {
      uid: session.uid,
      language: normalizeLanguage(session.language),
      model: session.model,
      endpointing: session.endpointing,
      noDelay: session.noDelay,
      smartFormat: session.smartFormat,
      punctuate: session.punctuate,
      numerals: session.numerals,
      queued: queued.length,
    });
    while (queued.length) {
      const item = queued.shift();
      sendToDeepgram(deepgram, item.message, item.isBinary);
    }
  });

  deepgram.on("message", (message) => {
    logDeepgramResult(message, session.uid);
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });

  deepgram.on("error", (error) => {
    console.error("deepgram socket error", { uid: session.uid, error });
    sendJson(client, { type: "Error", message: "deepgram_socket_error" });
  });

  deepgram.on("unexpected-response", (_request, response) => {
    let body = "";
    response.on("data", (chunk) => {
      body += chunk.toString("utf8");
    });
    response.on("end", () => {
      console.error("deepgram socket rejected", {
        uid: session.uid,
        statusCode: response.statusCode,
        body: body.slice(0, 500),
      });
      sendJson(client, { type: "Error", message: "deepgram_socket_rejected" });
    });
  });

  deepgram.on("close", () => {
    console.log("deepgram relay closed", {
      uid: session.uid,
      audioBytes,
    });
    closeSocket(client, 1000, "deepgram_closed");
  });

  client.on("message", (message, isBinary) => {
    if (isBinary) {
      audioBytes += message.length;
    }
    if (!opened) {
      queued.push({ message, isBinary });
      return;
    }
    sendToDeepgram(deepgram, message, isBinary);
  });

  client.on("close", () => {
    closeSocket(deepgram, 1000, "client_closed");
  });

  client.on("error", () => {
    closeSocket(deepgram, 1011, "client_error");
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`verbal deepgram relay listening on ${port}`);
});

function bearerToken(value) {
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match ? match[1].trim() : "";
}

function normalizeSecret(value) {
  return String(value || "")
    .trim()
    .replace(/^['"]|['"]$/g, "")
    .replace(/[\r\n\t ]+/g, "");
}

function cleanParam(value, fallback) {
  const next = (value || "").trim();
  return next.length > 0 && next.length <= 64 ? next : fallback;
}

function normalizePositiveInteger(value, fallback) {
  const next = Number(String(value || "").trim());
  return Number.isInteger(next) && next > 0 ? String(next) : fallback;
}

function normalizeBoundedInteger(value, fallback, min, max) {
  const next = Number(String(value || "").trim());
  if (!Number.isInteger(next)) return fallback;
  if (next < min) return min;
  if (next > max) return max;
  return next;
}

function normalizeOpenAiDelay(value, fallback) {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase();
  return ["minimal", "low", "medium", "high", "xhigh"].includes(raw)
    ? raw
    : fallback;
}

function normalizeBoolean(value, fallback) {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase();
  if (raw === "true" || raw === "1" || raw === "yes") return "true";
  if (raw === "false" || raw === "0" || raw === "no") return "false";
  return fallback;
}

function normalizeOptionalBoolean(value) {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase();
  if (raw === "true" || raw === "1" || raw === "yes") return "true";
  if (raw === "false" || raw === "0" || raw === "no") return "false";
  return "";
}

function normalizeUtteranceEndMs(value) {
  const next = Number(String(value || "").trim());
  // Deepgram rejects utterance_end_ms below 1000ms for live transcription.
  return Number.isInteger(next) && next >= 1000 ? String(next) : "";
}

function normalizeLanguage(language) {
  const raw = cleanParam(language, defaultLanguage).toLowerCase();
  if (raw.startsWith("ko")) return "ko";
  if (raw.startsWith("en")) return "en";
  if (raw.startsWith("ja")) return "ja";
  if (raw.startsWith("zh")) return "zh";
  return raw;
}

function sendJson(socket, value) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(value));
  }
}

function sendToDeepgram(socket, message, isBinary) {
  if (socket.readyState !== WebSocket.OPEN) {
    return;
  }
  if (!isBinary) {
    const text = message.toString("utf8");
    if (text.includes("Finalize")) {
      socket.send(JSON.stringify({ type: "Finalize" }));
      return;
    }
  }
  socket.send(message, { binary: isBinary });
}

function startOpenAiRelay(client, session) {
  if (mockOpenAiRealtime) {
    startMockOpenAiRelay(client, session);
    return;
  }

  const openaiUrl = new URL("wss://api.openai.com/v1/realtime");
  openaiUrl.searchParams.set("model", openaiConnectModel);

  const openai = new WebSocket(openaiUrl, {
    headers: {
      Authorization: `Bearer ${openaiApiKey}`,
      "OpenAI-Safety-Identifier": stableSafetyIdentifier(session.uid),
      ...optionalOpenAiRealtimeHeaders(),
    },
  });
  const state = {
    uid: session.uid,
    opened: false,
    queued: [],
    clientAudioBytes: 0,
    openaiAudioBytes: 0,
    pendingAudioBytes: 0,
    finalRequested: false,
    closeTimer: null,
    commitTimer: null,
    transcriptByItem: new Map(),
    itemOrder: [],
    lastEmittedTranscript: "",
  };

  openai.on("open", () => {
    state.opened = true;
    console.log("openai relay connected", {
      uid: session.uid,
      language: normalizeLanguage(session.language),
      model: session.model,
      delay: session.openaiDelay,
      commitIntervalMs: session.openaiCommitIntervalMs,
    });
    sendOpenAiSessionUpdate(openai, session);
    state.commitTimer = setInterval(() => {
      commitOpenAiAudio(openai, state, "interval");
    }, session.openaiCommitIntervalMs);
    while (state.queued.length) {
      const item = state.queued.shift();
      sendToOpenAi(openai, item.message, item.isBinary, state);
    }
  });

  openai.on("message", (message) => {
    handleOpenAiMessage(message, client, openai, state);
  });

  openai.on("error", (error) => {
    console.error("openai socket error", { uid: session.uid, error });
    sendJson(client, { type: "Error", message: "openai_socket_error" });
  });

  openai.on("unexpected-response", (_request, response) => {
    let body = "";
    response.on("data", (chunk) => {
      body += chunk.toString("utf8");
    });
    response.on("end", () => {
      console.error("openai socket rejected", {
        uid: session.uid,
        statusCode: response.statusCode,
        body: body.slice(0, 500),
      });
      sendJson(client, { type: "Error", message: "openai_socket_rejected" });
    });
  });

  openai.on("close", () => {
    if (state.commitTimer) {
      clearInterval(state.commitTimer);
      state.commitTimer = null;
    }
    if (state.closeTimer) {
      clearTimeout(state.closeTimer);
      state.closeTimer = null;
    }
    console.log("openai relay closed", {
      uid: session.uid,
      clientAudioBytes: state.clientAudioBytes,
      openaiAudioBytes: state.openaiAudioBytes,
      transcriptLength: joinedOpenAiTranscript(state).length,
    });
    closeSocket(client, 1000, "openai_closed");
  });

  client.on("message", (message, isBinary) => {
    if (isBinary) {
      state.clientAudioBytes += message.length;
    }
    if (!state.opened) {
      state.queued.push({ message, isBinary });
      return;
    }
    sendToOpenAi(openai, message, isBinary, state);
  });

  client.on("close", () => {
    commitOpenAiAudio(openai, state, "client_closed");
    closeSocket(openai, 1000, "client_closed");
  });

  client.on("error", () => {
    closeSocket(openai, 1011, "client_error");
  });
}

function startMockOpenAiRelay(client, session) {
  const state = {
    uid: session.uid,
    audioBytes: 0,
    interimSent: false,
    finalSent: false,
    transcript: mockOpenAiTranscript,
    interimTimer: null,
  };

  console.log("mock openai realtime relay connected", {
    uid: state.uid,
    language: normalizeLanguage(session.language),
    transcriptLength: state.transcript.length,
  });

  client.on("message", (message, isBinary) => {
    if (isBinary) {
      state.audioBytes += message.length;
      if (!state.interimSent && state.audioBytes >= sampleRate * 2 * 0.35) {
        state.interimSent = true;
        state.interimTimer = setTimeout(() => {
          sendMockOpenAiTranscript(client, state, false);
        }, 80);
      }
      return;
    }

    const text = message.toString("utf8");
    if (text.includes("Finalize")) {
      if (state.interimTimer) {
        clearTimeout(state.interimTimer);
        state.interimTimer = null;
      }
      sendMockOpenAiTranscript(client, state, true);
      setTimeout(() => closeSocket(client, 1000, "mock_openai_final"), 80);
    }
  });

  client.on("close", () => {
    if (state.interimTimer) {
      clearTimeout(state.interimTimer);
      state.interimTimer = null;
    }
    console.log("mock openai realtime relay closed", {
      uid: state.uid,
      audioBytes: state.audioBytes,
      finalSent: state.finalSent,
    });
  });
}

function sendMockOpenAiTranscript(client, state, isFinal) {
  if (client.readyState !== WebSocket.OPEN) {
    return;
  }
  if (isFinal) {
    state.finalSent = true;
  }
  console.log("mock openai realtime result", {
    uid: state.uid,
    transcriptLength: state.transcript.length,
    isFinal,
    audioBytes: state.audioBytes,
  });
  sendJson(client, {
    type: "Results",
    is_final: isFinal,
    speech_final: isFinal,
    channel: {
      alternatives: [{ transcript: state.transcript }],
    },
  });
}

function optionalOpenAiRealtimeHeaders() {
  return normalizeOptionalBoolean(process.env.OPENAI_REALTIME_BETA_HEADER)
    ? { "OpenAI-Beta": "realtime=v1" }
    : {};
}

function stableSafetyIdentifier(uid) {
  return crypto
    .createHash("sha256")
    .update(`verbal:${uid}`)
    .digest("hex")
    .slice(0, 64);
}

function sendOpenAiSessionUpdate(openai, session) {
  sendJson(openai, {
    type: "session.update",
    session: {
      type: "transcription",
      audio: {
        input: {
          format: {
            type: "audio/pcm",
            rate: openaiSampleRate,
          },
          transcription: {
            model: session.model,
            language: normalizeLanguage(session.language),
            delay: session.openaiDelay,
          },
          turn_detection: null,
        },
      },
    },
  });
}

function sendToOpenAi(openai, message, isBinary, state) {
  if (openai.readyState !== WebSocket.OPEN) {
    return;
  }
  if (!isBinary) {
    const text = message.toString("utf8");
    if (text.includes("Finalize")) {
      state.finalRequested = true;
      commitOpenAiAudio(openai, state, "finalize");
      if (!state.closeTimer) {
        state.closeTimer = setTimeout(() => {
          closeSocket(openai, 1000, "finalize_done");
        }, 1800);
      }
      return;
    }
    return;
  }
  const source = Buffer.isBuffer(message) ? message : Buffer.from(message);
  const audio = resamplePcm16Mono(source, sampleRate, openaiSampleRate);
  state.openaiAudioBytes += audio.length;
  state.pendingAudioBytes += audio.length;
  sendJson(openai, {
    type: "input_audio_buffer.append",
    audio: audio.toString("base64"),
  });
}

function commitOpenAiAudio(openai, state, reason) {
  if (openai.readyState !== WebSocket.OPEN || state.pendingAudioBytes <= 0) {
    return;
  }
  sendJson(openai, { type: "input_audio_buffer.commit" });
  console.log("openai relay committed audio", {
    uid: state.uid,
    reason,
    pendingAudioBytes: state.pendingAudioBytes,
  });
  state.pendingAudioBytes = 0;
}

function handleOpenAiMessage(message, client, openai, state) {
  let payload;
  try {
    payload = JSON.parse(message.toString("utf8"));
  } catch {
    return;
  }
  const type = String(payload?.type || "");
  if (type === "error" || payload?.error) {
    console.error("openai relay api error", {
      uid: state.uid,
      message:
        payload?.error?.message ||
        payload?.message ||
        payload?.error ||
        "openai_error",
    });
    sendJson(client, { type: "Error", message: "openai_api_error" });
    return;
  }

  const itemId = openAiItemId(payload);
  const delta = openAiTranscriptDelta(payload);
  if (delta) {
    rememberOpenAiTranscript(state, itemId, delta, true);
    emitOpenAiTranscript(client, state, false);
    return;
  }

  const completed = openAiCompletedTranscript(payload);
  if (completed) {
    rememberOpenAiTranscript(state, itemId, completed, false);
    emitOpenAiTranscript(client, state, true);
    if (state.finalRequested && state.closeTimer) {
      clearTimeout(state.closeTimer);
      state.closeTimer = setTimeout(() => {
        closeSocket(client, 1000, "openai_final_transcript");
        closeSocket(openai, 1000, "openai_final_transcript");
      }, 250);
    }
    return;
  }

  if (type.endsWith(".failed")) {
    console.error("openai transcription failed", {
      uid: state.uid,
      type,
      error: payload?.error || payload,
    });
  }
}

function openAiItemId(payload) {
  return String(
    payload?.item_id ||
      payload?.itemId ||
      payload?.item?.id ||
      payload?.response_id ||
      payload?.id ||
      "default",
  );
}

function openAiTranscriptDelta(payload) {
  const type = String(payload?.type || "");
  if (!type.includes("transcription") || !type.endsWith(".delta")) {
    return "";
  }
  return String(
    payload?.delta || payload?.transcript_delta || payload?.text_delta || "",
  ).trim();
}

function openAiCompletedTranscript(payload) {
  const type = String(payload?.type || "");
  if (!type.includes("transcription") || !type.endsWith(".completed")) {
    return "";
  }
  return String(
    payload?.transcript || payload?.text || payload?.output_text || "",
  ).trim();
}

function rememberOpenAiTranscript(state, itemId, text, append) {
  const id = itemId || "default";
  if (!state.transcriptByItem.has(id)) {
    state.itemOrder.push(id);
    state.transcriptByItem.set(id, "");
  }
  const previous = state.transcriptByItem.get(id) || "";
  const next = append ? `${previous}${text}` : text;
  state.transcriptByItem.set(id, next.trim());
}

function emitOpenAiTranscript(client, state, isFinal) {
  const transcript = joinedOpenAiTranscript(state);
  if (!transcript || (!isFinal && transcript === state.lastEmittedTranscript)) {
    return;
  }
  state.lastEmittedTranscript = transcript;
  console.log("openai relay result", {
    uid: state.uid,
    transcriptLength: transcript.length,
    isFinal,
  });
  sendJson(client, {
    type: "Results",
    is_final: isFinal,
    speech_final: isFinal,
    channel: {
      alternatives: [{ transcript }],
    },
  });
}

function joinedOpenAiTranscript(state) {
  return state.itemOrder
    .map((id) => state.transcriptByItem.get(id) || "")
    .filter((text) => text.trim())
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

function resamplePcm16Mono(input, inputRate, outputRate) {
  if (!input.length || inputRate === outputRate) {
    return input;
  }
  const inputSamples = Math.floor(input.length / 2);
  if (inputSamples <= 1) {
    return input;
  }
  const outputSamples = Math.max(
    1,
    Math.round((inputSamples * outputRate) / inputRate),
  );
  const output = Buffer.alloc(outputSamples * 2);
  const ratio = inputRate / outputRate;
  for (let index = 0; index < outputSamples; index += 1) {
    const position = index * ratio;
    const leftIndex = Math.floor(position);
    const rightIndex = Math.min(leftIndex + 1, inputSamples - 1);
    const weight = position - leftIndex;
    const left = input.readInt16LE(leftIndex * 2);
    const right = input.readInt16LE(rightIndex * 2);
    const value = Math.round(left + (right - left) * weight);
    output.writeInt16LE(Math.max(-32768, Math.min(32767, value)), index * 2);
  }
  return output;
}

function logDeepgramResult(message, uid) {
  try {
    const payload = JSON.parse(message.toString("utf8"));
    if (payload?.type === "Results") {
      const transcript =
        payload?.channel?.alternatives?.[0]?.transcript?.trim() || "";
      if (transcript || payload.is_final || payload.speech_final) {
        console.log("deepgram relay result", {
          uid,
          transcriptLength: transcript.length,
          isFinal: payload.is_final === true,
          speechFinal: payload.speech_final === true,
        });
      }
      return;
    }
    if (payload?.type === "Error") {
      console.error("deepgram relay api error", {
        uid,
        message: payload.message || payload.err_code || "deepgram_error",
      });
    }
  } catch {
    // Ignore non-JSON frames.
  }
}

function closeSocket(socket, code, reason) {
  if (
    socket.readyState === WebSocket.OPEN ||
    socket.readyState === WebSocket.CONNECTING
  ) {
    socket.close(code, reason);
  }
}
