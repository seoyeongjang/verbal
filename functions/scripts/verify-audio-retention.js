const fs = require("node:fs");
const path = require("node:path");
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

const args = new Set(process.argv.slice(2));
const prodMode = args.has("--prod");
const keepProbe = args.has("--keep");
const googleServices = JSON.parse(fs.readFileSync(googleServicesPath, "utf8"));
const projectInfo = googleServices.project_info;
const projectId = prodMode
  ? projectInfo.project_id
  : process.env.GCLOUD_PROJECT || "demo-verbal";
const storageBucket = prodMode
  ? projectInfo.storage_bucket
  : process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.appspot.com`;

if (prodMode && process.env.VERIFY_AUDIO_RETENTION_PROD !== "1") {
  throw new Error(
    "Production audio retention verification requires VERIFY_AUDIO_RETENTION_PROD=1.",
  );
}

if (!prodMode && !process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    "Run without --prod through `npm run verify:audio-retention` so Firestore/Storage emulators are active.",
  );
}

admin.initializeApp({
  projectId,
  storageBucket,
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const runId =
  process.env.RETENTION_RUN_ID ||
  new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const uid = `retention_user_${runId}`;
const roomId = `retention_probe_room_${runId}`;
const messageId = `retention_probe_message_${runId}`;
const draftId = `retention_probe_draft_${runId}`;
const messageAudioPath = `voice_messages/${roomId}/${messageId}.m4a`;
const draftAudioPath = `voice_drafts/${uid}/${draftId}.m4a`;
const transcript = `Retention transcript must remain ${runId}`;
const artifactDir = path.join(repoRoot, "artifacts");
const artifactPath = path.join(
  artifactDir,
  `audio-retention-verification-${runId}.json`,
);

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  await seedExpiredVoiceData();
  const cleanupSummary = await expireVoiceAudioProbe();
  const verification = await verifyExpiredVoiceData(cleanupSummary);
  await writeArtifact(verification);

  if (!keepProbe) {
    await cleanupProbe();
  }

  console.log(JSON.stringify(verification, null, 2));
}

async function seedExpiredVoiceData() {
  const expiredAt = admin.firestore.Timestamp.fromMillis(Date.now() - 60000);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await bucket.file(messageAudioPath).save(Buffer.from(`message-${runId}`), {
    resumable: false,
    contentType: "audio/mp4",
    metadata: {metadata: {retentionProbe: runId}},
  });
  await bucket.file(draftAudioPath).save(Buffer.from(`draft-${runId}`), {
    resumable: false,
    contentType: "audio/mp4",
    metadata: {metadata: {retentionProbe: runId}},
  });

  await db.collection("rooms").doc(roomId).set({
    type: "direct",
    title: "Retention Probe",
    participantIds: [uid],
    audioRetentionDays: 1,
    createdAt: now,
    updatedAt: now,
    retentionProbe: runId,
  });
  await db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .doc(messageId)
    .set({
      senderId: uid,
      kind: "voice",
      text: transcript,
      transcript,
      audioPath: messageAudioPath,
      durationMs: 1200,
      sttStatus: "completed",
      sendMode: "instant",
      deliveryStatus: "sent",
      audioExpiresAt: expiredAt,
      audioRetentionDays: 1,
      audioRetentionStatus: "active",
      createdAt: now,
      updatedAt: now,
      retentionProbe: runId,
    });
  await db.collection("transcriptionDrafts").doc(draftId).set({
    ownerId: uid,
    audioPath: draftAudioPath,
    transcript,
    sttStatus: "completed",
    audioExpiresAt: expiredAt,
    audioRetentionStatus: "active",
    createdAt: now,
    updatedAt: now,
    retentionProbe: runId,
  });
}

async function expireVoiceAudioProbe() {
  const now = admin.firestore.Timestamp.now();
  const summary = {
    expiredMessagesScanned: 0,
    probeMessagesDeleted: 0,
    expiredDraftsScanned: 0,
    probeDraftsDeleted: 0,
  };

  const expiredMessages = await db
    .collectionGroup("messages")
    .where("audioRetentionStatus", "==", "active")
    .where("audioExpiresAt", "<=", now)
    .limit(100)
    .get();
  summary.expiredMessagesScanned = expiredMessages.size;

  for (const doc of expiredMessages.docs) {
    const data = doc.data();
    const audioPath = data.audioPath;
    if (typeof audioPath === "string" && audioPath) {
      await deleteStorageFile(audioPath);
    }
    await doc.ref.set(
      {
        audioPath: null,
        audioDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
        audioRetentionStatus: "deleted",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    if (data.retentionProbe === runId) {
      summary.probeMessagesDeleted += 1;
    }
  }

  const expiredDrafts = await db
    .collection("transcriptionDrafts")
    .where("audioRetentionStatus", "==", "active")
    .where("audioExpiresAt", "<=", now)
    .limit(100)
    .get();
  summary.expiredDraftsScanned = expiredDrafts.size;

  for (const doc of expiredDrafts.docs) {
    const data = doc.data();
    const audioPath = data.audioPath;
    if (typeof audioPath === "string" && audioPath) {
      await deleteStorageFile(audioPath);
    }
    await doc.ref.set(
      {
        audioDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
        audioRetentionStatus: "deleted",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    if (data.retentionProbe === runId) {
      summary.probeDraftsDeleted += 1;
    }
  }

  return summary;
}

async function verifyExpiredVoiceData(cleanupSummary) {
  const messageRef = db
    .collection("rooms")
    .doc(roomId)
    .collection("messages")
    .doc(messageId);
  const draftRef = db.collection("transcriptionDrafts").doc(draftId);
  const [messageSnapshot, draftSnapshot, messageFileExists, draftFileExists] =
    await Promise.all([
      messageRef.get(),
      draftRef.get(),
      fileExists(messageAudioPath),
      fileExists(draftAudioPath),
    ]);

  const message = messageSnapshot.data() || {};
  const draft = draftSnapshot.data() || {};
  const checks = {
    messageExists: messageSnapshot.exists,
    messageAudioPathDeleted: message.audioPath === null,
    messageRetentionStatusDeleted: message.audioRetentionStatus === "deleted",
    messageTranscriptPreserved: message.transcript === transcript,
    messageTextPreserved: message.text === transcript,
    messageAudioFileDeleted: !messageFileExists,
    draftExists: draftSnapshot.exists,
    draftRetentionStatusDeleted: draft.audioRetentionStatus === "deleted",
    draftAudioFileDeleted: !draftFileExists,
  };
  const ok = Object.values(checks).every(Boolean);
  if (!ok) {
    throw new Error(`Audio retention verification failed: ${JSON.stringify(checks)}`);
  }

  return {
    ok,
    mode: prodMode ? "production" : "emulator",
    projectId,
    storageBucket,
    runId,
    roomId,
    messageId,
    draftId,
    transcript,
    cleanupSummary,
    checks,
    artifact: path.relative(repoRoot, artifactPath),
    keptProbe: keepProbe,
    verifiedAt: new Date().toISOString(),
  };
}

async function writeArtifact(verification) {
  fs.writeFileSync(
    artifactPath,
    `${JSON.stringify(verification, null, 2)}\n`,
    "utf8",
  );
}

async function cleanupProbe() {
  await Promise.allSettled([
    db.collection("rooms").doc(roomId).collection("messages").doc(messageId).delete(),
    db.collection("rooms").doc(roomId).delete(),
    db.collection("transcriptionDrafts").doc(draftId).delete(),
    deleteStorageFile(messageAudioPath),
    deleteStorageFile(draftAudioPath),
  ]);
}

async function deleteStorageFile(storagePath) {
  try {
    await bucket.file(storagePath).delete({ignoreNotFound: true});
  } catch (error) {
    if (!String(error?.message || error).includes("No such object")) {
      throw error;
    }
  }
}

async function fileExists(storagePath) {
  const [exists] = await bucket.file(storagePath).exists();
  return exists;
}
