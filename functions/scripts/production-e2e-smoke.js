const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const admin = require("firebase-admin");

const repoRoot = path.resolve(__dirname, "..", "..");
const googleServicesPath = path.join(
  repoRoot,
  "apps",
  "mobile",
  "android",
  "app",
  "google-services.json",
);
const googleServices = JSON.parse(fs.readFileSync(googleServicesPath, "utf8"));
const projectInfo = googleServices.project_info;
const androidClient = googleServices.client[0];
const projectId = projectInfo.project_id;
const storageBucket = projectInfo.storage_bucket;
const apiKey = androidClient.api_key[0].current_key;
const appId = androidClient.client_info.mobilesdk_app_id;
const region = process.env.FIREBASE_FUNCTIONS_REGION || "asia-northeast3";
const runId =
  process.env.SMOKE_RUN_ID ||
  new Date().toISOString().replace(/\D/g, "").slice(0, 14);

const sender = {
  phoneNumber: process.env.SMOKE_SENDER_PHONE || "+16505550102",
  smsCode: process.env.SMOKE_SENDER_CODE || "123456",
  uid: "",
  handle: `e2e_a_${runId.slice(-8)}`,
  displayName: "E2E Sender",
};
const receiver = {
  phoneNumber: process.env.SMOKE_RECEIVER_PHONE || "+16505550103",
  smsCode: process.env.SMOKE_RECEIVER_CODE || "123456",
  uid: "",
  handle: `e2e_b_${runId.slice(-8)}`,
  displayName: "E2E Receiver",
};

const artifactDir = path.join(repoRoot, "artifacts");
const audioPath = path.join(artifactDir, "e2e-deepgram-test.wav");
const resultPath = path.join(
  artifactDir,
  `production-e2e-smoke-${runId}.json`,
);

