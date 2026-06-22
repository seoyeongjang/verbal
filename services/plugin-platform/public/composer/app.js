const state = {
  recorder: null,
  chunks: [],
  audioBlob: null,
  audioUrl: "",
  card: null,
};

const els = {
  coreApiBase: document.querySelector("#coreApiBase"),
  platform: document.querySelector("#platform"),
  partnerId: document.querySelector("#partnerId"),
  keyId: document.querySelector("#keyId"),
  apiKey: document.querySelector("#apiKey"),
  senderName: document.querySelector("#senderName"),
  recordButton: document.querySelector("#recordButton"),
  stopButton: document.querySelector("#stopButton"),
  audioFile: document.querySelector("#audioFile"),
  status: document.querySelector("#status"),
  transcript: document.querySelector("#transcript"),
  transcribeButton: document.querySelector("#transcribeButton"),
  cardButton: document.querySelector("#cardButton"),
  copyTextButton: document.querySelector("#copyTextButton"),
  audioPanel: document.querySelector("#audioPanel"),
  audioUrl: document.querySelector("#audioUrl"),
  cardOutput: document.querySelector("#cardOutput"),
  copyCardButton: document.querySelector("#copyCardButton"),
  shareButton: document.querySelector("#shareButton"),
};

init();

function init() {
  window.addEventListener("unhandledrejection", (event) => {
    setStatus(event.reason?.message || "Request failed.");
  });
  window.addEventListener("error", (event) => {
    setStatus(event.message || "Unexpected error.");
  });
  const params = new URLSearchParams(location.search);
  els.platform.value = params.get("platform") || "slack";
  els.coreApiBase.value =
    localStorage.getItem("verbal.coreApiBase") || params.get("coreApiBase") || "";
  els.partnerId.value =
    localStorage.getItem("verbal.partnerId") || params.get("partnerId") || "";
  els.keyId.value = localStorage.getItem("verbal.keyId") || params.get("keyId") || "";

  els.recordButton.addEventListener("click", startRecording);
  els.stopButton.addEventListener("click", stopRecording);
  els.audioFile.addEventListener("change", useUploadedAudio);
  els.transcribeButton.addEventListener("click", transcribeAudio);
  els.cardButton.addEventListener("click", renderCard);
  els.copyTextButton.addEventListener("click", () =>
    copyToClipboard(els.transcript.value),
  );
  els.copyCardButton.addEventListener("click", () =>
    copyToClipboard(JSON.stringify(state.card, null, 2)),
  );
  els.shareButton.addEventListener("click", shareResult);
}

async function startRecording() {
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    setStatus("This browser does not support in-page audio recording.");
    return;
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  state.chunks = [];
  state.recorder = new MediaRecorder(stream);
  state.recorder.addEventListener("dataavailable", (event) => {
    if (event.data.size > 0) {
      state.chunks.push(event.data);
    }
  });
  state.recorder.addEventListener("stop", () => {
    stream.getTracks().forEach((track) => track.stop());
    state.audioBlob = new Blob(state.chunks, {
      type: state.recorder.mimeType || "audio/webm",
    });
    els.transcribeButton.disabled = false;
    setStatus("Recording ready. Transcribe audio to continue.");
  });
  state.recorder.start();
  els.recordButton.disabled = true;
  els.stopButton.disabled = false;
  setStatus("Recording...");
}

function stopRecording() {
  if (!state.recorder) {
    return;
  }
  state.recorder.stop();
  els.recordButton.disabled = false;
  els.stopButton.disabled = true;
}

function useUploadedAudio() {
  const file = els.audioFile.files?.[0];
  if (!file) {
    return;
  }
  state.audioBlob = file;
  els.transcribeButton.disabled = false;
  setStatus(`Selected ${file.name}.`);
}

async function transcribeAudio() {
  if (!state.audioBlob) {
    setStatus("Record or upload audio first.");
    return;
  }
  saveConnection();
  const audioBase64 = await blobToBase64(state.audioBlob);
  setStatus("Sending audio to Verbal Core API...");
  const result = await postCoreApi("/v1/transcriptions", {
    audioBase64,
    contentType: state.audioBlob.type || "audio/mp4",
    language: "ko",
    storeAudio: true,
    retentionDays: 1,
  });
  els.transcript.value = result.transcript || "";
  state.audioUrl = result.audioUrl || "";
  els.audioPanel.hidden = !state.audioUrl;
  els.audioUrl.textContent = state.audioUrl;
  els.cardButton.disabled = !els.transcript.value.trim();
  els.copyTextButton.disabled = !els.transcript.value.trim();
  setStatus(result.sttStatus === "completed" ? "Transcript ready." : "STT returned no transcript.");
}

async function renderCard() {
  if (!els.transcript.value.trim()) {
    setStatus("Transcript is required before rendering a card.");
    return;
  }
  saveConnection();
  state.card = await postCoreApi("/v1/message-cards", {
    platform: els.platform.value,
    transcript: els.transcript.value,
    audioUrl: state.audioUrl,
    senderName: els.senderName.value,
  });
  els.cardOutput.textContent = JSON.stringify(state.card, null, 2);
  els.copyCardButton.disabled = false;
  els.shareButton.disabled = false;
  setStatus("Messenger card rendered.");
}

async function postCoreApi(path, body) {
  const base = els.coreApiBase.value.trim().replace(/\/+$/, "");
  if (!base || !els.partnerId.value || !els.keyId.value || !els.apiKey.value) {
    throw new Error("Core API base URL, Partner ID, Key ID, and API key are required.");
  }
  const response = await fetch(`${base}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-verbal-partner-id": els.partnerId.value.trim(),
      "x-verbal-key-id": els.keyId.value.trim(),
      "x-verbal-api-key": els.apiKey.value,
    },
    body: JSON.stringify(body),
  });
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json.error?.message || "Core API request failed.");
  }
  return json;
}

async function blobToBase64(blob) {
  const buffer = await blob.arrayBuffer();
  let binary = "";
  for (const byte of new Uint8Array(buffer)) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function saveConnection() {
  localStorage.setItem("verbal.coreApiBase", els.coreApiBase.value.trim());
  localStorage.setItem("verbal.partnerId", els.partnerId.value.trim());
  localStorage.setItem("verbal.keyId", els.keyId.value.trim());
}

async function copyToClipboard(value) {
  await navigator.clipboard.writeText(value || "");
  setStatus("Copied.");
}

async function shareResult() {
  const text = state.card?.plainText || els.transcript.value;
  if (navigator.share) {
    await navigator.share({ text });
    setStatus("Shared.");
    return;
  }
  await copyToClipboard(text);
}

function setStatus(message) {
  els.status.textContent = message;
}
