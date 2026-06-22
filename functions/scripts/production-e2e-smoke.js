const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
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
  await clearActionCooldowns([sender.uid, receiver.uid]);
  const db = admin.firestore();

  const friendResult = await callFunction(senderAuth.idToken, "addFriendByHandle", {
    handle: receiver.handle,
  });
  const friendSnapshot = await db
    .collection("users")
    .doc(sender.uid)
    .collection("friends")
    .doc(receiver.uid)
    .get();

  const roomResult = await callFunction(senderAuth.idToken, "createRoom", {
    type: "direct",
    participantHandles: [receiver.handle],
  });
  const roomId = roomResult.roomId;
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
  await callFunction(senderAuth.idToken, "editMessage", {
    roomId,
    messageId: senderTextResult.messageId,
    text: `edited text smoke from sender ${runId}`,
  });
  const editedTextDoc = await db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .doc(senderTextResult.messageId)
    .get();
  const reactionResult = await callFunction(receiverAuth.idToken, "addReaction", {
    roomId,
    messageId: senderTextResult.messageId,
    emoji: "👍",
  });
  const pinResult = await callFunction(senderAuth.idToken, "pinMessage", {
    roomId,
    messageId: senderTextResult.messageId,
  });
  const pinDoc = await db
    .collection("rooms")
    .doc(roomId)
    .collection("pins")
    .doc(senderTextResult.messageId)
    .get();
  const unpinResult = await callFunction(senderAuth.idToken, "unpinMessage", {
    roomId,
    messageId: senderTextResult.messageId,
  });
  const pinDeleted = await waitForDocumentDeleted(pinDoc.ref, 30000);
  await callFunction(receiverAuth.idToken, "deleteMessage", {
    roomId,
    messageId: receiverTextResult.messageId,
  });
  const receiverTextDeleted = await waitForDocumentDeleted(
    db
      .collection("rooms")
      .doc(roomId)
      .collection("messages")
      .doc(receiverTextResult.messageId),
    30000,
  );

  const scheduledAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const scheduledResult = await callFunction(
    senderAuth.idToken,
    "scheduleTextMessage",
    {
      roomId,
      text: `scheduled smoke from sender ${runId}`,
      scheduledAt,
    },
  );
  await callFunction(senderAuth.idToken, "sendScheduledMessageNow", {
    roomId,
    messageId: scheduledResult.messageId,
  });
  const scheduledDoc = await db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .doc(scheduledResult.messageId)
    .get();

  const attachmentLocalPath = path.join(
    artifactDir,
    `e2e-attachment-${runId}.txt`,
  );
  fs.writeFileSync(
    attachmentLocalPath,
    `Verbal E2E attachment smoke ${runId}\n`,
    "utf8",
  );
  const attachmentStoragePath =
    `attachments/${roomId}/${sender.uid}/e2e-attachment-${runId}.txt`;
  await uploadFirebaseStorage(
    senderAuth.idToken,
    attachmentStoragePath,
    attachmentLocalPath,
    {
      ownerId: sender.uid,
      roomId,
      smokeRunId: runId,
    },
    "application/octet-stream",
  );
  const attachmentResult = await callFunction(
    senderAuth.idToken,
    "sendAttachmentMessage",
    {
      roomId,
      kind: "file",
      caption: `attachment smoke ${runId}`,
      attachment: {
        type: "file",
        title: `E2E attachment ${runId}.txt`,
        storagePath: attachmentStoragePath,
        mimeType: "application/octet-stream",
        sizeBytes: fs.statSync(attachmentLocalPath).size,
      },
    },
  );
  const locationResult = await callFunction(
    senderAuth.idToken,
    "sendAttachmentMessage",
    {
      roomId,
      kind: "location",
      attachment: {
        type: "location",
        title: "E2E Seoul location",
        address: "Seoul City Hall smoke test point",
        latitude: 37.5665,
        longitude: 126.978,
      },
    },
  );
  const translationResult = await callFunction(
    receiverAuth.idToken,
    "translateMessage",
    {
      roomId,
      messageId: senderTextResult.messageId,
      targetLanguage: "ja",
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
    finalText: draftResult.transcript || "hello verbal",
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
  const calendarTranscriptOverride = `${calendarTarget.year}년 ${calendarTarget.month}월 ${calendarTarget.day}일 오후 3시에 E2E 캘린더라는 일정 추가해줘`;
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
      transcriptOverride: calendarTranscriptOverride,
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

  const proposalStartOne = new Date(Date.now() + 8 * 24 * 60 * 60 * 1000);
  proposalStartOne.setUTCHours(6, 0, 0, 0);
  const proposalEndOne = new Date(proposalStartOne.getTime() + 60 * 60 * 1000);
  const proposalStartTwo = new Date(Date.now() + 9 * 24 * 60 * 60 * 1000);
  proposalStartTwo.setUTCHours(7, 0, 0, 0);
  const proposalEndTwo = new Date(proposalStartTwo.getTime() + 60 * 60 * 1000);
  const proposalResult = await callFunction(
    senderAuth.idToken,
    "createCalendarProposal",
    {
      roomId,
      title: `E2E proposal ${runId}`,
      details: `E2E proposal details ${runId}`,
      timezone: "Asia/Seoul",
      source: "manual",
      transcript: `proposal transcript ${runId}`,
      candidates: [
        {
          candidateId: "candidate_1",
          startAt: proposalStartOne.toISOString(),
          endAt: proposalEndOne.toISOString(),
        },
        {
          candidateId: "candidate_2",
          startAt: proposalStartTwo.toISOString(),
          endAt: proposalEndTwo.toISOString(),
        },
      ],
    },
  );
  await callFunction(receiverAuth.idToken, "voteCalendarProposal", {
    roomId,
    proposalId: proposalResult.proposalId,
    candidateIds: ["candidate_1"],
  });
  await callFunction(senderAuth.idToken, "finalizeCalendarProposal", {
    roomId,
    proposalId: proposalResult.proposalId,
    candidateId: "candidate_1",
  });
  const proposalSnapshot = await db
    .collection("rooms")
    .doc(roomId)
    .collection("calendarProposals")
    .doc(proposalResult.proposalId)
    .get();
  const receiverProposalEvent = await db
    .collection("users")
    .doc(receiver.uid)
    .collection("calendarEvents")
    .doc(`${proposalResult.proposalId}_candidate_1`)
    .get();

  await clearActionCooldowns([sender.uid, receiver.uid]);
  const openRoomResult = await callFunction(senderAuth.idToken, "createRoom", {
    type: "open",
    title: `E2E Open ${runId}`,
  });
  const openInviteResult = await callFunction(
    senderAuth.idToken,
    "createRoomInvite",
    {
      roomId: openRoomResult.roomId,
      approvalRequired: false,
    },
  );
  const openJoinResult = await callFunction(receiverAuth.idToken, "joinRoomByInvite", {
    token: openInviteResult.token,
  });
  const openReceiverMember = db
    .collection("rooms")
    .doc(openRoomResult.roomId)
    .collection("members")
    .doc(receiver.uid);
  const openReceiverJoined = await openReceiverMember.get();
  await callFunction(receiverAuth.idToken, "leaveRoom", {
    roomId: openRoomResult.roomId,
  });
  const openReceiverLeft = await openReceiverMember.get();

  await clearActionCooldowns([sender.uid, receiver.uid]);
  const reportMessageResult = await callFunction(receiverAuth.idToken, "reportMessage", {
    roomId,
    messageId: senderTextResult.messageId,
    reason: "smoke_test",
    details: `E2E report smoke ${runId}`,
  });
  const blockResult = await callFunction(senderAuth.idToken, "blockUser", {
    blockedUid: receiver.uid,
    reason: `E2E block smoke ${runId}`,
  });
  const reportDoc = await db
    .collection("reports")
    .doc(reportDocId(receiver.uid, "message", `${roomId}_${senderTextResult.messageId}`))
    .get();
  const blockDoc = await db
    .collection("blocks")
    .doc(sender.uid)
    .collection("users")
    .doc(receiver.uid)
    .get();

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
    friend: {
      addedUid: friendResult.friend?.uid || null,
      addedHandle: friendResult.friend?.handle || null,
      friendDocumentExists: friendSnapshot.exists,
      friendDocumentHandle: friendSnapshot.data()?.handle || null,
    },
    text: {
      senderMessageId: senderTextResult.messageId,
      receiverMessageId: receiverTextResult.messageId,
      editedText: editedTextDoc.data()?.text || null,
      receiverDeleted: receiverTextDeleted,
    },
    messageActions: {
      reactionOk: reactionResult.ok === true,
      pinOk: pinResult.ok === true,
      pinCreated: pinDoc.exists,
      unpinOk: unpinResult.ok === true,
      pinDeleted,
    },
    scheduledMessage: {
      messageId: scheduledResult.messageId,
      scheduledAt,
      deliveryStatus: scheduledDoc.data()?.deliveryStatus || null,
      text: scheduledDoc.data()?.text || null,
    },
    attachment: {
      messageId: attachmentResult.messageId,
      storagePath: attachmentStoragePath,
      localPath: path.relative(repoRoot, attachmentLocalPath),
    },
    location: {
      messageId: locationResult.messageId,
      latitude: 37.5665,
      longitude: 126.978,
    },
    translation: {
      targetLanguage: translationResult.targetLanguage,
      text: translationResult.text,
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
    calendarProposal: {
      proposalId: proposalResult.proposalId,
      messageId: proposalResult.messageId,
      status: proposalSnapshot.data()?.status || null,
      finalCandidateId: proposalSnapshot.data()?.finalCandidateId || null,
      receiverCalendarEventExists: receiverProposalEvent.exists,
      receiverCalendarEventTitle: receiverProposalEvent.data()?.title || null,
    },
    openChatInvite: {
      roomId: openRoomResult.roomId,
      inviteId: openInviteResult.inviteId,
      token: openInviteResult.token,
      url: openInviteResult.url,
      joinStatus: openJoinResult.status,
      receiverJoined: openReceiverJoined.exists && !openReceiverJoined.data()?.leftAt,
      receiverLeft: Boolean(openReceiverLeft.data()?.leftAt),
    },
    safety: {
      reportMessageOk: reportMessageResult.ok === true,
      reportDocumentExists: reportDoc.exists,
      blockOk: blockResult.ok === true,
      blockDocumentExists: blockDoc.exists,
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

  assertSmokeResult(result);
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

async function clearActionCooldowns(uids) {
  const db = admin.firestore();
  const actions = ["createRoomInvite", "joinRoomByInvite", "report", "blockUser"];
  const batch = db.batch();
  for (const uid of uids) {
    for (const action of actions) {
      batch.delete(db.collection("actionCooldowns").doc(`${safeId(uid)}_${action}`));
    }
  }
  await batch.commit();
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

async function uploadFirebaseStorage(
  idToken,
  storagePath,
  filePath,
  metadata,
  contentType = "audio/wav",
) {
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
        "Content-Type": contentType,
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

function assertSmokeResult(result) {
  const failures = [];
  const expect = (condition, label, detail) => {
    if (!condition) {
      failures.push({ label, detail });
    }
  };

  expect(result.room.exists, "room exists", result.room);
  expect(result.room.senderMemberExists, "sender member exists", result.room);
  expect(result.room.receiverMemberExists, "receiver member exists", result.room);
  expect(result.friend.friendDocumentExists, "friend document exists", result.friend);
  expect(
    result.text.editedText === `edited text smoke from sender ${result.runId}`,
    "text edit persisted",
    result.text,
  );
  expect(result.text.receiverDeleted, "receiver text deleted", result.text);
  expect(result.messageActions.reactionOk, "reaction callable succeeded", result.messageActions);
  expect(result.messageActions.pinCreated, "pin document created", result.messageActions);
  expect(result.messageActions.pinDeleted, "pin document deleted", result.messageActions);
  expect(
    result.scheduledMessage.deliveryStatus === "sent",
    "scheduled message delivered now",
    result.scheduledMessage,
  );
  expect(Boolean(result.attachment.messageId), "file attachment message created", result.attachment);
  expect(Boolean(result.location.messageId), "location message created", result.location);
  expect(Boolean(result.translation.text), "translation text returned", result.translation);
  expect(result.fcm.staleTokenRemoved, "stale FCM token removed", result.fcm);
  expect(
    result.voiceReviewSend.draftStatus === "completed",
    "review voice draft completed",
    result.voiceReviewSend,
  );
  expect(
    result.voiceInstantSend.finalStatus === "completed" &&
      Boolean(result.voiceInstantSend.transcript),
    "instant voice transcript completed",
    result.voiceInstantSend,
  );
  expect(result.calendar.deleted, "calendar event deleted", result.calendar);
  expect(
    result.calendarProposal.status === "finalized" &&
      result.calendarProposal.receiverCalendarEventExists,
    "calendar proposal finalized and added",
    result.calendarProposal,
  );
  expect(
    result.openChatInvite.joinStatus === "joined" &&
      result.openChatInvite.receiverJoined &&
      result.openChatInvite.receiverLeft,
    "open chat invite join and leave",
    result.openChatInvite,
  );
  expect(
    result.safety.reportDocumentExists && result.safety.blockDocumentExists,
    "safety report and block documents exist",
    result.safety,
  );

  if (failures.length > 0) {
    throw new Error(`Production E2E smoke assertions failed: ${JSON.stringify(failures)}`);
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

function reportDocId(uid, targetType, targetId) {
  const hash = crypto
    .createHash("sha256")
    .update(`${uid}:${targetType}:${targetId}`)
    .digest("hex")
    .slice(0, 32);
  return `${safeId(uid).slice(0, 32)}_${targetType}_${hash}`;
}

function safeId(value) {
  return String(value).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120) || "id";
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
    "$synth.Speak('hello verbal, this is a Deepgram test')",
    "$synth.SetOutputToNull()",
  ].join("; ");
  execFileSync("powershell", ["-NoProfile", "-Command", script], {
    stdio: "inherit",
  });
}

function escapePowerShellPath(value) {
  return value.replace(/'/g, "''");
}