admin.initializeApp({
  projectId,
  storageBucket,
});

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  fs.mkdirSync(artifactDir, { recursive: true });
  ensureSpeechAudio(audioPath);

  const senderAuth = await signInTestPhone(sender.phoneNumber, sender.smsCode);
  const receiverAuth = await signInTestPhone(
    receiver.phoneNumber,
    receiver.smsCode,
  );
  sender.uid = senderAuth.localId;
  receiver.uid = receiverAuth.localId;

  await prepareUser(sender);
  await prepareUser(receiver);

  const roomResult = await callFunction(senderAuth.idToken, "createRoom", {
    type: "direct",
    participantHandles: [receiver.handle],
  });
  const roomId = roomResult.roomId;
  const db = admin.firestore();
  const staleTokenRef = db
    .collection("users")
    .doc(receiver.uid)
    .collection("fcmTokens")
    .doc(`stale_${runId}`);
  await staleTokenRef.set({
    token: `invalid-fcm-token-${runId}`,
    platform: "smoke",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const senderTextResult = await callFunction(senderAuth.idToken, "sendTextMessage", {
    roomId,
    text: `text smoke from sender ${runId}`,
  });
  const fcmStaleTokenRemoved = await waitForDocumentDeleted(staleTokenRef, 90000);
  const receiverTextResult = await callFunction(
    receiverAuth.idToken,
    "sendTextMessage",
    {
    roomId,
    text: `text smoke from receiver ${runId}`,
    },
  );

  const draftId = `draft_${runId}`;
  const draftAudioPath = `voice_drafts/${sender.uid}/${draftId}.wav`;
  await uploadFirebaseStorage(senderAuth.idToken, draftAudioPath, audioPath, {
    ownerId: sender.uid,
    durationMs: "3500",
    language: "en",
    smokeRunId: runId,
  });

  const draftResult = await callFunction(senderAuth.idToken, "createTranscriptionDraft", {
    draftId,
    audioPath: draftAudioPath,
    language: "en",
    durationMs: 3500,
  });

  const reviewVoiceResult = await callFunction(senderAuth.idToken, "sendVoiceMessage", {
    roomId,
    draftId,
    finalText: draftResult.transcript || "hello voice messenger",
    sendMode: "confirm",
  });

  const instantMessageId = `instant_${runId}`;
  const instantAudioPath = `voice_drafts/${sender.uid}/${instantMessageId}.wav`;
  await uploadFirebaseStorage(senderAuth.idToken, instantAudioPath, audioPath, {
    ownerId: sender.uid,
    durationMs: "3500",
    language: "en",
    smokeRunId: runId,
  });
  const instantResult = await callFunction(senderAuth.idToken, "sendInstantVoiceMessage", {
    roomId,
    messageId: instantMessageId,
    audioPath: instantAudioPath,
    durationMs: 3500,
    language: "en",
    sendMode: "instant",
  });

  const instantDoc = db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .doc(instantResult.messageId);
  const instantFinal = await waitForMessageTranscription(instantDoc, 90000);

  const calendarDraftId = `calendar_${runId}`;
  const calendarAudioPath = `voice_drafts/${sender.uid}/${calendarDraftId}.wav`;
  const calendarTarget = kstDateParts(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  );
  const calendarTranscript = `${calendarTarget.year}년 ${calendarTarget.month}월 ${calendarTarget.day}일 오후 3시에 E2E 캘린더라는 일정 추가해줘`;
  await uploadFirebaseStorage(senderAuth.idToken, calendarAudioPath, audioPath, {
    ownerId: sender.uid,
    durationMs: "3500",
    language: "ko",
    purpose: "calendar",
    smokeRunId: runId,
  });
  const calendarDraftResult = await callFunction(
    senderAuth.idToken,
    "createCalendarIntentDraft",
    {
      draftId: calendarDraftId,
      audioPath: calendarAudioPath,
      language: "ko",
      durationMs: 3500,
      transcriptOverride: calendarTranscript,
    },
  );
  if (!calendarDraftResult.startAt || !calendarDraftResult.endAt) {
    throw new Error(
      `Calendar draft parsing failed: ${JSON.stringify(calendarDraftResult)}`,
    );
  }
  const calendarCreateResult = await callFunction(
    senderAuth.idToken,
    "createCalendarEvent",
    {
      title: calendarDraftResult.parsedTitle || `E2E calendar ${runId}`,
      startAt: calendarDraftResult.startAt,
      endAt: calendarDraftResult.endAt,
      timezone: calendarDraftResult.timezone || "Asia/Seoul",
      source: "voice",
      details: `E2E calendar detail ${runId}`,
      transcript: calendarDraftResult.transcript,
    },
  );
  const calendarEventId = calendarCreateResult.eventId;
  const calendarRef = db
    .collection("users")
    .doc(sender.uid)
    .collection("calendarEvents")
    .doc(calendarEventId);
  const calendarUpdateResult = await callFunction(
    senderAuth.idToken,
    "updateCalendarEvent",
    {
      eventId: calendarEventId,
      title: `E2E calendar updated ${runId}`,
      startAt: calendarDraftResult.startAt,
      endAt: calendarDraftResult.endAt,
      timezone: "Asia/Seoul",
      details: `E2E calendar detail updated ${runId}`,
    },
  );
  const calendarUpdatedSnapshot = await calendarRef.get();
  const calendarDeleteResult = await callFunction(
    senderAuth.idToken,
    "deleteCalendarEvent",
    { eventId: calendarEventId },
  );
  const calendarDeleted = await waitForDocumentDeleted(calendarRef, 30000);

  const roomSnapshot = await db.collection("rooms").doc(roomId).get();
  const messageSnapshot = await db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .orderBy("createdAt", "asc")
    .get();
  const senderMember = await db
    .collection("rooms")
    .doc(roomId)
    .collection("members")
    .doc(sender.uid)
    .get();
  const receiverMember = await db
    .collection("rooms")
    .doc(roomId)
    .collection("members")
    .doc(receiver.uid)
    .get();

  const result = {
    ok: true,
    runId,
    projectId,
    region,
    users: {
      sender,
      receiver,
    },
    room: {
      roomId,
      exists: roomSnapshot.exists,
      participantIds: roomSnapshot.data()?.participantIds || [],
      senderMemberExists: senderMember.exists,
      receiverMemberExists: receiverMember.exists,
    },
    text: {
      senderMessageId: senderTextResult.messageId,
      receiverMessageId: receiverTextResult.messageId,
    },
    fcm: {
      staleTokenSeeded: true,
      staleTokenRemoved: fcmStaleTokenRemoved,
    },
    voiceReviewSend: {
      draftId,
      draftAudioPath,
      draftTranscript: draftResult.transcript,
      draftStatus: draftResult.status,
      draftCacheHit: draftResult.sttCacheHit,
      messageId: reviewVoiceResult.messageId,
    },
    voiceInstantSend: {
      draftAudioPath: instantAudioPath,
      messageAudioPath: instantFinal.audioPath || null,
      messageId: instantResult.messageId,
      finalStatus: instantFinal.sttStatus,
      transcript: instantFinal.transcript || "",
      errorCode: instantFinal.errorCode || null,
    },
    calendar: {
      draftId: calendarDraftId,
      transcript: calendarDraftResult.transcript,
      parsedTitle: calendarDraftResult.parsedTitle,
      startAt: calendarDraftResult.startAt,
      endAt: calendarDraftResult.endAt,
      eventId: calendarEventId,
      createdTitle: calendarCreateResult.event?.title || null,
      createdDetails: calendarCreateResult.event?.details || null,
      updatedTitle: calendarUpdatedSnapshot.data()?.title || null,
      updatedDetails: calendarUpdatedSnapshot.data()?.details || null,
      updateResultTitle: calendarUpdateResult.event?.title || null,
      updateResultDetails: calendarUpdateResult.event?.details || null,
      deleteResult: calendarDeleteResult.deleted === true,
      deleted: calendarDeleted,
    },
    messageCount: messageSnapshot.size,
    messages: messageSnapshot.docs.map((doc) => ({
      id: doc.id,
      kind: doc.data().kind,
      senderId: doc.data().senderId,
      text: doc.data().text || "",
      transcript: doc.data().transcript || "",
      sttStatus: doc.data().sttStatus || null,
      sendMode: doc.data().sendMode || null,
    })),
    artifact: path.relative(repoRoot, resultPath),
  };

  fs.writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  console.log(JSON.stringify(result, null, 2));

}

async function prepareUser(user) {
  await admin.auth().updateUser(user.uid, {
    displayName: user.displayName,
  });

  const now = admin.firestore.FieldValue.serverTimestamp();
  const db = admin.firestore();
  await db.collection("users").doc(user.uid).set(
    {
      displayName: user.displayName,
      handle: user.handle,
      defaultSendMode: "confirm",
      photoUrl: null,
      phoneHash: null,
      smokeRunId: runId,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  await db.collection("handles").doc(user.handle).set(
    {
      uid: user.uid,
      smokeRunId: runId,
      updatedAt: now,
    },
    { merge: true },
  );
}

async function signInTestPhone(phoneNumber, code) {
  const sendResponse = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=${apiKey}`,
    {
      phoneNumber,
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
      ) || raw}`,
    );
  }
  return body.result || {};
}

async function uploadFirebaseStorage(idToken, storagePath, filePath, metadata) {
  const query = new URLSearchParams({
    uploadType: "media",
    name: storagePath,
  });
  Object.entries(metadata || {}).forEach(([key, value]) => {
    query.set(`metadata_${key}`, String(value));
  });
  const metadataHeaders = {};
  Object.entries(metadata || {}).forEach(([key, value]) => {
    metadataHeaders[`x-goog-meta-${key}`] = String(value);
  });
  const response = await fetch(
    `https://firebasestorage.googleapis.com/v0/b/${storageBucket}/o?${query}`,
    {
      method: "POST",
      headers: {
        Authorization: `Firebase ${idToken}`,
        "Content-Type": "audio/wav",
        ...metadataHeaders,
      },
      body: fs.readFileSync(filePath),
    },
  );
  const raw = await response.text();
  const body = raw ? safeJson(raw) : {};
  if (!response.ok) {
    throw new Error(
      `Storage upload failed for ${storagePath}: ${JSON.stringify(body)}`,
    );
  }
  return body;
}

async function postJson(url, data) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  const raw = await response.text();
  const body = raw ? safeJson(raw) : {};
  if (!response.ok || body.error) {
    throw new Error(`POST failed: ${JSON.stringify(body.error || body)}`);
  }
  return body;
}

function safeJson(value) {
  try {
    return JSON.parse(value);
  } catch (_error) {
    return { raw: value };
  }
}

async function waitForMessageTranscription(docRef, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new Error(`Message not found: ${docRef.path}`);
    }
    const data = snapshot.data();
    if (data.sttStatus === "completed" || data.sttStatus === "failed") {
      return data;
    }
    await sleep(3000);
  }
  const snapshot = await docRef.get();
  return {
    ...(snapshot.data() || {}),
    sttStatus: snapshot.data()?.sttStatus || "timeout",
    errorCode: snapshot.data()?.errorCode || "timeout",
  };
}

async function waitForDocumentDeleted(docRef, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      return true;
    }
    await sleep(3000);
  }
  return false;
}

function kstDateParts(date) {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  return {
    year: kst.getUTCFullYear(),
    month: kst.getUTCMonth() + 1,
    day: kst.getUTCDate(),
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function ensureSpeechAudio(outputPath) {
  if (fs.existsSync(outputPath) && fs.statSync(outputPath).size > 10000) {
    return;
  }

  const script = [
    "Add-Type -AssemblyName System.Speech",
    "$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer",
    `$synth.SetOutputToWaveFile('${escapePowerShellPath(outputPath)}')`,
    "$synth.Speak('hello voice messenger, this is a Deepgram test')",
    "$synth.SetOutputToNull()",
  ].join("; ");
  execFileSync("powershell", ["-NoProfile", "-Command", script], {
    stdio: "inherit",
  });
}

function escapePowerShellPath(value) {
  return value.replace(/'/g, "''");
}
