import * as admin from "firebase-admin";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { GoogleAuth } from "google-auth-library";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { parseCalendarCommand } from "./calendar-parser";
import {
  pluginAudioExtension,
  pluginContentType,
  PluginMessageCardInputError,
  pluginMessageCardInput,
  pluginPlatform,
  renderPluginMessageCard,
} from "./plugin-platform";

if (getApps().length === 0) {
  initializeApp();
}

setGlobalOptions({
  region: process.env.FUNCTIONS_REGION || "asia-northeast3",
  maxInstances: 20,
});

const db = getFirestore();
const bucket = getStorage().bucket();
const messaging = getMessaging();
const deepgramApiKey = defineSecret("DEEPGRAM_API_KEY");
const googleAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/devstorage.full_control"],
});

const DEFAULT_AUDIO_RETENTION_DAYS = boundedInt(
  process.env.DEFAULT_AUDIO_RETENTION_DAYS,
  1,
  1,
  30,
);
const DRAFT_AUDIO_RETENTION_DAYS = boundedInt(
  process.env.DRAFT_AUDIO_RETENTION_DAYS,
  1,
  1,
  7,
);
const HANDLE_PATTERN =
  /^[A-Za-z0-9_\u1100-\u11FF\u3130-\u318F\uAC00-\uD7A3\u3040-\u30FF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF]+$/u;
const HANDLE_MIN_LENGTH = 3;
const HANDLE_MAX_LENGTH = 30;
const INVITE_CREATE_COOLDOWN_MS = boundedInt(
  process.env.INVITE_CREATE_COOLDOWN_MS,
  30_000,
  1_000,
  10 * 60_000,
);
const INVITE_JOIN_COOLDOWN_MS = boundedInt(
  process.env.INVITE_JOIN_COOLDOWN_MS,
  10_000,
  1_000,
  10 * 60_000,
);
const REPORT_COOLDOWN_MS = boundedInt(
  process.env.REPORT_COOLDOWN_MS,
  10_000,
  1_000,
  10 * 60_000,
);
const BLOCK_COOLDOWN_MS = boundedInt(
  process.env.BLOCK_COOLDOWN_MS,
  2_000,
  500,
  60_000,
);
const DEEPGRAM_COST_LOW_PER_MINUTE_USD = boundedFloat(
  process.env.DEEPGRAM_COST_LOW_PER_MINUTE_USD,
  0.0048,
  0,
  1,
);
const DEEPGRAM_COST_HIGH_PER_MINUTE_USD = boundedFloat(
  process.env.DEEPGRAM_COST_HIGH_PER_MINUTE_USD,
  0.0058,
  0,
  1,
);
const VOICE_STT_MIN_INSTANCES = boundedInt(
  process.env.VOICE_STT_MIN_INSTANCES,
  1,
  0,
  3,
);
const VOICE_STT_CALL_OPTIONS = {
  secrets: [deepgramApiKey],
  timeoutSeconds: 180,
  memory: "512MiB" as const,
  minInstances: VOICE_STT_MIN_INSTANCES,
};
const VOICE_STT_RECOVERY_CALL_OPTIONS = {
  secrets: [deepgramApiKey],
  timeoutSeconds: 180,
  memory: "512MiB" as const,
};
const STALE_PENDING_VOICE_MS = boundedInt(
  process.env.STALE_PENDING_VOICE_MS,
  2 * 60 * 1000,
  30 * 1000,
  30 * 60 * 1000,
);
const DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_COUNT = boundedInt(
  process.env.DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_COUNT,
  1,
  0,
  4,
);
const DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_DELAY_MS = boundedInt(
  process.env.DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_DELAY_MS,
  250,
  0,
  2_000,
);
const DEEPGRAM_REQUEST_TIMEOUT_MS = boundedInt(
  process.env.DEEPGRAM_REQUEST_TIMEOUT_MS,
  4_500,
  2_000,
  30_000,
);
const DEEPGRAM_PARALLEL_KO_MODEL_RACE =
  (process.env.DEEPGRAM_PARALLEL_KO_MODEL_RACE || "true")
    .trim()
    .toLowerCase() !== "false";
const DEEPGRAM_DETECT_LANGUAGE_FALLBACK =
  (process.env.DEEPGRAM_DETECT_LANGUAGE_FALLBACK || "true")
    .trim()
    .toLowerCase() !== "false";
const STT_FAILED_RECOVERY_MAX_ATTEMPTS = boundedInt(
  process.env.STT_FAILED_RECOVERY_MAX_ATTEMPTS,
  3,
  0,
  10,
);
const PLUGIN_MAX_AUDIO_BYTES = boundedInt(
  process.env.PLUGIN_MAX_AUDIO_BYTES,
  15 * 1024 * 1024,
  128 * 1024,
  50 * 1024 * 1024,
);
const PLUGIN_SIGNED_URL_TTL_MINUTES = boundedInt(
  process.env.PLUGIN_SIGNED_URL_TTL_MINUTES,
  15,
  1,
  60,
);
const PLUGIN_DEFAULT_AUDIO_RETENTION_DAYS = boundedInt(
  process.env.PLUGIN_DEFAULT_AUDIO_RETENTION_DAYS,
  1,
  1,
  30,
);

type RoomType = "direct" | "group" | "open";
type SendMode = "confirm" | "instant";
type MessageKind =
  | "text"
  | "voice"
  | "image"
  | "file"
  | "location"
  | "calendarProposal";
type SttStatus = "none" | "processing" | "completed" | "failed";
type DeliveryStatus = "sending" | "scheduled" | "sent" | "failed";
type RoomMemberRole = "owner" | "admin" | "member";
type CalendarEventSource = "manual" | "voice" | "chatProposal";
type CalendarEventStatus = "active";

interface PluginPartnerData {
  name?: string;
  status?: string;
  allowedOrigins?: string[];
  enabledFeatures?: string[];
  defaultAudioRetentionDays?: number;
}

interface PluginAuthContext {
  partnerId: string;
  keyId: string;
  partner: PluginPartnerData;
}

interface RoomData {
  type: RoomType;
  participantIds: string[];
  title: string;
  ownerId?: string;
  audioRetentionDays?: number;
  audioRetentionPreset?: string;
  lastMessage?: {
    messageId?: string;
    kind?: MessageKind;
    preview?: string;
    senderId?: string;
    createdAt?: unknown;
  };
}

interface MessageReply {
  messageId: string;
  senderId: string;
  preview: string;
}

interface MessageData {
  senderId: string;
  kind: MessageKind;
  text: string;
  transcript: string;
  audioPath: string | null;
  audioHash?: string | null;
  audioExpiresAt?: unknown;
  audioDeletedAt?: unknown;
  audioRetentionDays?: number;
  audioRetentionStatus?: "active" | "deleted" | "none";
  durationMs: number;
  sttStatus: SttStatus;
  sttCacheHit?: boolean;
  sttRetryCount?: number;
  lastSttRetryAt?: unknown;
  errorCode?: string | null;
  sendMode: SendMode;
  language?: string;
  replyTo?: MessageReply | null;
  attachment?: MessageAttachment | null;
  calendarProposal?: CalendarProposalData | null;
  deliveryStatus?: DeliveryStatus;
  scheduledAt?: unknown;
  translations?: Record<string, MessageTranslation>;
  reactions?: Record<string, string[]>;
  pinnedAt?: unknown;
  pinnedBy?: string;
  deletedAt?: unknown;
  createdAt?: unknown;
  updatedAt?: unknown;
  clientCreated?: boolean;
}

interface CalendarProposalCandidateData {
  candidateId: string;
  startAt: unknown;
  endAt: unknown;
}

interface CalendarProposalData {
  roomId: string;
  messageId: string;
  createdBy: string;
  title: string;
  details: string;
  timezone: string;
  status: "open" | "finalized" | "cancelled";
  candidates: CalendarProposalCandidateData[];
  votes: Record<string, string[]>;
  finalCandidateId?: string | null;
  source?: string;
  transcript?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

interface MessageAttachment {
  type: "image" | "file" | "location";
  title: string;
  url?: string;
  storagePath?: string;
  mimeType?: string;
  sizeBytes?: number;
  latitude?: number;
  longitude?: number;
  address?: string;
}

interface MessageTranslation {
  text: string;
  createdAt: unknown;
}

interface RoomJoinRequest {
  uid: string;
  roomId: string;
  inviteId: string;
  status: "pending" | "approved" | "rejected";
  displayName?: string;
  handle?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

interface CalendarEventData {
  ownerId: string;
  title: string;
  startAt: unknown;
  endAt: unknown;
  timezone: string;
  source: CalendarEventSource;
  details?: string;
  transcript: string;
  status: CalendarEventStatus;
  roomId?: string;
  proposalId?: string;
  messageId?: string;
  candidateId?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

interface CalendarNotificationSettings {
  calendarReminderEnabled: boolean;
  calendarReminderLeadMinutes: number;
  morningBriefingEnabled: boolean;
  morningBriefingMinuteOfDay: number;
  calendarTimezone: string;
  holidayCountryCode: string;
}

export const exportMyData = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const userRef = db.collection("users").doc(uid);
  const [
    userSnapshot,
    roomsSnapshot,
    reportsSnapshot,
    blocksSnapshot,
    usageSnapshot,
  ] = await Promise.all([
    userRef.get(),
    db
      .collection("rooms")
      .where("participantIds", "array-contains", uid)
      .limit(200)
      .get(),
    db.collection("reports").where("reporterId", "==", uid).limit(500).get(),
    db.collection("blocks").doc(uid).collection("users").limit(500).get(),
    db.collection("usageDaily").where("uid", "==", uid).limit(370).get(),
  ]);

  const rooms = [];
  for (const roomDoc of roomsSnapshot.docs) {
    const memberSnapshot = await roomDoc.ref
      .collection("members")
      .doc(uid)
      .get();
    const messagesSnapshot = await roomDoc.ref
      .collection("messages")
      .where("senderId", "==", uid)
      .limit(450)
      .get();
    rooms.push({
      id: roomDoc.id,
      room: serializeData(roomDoc.data()),
      myMemberState: serializeData(memberSnapshot.data() || null),
      myMessages: messagesSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...(serializeData(doc.data()) as Record<string, unknown>),
      })),
    });
  }

  return {
    exportedAt: new Date().toISOString(),
    user: serializeData(userSnapshot.data() || null),
    rooms,
    reports: reportsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...(serializeData(doc.data()) as Record<string, unknown>),
    })),
    blockedUsers: blocksSnapshot.docs.map((doc) => ({
      uid: doc.id,
      ...(serializeData(doc.data()) as Record<string, unknown>),
    })),
    usageDaily: usageSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...(serializeData(doc.data()) as Record<string, unknown>),
    })),
  };
});

export const deleteMyAccount = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const userRef = db.collection("users").doc(uid);
  const userSnapshot = await userRef.get();
  const userData = userSnapshot.data() || {};
  const handle = optionalString(userData.handle);
  const now = FieldValue.serverTimestamp();

  if (handle) {
    await db
      .collection("handles")
      .doc(handle)
      .delete()
      .catch(() => undefined);
  }
  await deleteCollection(userRef.collection("fcmTokens"), 100);
  await deleteCollection(userRef.collection("calendarEvents"), 100);
  await deleteCollection(
    userRef.collection("calendarNotificationDeliveries"),
    100,
  );

  const roomsSnapshot = await db
    .collection("rooms")
    .where("participantIds", "array-contains", uid)
    .limit(200)
    .get();
  for (const roomDoc of roomsSnapshot.docs) {
    const room = roomDoc.data() as RoomData;
    const nextParticipantIds = Array.isArray(room.participantIds)
      ? room.participantIds.filter((participantId) => participantId !== uid)
      : [];
    const batch = db.batch();
    const roomUpdate: Record<string, unknown> = {
      participantIds: nextParticipantIds,
      updatedAt: now,
    };
    if (room.ownerId === uid) {
      roomUpdate.ownerId = nextParticipantIds[0] || null;
      if (nextParticipantIds[0]) {
        batch.set(
          roomDoc.ref.collection("members").doc(nextParticipantIds[0]),
          {
            role: "owner",
            updatedAt: now,
          },
          { merge: true },
        );
      }
    }
    batch.set(roomDoc.ref, roomUpdate, { merge: true });
    batch.set(
      roomDoc.ref.collection("members").doc(uid),
      {
        leftAt: now,
        archived: true,
        pinned: false,
        muted: true,
        unreadCount: 0,
        accountDeleted: true,
        updatedAt: now,
      },
      { merge: true },
    );

    const messagesSnapshot = await roomDoc.ref
      .collection("messages")
      .where("senderId", "==", uid)
      .limit(450)
      .get();
    for (const messageDoc of messagesSnapshot.docs) {
      batch.set(
        messageDoc.ref,
        {
          senderDeleted: true,
          updatedAt: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
  }

  await userRef.set(
    {
      displayName: "\uD0C8\uD1F4\uD55C \uC0AC\uC6A9\uC790",
      handle: "",
      defaultSendMode: "confirm",
      photoUrl: null,
      phoneHash: null,
      deletedAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  await admin
    .auth()
    .deleteUser(uid)
    .catch((error) => {
      logger.warn("Auth user deletion failed", { uid, error });
    });
  return { ok: true };
});

export const getOperationalHealth = onCall(
  { secrets: [deepgramApiKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const today = kstDateKey();
    const [bucketStatus, usageSnapshot, rollupSnapshot] = await Promise.all([
      storageBucketStatus(),
      db.collection("usageDaily").doc(dailyUsageDocId(uid)).get(),
      db.collection("usageRollups").doc(today).get(),
    ]);
    const deepgramConfigured = Boolean(
      normalizeSecretValue(
        process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
      ),
    );
    return {
      ok: bucketStatus.ok && deepgramConfigured,
      checkedAt: new Date().toISOString(),
      region: process.env.FUNCTIONS_REGION || "asia-northeast3",
      services: {
        firestore: true,
        storage: bucketStatus,
        functions: true,
        deepgram: {
          configured: deepgramConfigured,
          model: process.env.DEEPGRAM_MODEL || "nova-3",
        },
        translation: {
          providerConfigured: Boolean(process.env.TRANSLATION_API_URL),
          fallbackMode: process.env.TRANSLATION_API_URL
            ? "provider"
            : "free-preview",
        },
      },
      policies: {
        usageMode: "unlimited",
        textLimit: null,
        voiceLimit: null,
        defaultAudioRetentionDays: DEFAULT_AUDIO_RETENTION_DAYS,
        draftAudioRetentionDays: DRAFT_AUDIO_RETENTION_DAYS,
      },
      usageToday: serializeData(usageSnapshot.data() || null),
      latestRollup: serializeData(rollupSnapshot.data() || null),
    };
  },
);

export const pluginCoreApi = onRequest(
  {
    secrets: [deepgramApiKey],
    timeoutSeconds: 180,
    memory: "512MiB",
    cors: true,
  },
  async (request, response) => {
    try {
      if (request.method === "OPTIONS") {
        response.status(204).end();
        return;
      }
      const route = pluginRoutePath(request.url);
      if (request.method === "POST" && route === "/v1/transcriptions") {
        await handlePluginTranscriptionRequest(request, response);
        return;
      }
      if (request.method === "POST" && route === "/v1/message-cards") {
        await handlePluginMessageCardRequest(request, response);
        return;
      }
      if (request.method === "POST" && route === "/v1/calendar-intents") {
        await handlePluginCalendarIntentRequest(request, response);
        return;
      }
      if (request.method === "GET" && route.startsWith("/v1/audio/")) {
        await handlePluginAudioRequest(request, response, route);
        return;
      }
      response.status(404).json({
        error: {
          code: "not_found",
          message: "Plugin API route was not found.",
        },
      });
    } catch (error) {
      sendPluginError(response, error);
    }
  },
);

interface PluginHttpRequest {
  method: string;
  url: string;
  body?: unknown;
  header(name: string): string | undefined;
}

interface PluginHttpResponse {
  status(code: number): PluginHttpResponse;
  json(body: unknown): void;
  redirect(status: number, url: string): void;
  end(): void;
}

class PluginApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

async function handlePluginTranscriptionRequest(
  request: PluginHttpRequest,
  response: PluginHttpResponse,
) {
  const auth = await authenticatePluginRequest(request);
  const body = pluginJsonBody(request.body);
  assertPluginFeature(auth, "voiceTranscription");
  const apiKey = normalizeSecretValue(
    process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
  );
  if (!apiKey) {
    throw new PluginApiError(
      503,
      "stt_unavailable",
      "DEEPGRAM_API_KEY is not configured.",
    );
  }
  const startedAt = Date.now();
  const contentType = pluginContentType(body.contentType);
  const audioBytes = pluginAudioBase64(body.audioBase64);
  const language = normalizeDeepgramLanguage(
    optionalString(body.language) || "ko",
  );
  const transcription = await transcribeAudioBytesCached({
    apiKey,
    audioBytes,
    language,
    model: process.env.DEEPGRAM_MODEL || "nova-3",
    contentType,
  });
  const retentionDays = pluginAudioRetentionDays(auth, body.retentionDays);
  const shouldStoreAudio = body.storeAudio !== false;
  let audioId: string | null = null;
  let audioUrl: string | null = null;
  let audioExpiresAt: admin.firestore.Timestamp | null = null;
  if (shouldStoreAudio) {
    const stored = await storePluginAudio({
      auth,
      audioBytes,
      contentType,
      transcript: transcription.transcript,
      retentionDays,
      request,
      externalUserId: optionalString(body.externalUserId),
      conversationId: optionalString(body.conversationId),
      externalMessageId: optionalString(body.messageId),
    });
    audioId = stored.audioId;
    audioUrl = stored.audioUrl;
    audioExpiresAt = stored.expiresAt;
  }
  await recordPluginUsage(auth.partnerId, {
    transcriptionCount: 1,
    messageCardCount: 0,
    calendarIntentCount: 0,
    audioBytes: audioBytes.length,
    sttMs: Date.now() - startedAt,
  });
  response.status(200).json({
    transcript: transcription.transcript,
    sttStatus: transcription.transcript.trim() ? "completed" : "failed",
    language,
    model: transcription.model,
    cacheHit: transcription.cacheHit,
    audioHash: transcription.audioHash,
    audioId,
    audioUrl,
    audioRetentionDays: shouldStoreAudio ? retentionDays : null,
    audioExpiresAt: audioExpiresAt ? audioExpiresAt.toDate().toISOString() : null,
  });
}

async function handlePluginMessageCardRequest(
  request: PluginHttpRequest,
  response: PluginHttpResponse,
) {
  const auth = await authenticatePluginRequest(request);
  assertPluginFeature(auth, "messageCards");
  const body = pluginJsonBody(request.body);
  const card = renderPluginMessageCard(pluginMessageCardInput(body));
  await recordPluginUsage(auth.partnerId, {
    transcriptionCount: 0,
    messageCardCount: 1,
    calendarIntentCount: 0,
    audioBytes: 0,
    sttMs: 0,
  });
  response.status(200).json(card);
}

async function handlePluginCalendarIntentRequest(
  request: PluginHttpRequest,
  response: PluginHttpResponse,
) {
  const auth = await authenticatePluginRequest(request);
  assertPluginFeature(auth, "calendarIntents");
  const body = pluginJsonBody(request.body);
  let transcript = optionalString(body.transcript);
  const apiKey = normalizeSecretValue(
    process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
  );
  let transcriptionMeta: Record<string, unknown> | null = null;
  if (!transcript && typeof body.audioBase64 === "string") {
    if (!apiKey) {
      throw new PluginApiError(
        503,
        "stt_unavailable",
        "DEEPGRAM_API_KEY is not configured.",
      );
    }
    const audioBytes = pluginAudioBase64(body.audioBase64);
    const transcription = await transcribeAudioBytesCached({
      apiKey,
      audioBytes,
      language: normalizeDeepgramLanguage(optionalString(body.language) || "ko"),
      model: process.env.DEEPGRAM_MODEL || "nova-3",
      contentType: pluginContentType(body.contentType),
    });
    transcript = transcription.transcript;
    transcriptionMeta = {
      model: transcription.model,
      cacheHit: transcription.cacheHit,
      audioHash: transcription.audioHash,
    };
  }
  if (!transcript) {
    throw new PluginApiError(
      400,
      "transcript_required",
      "transcript or audioBase64 is required.",
    );
  }
  const parsed = parseCalendarCommand(transcript, {
    timezone: optionalString(body.timezone) || "Asia/Seoul",
  });
  await recordPluginUsage(auth.partnerId, {
    transcriptionCount: transcriptionMeta ? 1 : 0,
    messageCardCount: 0,
    calendarIntentCount: 1,
    audioBytes: 0,
    sttMs: 0,
  });
  response.status(200).json({
    transcript,
    parsedTitle: parsed.title,
    startAt: parsed.startAt ? parsed.startAt.toISOString() : null,
    endAt: parsed.endAt ? parsed.endAt.toISOString() : null,
    timezone: parsed.timezone,
    missingFields: parsed.missingFields,
    transcription: transcriptionMeta,
  });
}

async function handlePluginAudioRequest(
  request: PluginHttpRequest,
  response: PluginHttpResponse,
  route: string,
) {
  const auth = await authenticatePluginRequest(request);
  assertPluginFeature(auth, "audioPlayback");
  const audioId = decodeURIComponent(route.replace("/v1/audio/", "")).trim();
  if (!audioId || audioId.includes("/")) {
    throw new PluginApiError(400, "invalid_audio_id", "audioId is invalid.");
  }
  const snapshot = await db.collection("pluginAudio").doc(audioId).get();
  const audio = snapshot.data();
  if (!snapshot.exists || !audio || audio.partnerId !== auth.partnerId) {
    throw new PluginApiError(404, "audio_not_found", "Audio was not found.");
  }
  const expiresAt = audio.expiresAt;
  if (
    expiresAt instanceof admin.firestore.Timestamp &&
    expiresAt.toMillis() <= Date.now()
  ) {
    throw new PluginApiError(410, "audio_expired", "Audio has expired.");
  }
  const storagePath = optionalString(audio.storagePath);
  if (!storagePath) {
    throw new PluginApiError(404, "audio_not_found", "Audio was not found.");
  }
  const [url] = await bucket.file(storagePath).getSignedUrl({
    action: "read",
    expires: Date.now() + PLUGIN_SIGNED_URL_TTL_MINUTES * 60 * 1000,
  });
  response.redirect(302, url);
}

export const createDeepgramStreamingToken = onCall(
  VOICE_STT_CALL_OPTIONS,
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const apiKey = normalizeSecretValue(
      process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
    );
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "DEEPGRAM_API_KEY is not configured.",
      );
    }
    const language = normalizeDeepgramLanguage(
      optionalString(request.data?.language) || "ko-KR",
    );
    const model =
      optionalString(request.data?.model) ||
      process.env.DEEPGRAM_MODEL ||
      "nova-3";
    const tokenResponse = await fetch(
      "https://api.deepgram.com/v1/auth/grant",
      {
        method: "POST",
        headers: {
          Authorization: `Token ${apiKey}`,
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({}),
      },
    );
    const raw = await tokenResponse.text();
    if (!tokenResponse.ok) {
      logger.error("Deepgram token grant failed", {
        uid,
        status: tokenResponse.status,
        body: raw.slice(0, 500),
      });
      return {
        available: false,
        reason: "deepgram_token_grant_failed",
        expiresIn: 0,
      };
    }
    let payload: { access_token?: string; expires_in?: number };
    try {
      payload = JSON.parse(raw) as {
        access_token?: string;
        expires_in?: number;
      };
    } catch (error) {
      logger.error("Deepgram token response was not JSON", { uid, error });
      throw new HttpsError("internal", "Deepgram token response was invalid.");
    }
    const accessToken = payload.access_token;
    if (!accessToken) {
      logger.error("Deepgram token response missing access_token", { uid });
      return {
        available: false,
        reason: "deepgram_token_missing",
        expiresIn: 0,
      };
    }
    return {
      accessToken,
      expiresIn: boundedInt(payload.expires_in, 30, 1, 30),
      url: deepgramStreamingListenUrl(model, language),
      model,
      language,
      sampleRate: 16000,
      channels: 1,
      encoding: "linear16",
    };
  },
);

export const addFriendByHandle = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const handle = normalizeHandle(requiredString(request.data?.handle, "handle"));
  validateHandle(handle);

  const handleSnapshot = await db.collection("handles").doc(handle).get();
  const targetUid = handleSnapshot.data()?.uid;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("not-found", `Handle not found: ${handle}`);
  }
  if (targetUid === uid) {
    throw new HttpsError(
      "invalid-argument",
      "You cannot add yourself as a friend.",
    );
  }

  const targetSnapshot = await db.collection("users").doc(targetUid).get();
  const target = targetSnapshot.data();
  if (!target || typeof target.displayName !== "string") {
    throw new HttpsError("not-found", "User profile was not found.");
  }
  const targetHandle =
    typeof target.handle === "string" && target.handle.trim()
      ? target.handle.trim()
      : handle;
  const now = FieldValue.serverTimestamp();
  const friendPayload: Record<string, unknown> = {
    uid: targetUid,
    displayName: target.displayName,
    handle: targetHandle,
    defaultSendMode:
      typeof target.defaultSendMode === "string"
        ? target.defaultSendMode
        : "confirm",
    addedAt: now,
    updatedAt: now,
  };
  if (typeof target.photoUrl === "string" && target.photoUrl.trim()) {
    friendPayload.photoUrl = target.photoUrl.trim();
  }
  await db
    .collection("users")
    .doc(uid)
    .collection("friends")
    .doc(targetUid)
    .set(friendPayload, { merge: true });

  return {
    friend: {
      uid: targetUid,
      displayName: target.displayName,
      handle: targetHandle,
      defaultSendMode: friendPayload.defaultSendMode,
      photoUrl: friendPayload.photoUrl ?? null,
    },
  };
});

export const createRoom = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const participantHandles = stringArray(request.data?.participantHandles)
    .map(normalizeHandle)
    .filter(Boolean);
  const type = roomType(request.data?.type);
  const title = optionalString(request.data?.title);

  if (participantHandles.length === 0 && type !== "open") {
    throw new HttpsError(
      "invalid-argument",
      "At least one participant handle is required unless creating an open room.",
    );
  }
  participantHandles.forEach(validateHandle);

  const participantIds = new Set<string>([uid]);
  for (const handle of participantHandles) {
    const handleDoc = await db.collection("handles").doc(handle).get();
    const targetUid = handleDoc.data()?.uid;
    if (!targetUid || typeof targetUid !== "string") {
      throw new HttpsError("not-found", `Handle not found: ${handle}`);
    }
    participantIds.add(targetUid);
  }

  if (type === "direct" && participantIds.size !== 2) {
    throw new HttpsError(
      "invalid-argument",
      "Direct rooms must have exactly two participants.",
    );
  }

  const now = FieldValue.serverTimestamp();
  const roomRef = db.collection("rooms").doc();
  const participantIdList = [...participantIds];
  const batch = db.batch();
  batch.set(roomRef, {
    type,
    participantIds: participantIdList,
    ownerId: uid,
    title: title || defaultRoomTitle(type, participantHandles),
    audioRetentionDays: DEFAULT_AUDIO_RETENTION_DAYS,
    audioRetentionPreset: "oneDay",
    createdAt: now,
    updatedAt: now,
  });
  for (const participantId of participantIdList) {
    batch.set(roomRef.collection("members").doc(participantId), {
      role: participantId === uid ? "owner" : "member",
      joinedAt: now,
      lastReadAt: null,
      lastReadMessageId: null,
      unreadCount: 0,
      notificationMode: "all",
      pinned: false,
      archived: false,
      muted: false,
      updatedAt: now,
    });
  }
  await batch.commit();

  return { roomId: roomRef.id };
});

export const createRoomInvite = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  await enforceActionCooldown(
    uid,
    "createRoomInvite",
    INVITE_CREATE_COOLDOWN_MS,
  );
  const roomId = requiredString(request.data?.roomId, "roomId");
  const approvalRequired = request.data?.approvalRequired === true;
  const { roomRef } = await requireRoomManager(roomId, uid);
  const inviteRef = db.collection("roomInvites").doc();
  const token = inviteRef.id;
  const baseUrl = process.env.PUBLIC_APP_URL || "https://verbal.local";
  const url = `${baseUrl.replace(/\/$/, "")}/invite/${token}`;
  const createdAt = new Date();
  const now = FieldValue.serverTimestamp();
  const payload = {
    roomId,
    token,
    url,
    createdBy: uid,
    createdAt: now,
    approvalRequired,
    revokedAt: null,
  };
  const batch = db.batch();
  batch.set(inviteRef, payload);
  batch.set(
    roomRef,
    {
      inviteApprovalRequired: approvalRequired,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
  return {
    inviteId: inviteRef.id,
    roomId,
    token,
    url,
    createdBy: uid,
    createdAt: createdAt.toISOString(),
    approvalRequired,
    revokedAt: null,
  };
});

export const revokeRoomInvite = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const inviteId = requiredString(request.data?.inviteId, "inviteId");
  await requireRoomManager(roomId, uid);
  const inviteRef = db.collection("roomInvites").doc(inviteId);
  const invite = await inviteRef.get();
  if (!invite.exists || invite.data()?.roomId !== roomId) {
    throw new HttpsError("not-found", "Invite was not found.");
  }
  await inviteRef.set(
    {
      revokedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

export const setInviteApprovalRequired = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const approvalRequired = booleanValue(
    request.data?.approvalRequired,
    "approvalRequired",
  );
  const { roomRef } = await requireRoomManager(roomId, uid);
  await roomRef.set(
    {
      inviteApprovalRequired: approvalRequired,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

export const setRoomAudioRetention = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const days = boundedInt(
    request.data?.days,
    DEFAULT_AUDIO_RETENTION_DAYS,
    1,
    30,
  );
  const preset = audioRetentionPreset(request.data?.preset, days);
  const { roomRef } = await requireRoomManager(roomId, uid);
  await roomRef.set(
    {
      audioRetentionDays: days,
      audioRetentionPreset: preset,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true, days, preset };
});

export const joinRoomByInvite = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  await enforceActionCooldown(uid, "joinRoomByInvite", INVITE_JOIN_COOLDOWN_MS);
  const token = inviteToken(request.data?.token);
  const inviteRef = db.collection("roomInvites").doc(token);
  const invite = await inviteRef.get();
  const inviteData = invite.data();
  if (!invite.exists || !inviteData) {
    throw new HttpsError("not-found", "Invite was not found.");
  }
  if (inviteData.revokedAt) {
    throw new HttpsError("failed-precondition", "Invite has been revoked.");
  }
  if (isExpired(inviteData.expiresAt)) {
    throw new HttpsError("failed-precondition", "Invite has expired.");
  }

  const roomId = requiredString(inviteData.roomId, "roomId");
  const roomRef = db.collection("rooms").doc(roomId);
  const roomSnapshot = await roomRef.get();
  const room = roomSnapshot.data() as RoomData | undefined;
  if (!roomSnapshot.exists || !room || !Array.isArray(room.participantIds)) {
    throw new HttpsError("not-found", "Room was not found.");
  }

  const memberRef = roomRef.collection("members").doc(uid);
  const memberSnapshot = await memberRef.get();
  if (room.participantIds.includes(uid) && !memberSnapshot.data()?.leftAt) {
    return { status: "joined", roomId, room };
  }

  if (room.type === "direct" && room.participantIds.length >= 2) {
    throw new HttpsError(
      "failed-precondition",
      "Direct rooms cannot accept invite joins.",
    );
  }

  const user = await db.collection("users").doc(uid).get();
  const userData = user.data() || {};
  const approvalRequired =
    inviteData.approvalRequired === true ||
    roomSnapshot.data()?.inviteApprovalRequired === true;
  if (approvalRequired) {
    const joinRequest: RoomJoinRequest = {
      uid,
      roomId,
      inviteId: invite.id,
      status: "pending",
      displayName: optionalString(userData.displayName),
      handle: optionalString(userData.handle),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    await roomRef
      .collection("joinRequests")
      .doc(uid)
      .set(joinRequest, { merge: true });
    return { status: "pending", roomId, requestId: uid };
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    roomRef,
    {
      participantIds: FieldValue.arrayUnion(uid),
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    memberRef,
    {
      role: "member",
      joinedAt: now,
      leftAt: FieldValue.delete(),
      lastReadAt: null,
      lastReadMessageId: null,
      unreadCount: 0,
      notificationMode: "all",
      pinned: false,
      archived: false,
      muted: false,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();

  const joinedRoom = await roomRef.get();
  return { status: "joined", roomId, room: joinedRoom.data() };
});

export const approveRoomJoinRequest = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const memberUid = requiredString(request.data?.memberUid, "memberUid");
  const { roomRef } = await requireRoomManager(roomId, uid);
  const requestRef = roomRef.collection("joinRequests").doc(memberUid);
  const requestSnapshot = await requestRef.get();
  const joinRequest = requestSnapshot.data() as RoomJoinRequest | undefined;
  if (
    !requestSnapshot.exists ||
    !joinRequest ||
    joinRequest.status !== "pending"
  ) {
    throw new HttpsError("not-found", "Join request was not found.");
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    roomRef,
    {
      participantIds: FieldValue.arrayUnion(memberUid),
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    roomRef.collection("members").doc(memberUid),
    {
      role: "member",
      joinedAt: now,
      leftAt: FieldValue.delete(),
      lastReadAt: null,
      lastReadMessageId: null,
      unreadCount: 0,
      notificationMode: "all",
      pinned: false,
      archived: false,
      muted: false,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    requestRef,
    {
      status: "approved",
      reviewedAt: now,
      reviewedBy: uid,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
  return { ok: true };
});

export const rejectRoomJoinRequest = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const memberUid = requiredString(request.data?.memberUid, "memberUid");
  const { roomRef } = await requireRoomManager(roomId, uid);
  const requestRef = roomRef.collection("joinRequests").doc(memberUid);
  const requestSnapshot = await requestRef.get();
  if (!requestSnapshot.exists) {
    throw new HttpsError("not-found", "Join request was not found.");
  }
  const now = FieldValue.serverTimestamp();
  await requestRef.set(
    {
      status: "rejected",
      reviewedAt: now,
      reviewedBy: uid,
      updatedAt: now,
    },
    { merge: true },
  );
  return { ok: true };
});

export const updateRoomMemberRole = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const memberUid = requiredString(request.data?.memberUid, "memberUid");
  const role = roomMemberRole(request.data?.role);
  const { roomRef, memberRole } = await requireRoomManager(roomId, uid);
  if (role === "owner" && memberRole !== "owner") {
    throw new HttpsError(
      "permission-denied",
      "Only the owner can transfer ownership.",
    );
  }
  const memberRef = roomRef.collection("members").doc(memberUid);
  const target = await memberRef.get();
  if (!target.exists || target.data()?.leftAt) {
    throw new HttpsError("not-found", "Member was not found.");
  }
  const batch = db.batch();
  batch.set(
    memberRef,
    { role, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  if (role === "owner") {
    batch.set(
      roomRef,
      { ownerId: memberUid, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    batch.set(
      roomRef.collection("members").doc(uid),
      {
        role: "admin",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
  return { ok: true };
});

export const removeRoomMember = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const memberUid = requiredString(request.data?.memberUid, "memberUid");
  if (memberUid === uid) {
    throw new HttpsError(
      "invalid-argument",
      "Use leaveRoom to remove yourself.",
    );
  }
  const { roomRef, room } = await requireRoomManager(roomId, uid);
  const memberRef = roomRef.collection("members").doc(memberUid);
  const member = await memberRef.get();
  if (!member.exists || member.data()?.role === "owner") {
    throw new HttpsError("permission-denied", "This member cannot be removed.");
  }
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    roomRef,
    {
      participantIds: room.participantIds.filter((id) => id !== memberUid),
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    memberRef,
    {
      leftAt: now,
      archived: true,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
  return { ok: true };
});

export const sendTextMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const text = requiredString(request.data?.text, "text").trim();
  if (text.length === 0 || text.length > 4000) {
    throw new HttpsError("invalid-argument", "Text message length is invalid.");
  }

  await recordDailyUsage(uid, { textCount: 1 });
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc();
  const replyTo = await replyToValue(
    roomRef,
    optionalString(request.data?.replyToMessageId),
  );
  const message: MessageData = {
    senderId: uid,
    kind: "text",
    text,
    transcript: "",
    audioPath: null,
    durationMs: 0,
    sttStatus: "none",
    sendMode: "confirm",
    replyTo,
  };
  await createMessage(roomRef, room, messageRef.id, message, text);
  return { messageId: messageRef.id };
});

export const scheduleTextMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const text = requiredString(request.data?.text, "text").trim();
  const scheduledAt = dateValue(request.data?.scheduledAt, "scheduledAt");
  if (text.length === 0 || text.length > 4000) {
    throw new HttpsError("invalid-argument", "Text message length is invalid.");
  }
  if (scheduledAt.getTime() < Date.now() - 30000) {
    throw new HttpsError(
      "invalid-argument",
      "Scheduled time must be in the future.",
    );
  }

  await recordDailyUsage(uid, { textCount: 1 });
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc();
  const replyTo = await replyToValue(
    roomRef,
    optionalString(request.data?.replyToMessageId),
  );
  await messageRef.set({
    senderId: uid,
    kind: "text",
    text,
    transcript: "",
    audioPath: null,
    durationMs: 0,
    sttStatus: "none",
    sendMode: "confirm",
    replyTo,
    deliveryStatus: "scheduled",
    scheduledAt,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { messageId: messageRef.id };
});

export const sendScheduledMessageNow = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const snapshot = await messageRef.get();
  const message = snapshot.data() as MessageData | undefined;
  if (
    !snapshot.exists ||
    !message ||
    message.senderId !== uid ||
    message.deletedAt
  ) {
    throw new HttpsError(
      "permission-denied",
      "Scheduled message access denied.",
    );
  }
  if (message.deliveryStatus !== "scheduled") {
    return { ok: true };
  }
  await deliverScheduledMessage(roomRef, room, messageId, message);
  return { ok: true };
});

export const sendAttachmentMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const kind = attachmentMessageKind(request.data?.kind);
  const attachment = attachmentValue(
    request.data?.attachment,
    kind,
    roomId,
    uid,
  );
  const caption = optionalString(request.data?.caption).slice(0, 1000);
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc();
  const replyTo = await replyToValue(
    roomRef,
    optionalString(request.data?.replyToMessageId),
  );
  const message: MessageData = {
    senderId: uid,
    kind,
    text: caption,
    transcript: "",
    audioPath: null,
    durationMs: 0,
    sttStatus: "none",
    sendMode: "confirm",
    replyTo,
    attachment,
    deliveryStatus: "sent",
  };
  await createMessage(
    roomRef,
    room,
    messageRef.id,
    message,
    caption || attachmentPreview(attachment),
  );
  return { messageId: messageRef.id };
});

export const createCalendarProposal = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const title = calendarProposalTitle(request.data?.title);
  const details = calendarProposalDetails(request.data?.details);
  const timezone = calendarTimezoneValue(request.data?.timezone);
  const candidates = calendarProposalCandidates(request.data?.candidates);
  const transcript = optionalString(request.data?.transcript).slice(0, 4000);
  const source =
    optionalString(request.data?.source) === "voice" ? "voice" : "manual";
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc();
  const proposalRef = roomRef.collection("calendarProposals").doc();
  const replyTo = await replyToValue(
    roomRef,
    optionalString(request.data?.replyToMessageId),
  );
  const proposal: CalendarProposalData = {
    roomId,
    messageId: messageRef.id,
    createdBy: uid,
    title,
    details,
    timezone,
    status: "open",
    candidates,
    votes: {},
    finalCandidateId: null,
    source,
    transcript,
  };
  const message: MessageData = {
    senderId: uid,
    kind: "calendarProposal",
    text: title,
    transcript,
    audioPath: null,
    durationMs: 0,
    sttStatus: "none",
    sendMode: "confirm",
    replyTo,
    calendarProposal: {
      ...proposal,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    deliveryStatus: "sent",
  };
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(proposalRef, {
    ...proposal,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(messageRef, {
    ...message,
    calendarProposal: {
      ...proposal,
      id: proposalRef.id,
      createdAt: now,
      updatedAt: now,
    },
    createdAt: now,
    updatedAt: now,
  });
  batch.set(
    roomRef,
    {
      lastMessage: {
        messageId: messageRef.id,
        kind: "calendarProposal",
        preview: calendarProposalPreview(title),
        senderId: uid,
        createdAt: now,
      },
      updatedAt: now,
    },
    { merge: true },
  );
  for (const participantId of room.participantIds) {
    batch.set(
      roomRef.collection("members").doc(participantId),
      participantId === uid
        ? {
            lastReadAt: now,
            lastReadMessageId: messageRef.id,
            unreadCount: 0,
            updatedAt: now,
          }
        : {
            unreadCount: FieldValue.increment(1),
            updatedAt: now,
          },
      { merge: true },
    );
  }
  await batch.commit();
  return { proposalId: proposalRef.id, messageId: messageRef.id };
});

export const voteCalendarProposal = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const proposalId = requiredString(request.data?.proposalId, "proposalId");
  const candidateIds = stringArray(request.data?.candidateIds);
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const proposalRef = roomRef.collection("calendarProposals").doc(proposalId);
  const voteRef = proposalRef.collection("votes").doc(uid);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(proposalRef);
    const proposal = proposalSnapshot(snapshot, roomId, proposalId);
    if (proposal.status !== "open") {
      throw new HttpsError(
        "failed-precondition",
        "Calendar proposal is not open.",
      );
    }
    const validIds = new Set(
      proposal.candidates.map((candidate) => candidate.candidateId),
    );
    const selected = [...new Set(candidateIds)].filter((id) =>
      validIds.has(id),
    );
    const votes = calendarProposalVotes(proposal.votes);
    votes[uid] = selected;
    const now = FieldValue.serverTimestamp();
    transaction.set(
      voteRef,
      {
        uid,
        candidateIds: selected,
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(
      proposalRef,
      {
        votes,
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(
      roomRef.collection("messages").doc(proposal.messageId),
      {
        calendarProposal: {
          ...proposal,
          id: proposalId,
          votes,
          updatedAt: now,
        },
        updatedAt: now,
      },
      { merge: true },
    );
  });
  return { ok: true };
});

export const finalizeCalendarProposal = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const proposalId = requiredString(request.data?.proposalId, "proposalId");
  const candidateId = requiredString(request.data?.candidateId, "candidateId");
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const member = await roomRef.collection("members").doc(uid).get();
  const role = roomMemberRole(member.data()?.role);
  const proposalRef = roomRef.collection("calendarProposals").doc(proposalId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(proposalRef);
    const proposal = proposalSnapshot(snapshot, roomId, proposalId);
    if (proposal.status !== "open") {
      throw new HttpsError(
        "failed-precondition",
        "Calendar proposal is not open.",
      );
    }
    if (proposal.createdBy !== uid && role !== "owner" && role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Calendar proposal manager permission is required.",
      );
    }
    const candidate = proposal.candidates.find(
      (item) => item.candidateId === candidateId,
    );
    if (!candidate) {
      throw new HttpsError("invalid-argument", "Candidate was not found.");
    }
    const votes = calendarProposalVotes(proposal.votes);
    const ownerIds = new Set<string>([proposal.createdBy]);
    for (const [voterId, selectedIds] of Object.entries(votes)) {
      if (selectedIds.includes(candidateId)) {
        ownerIds.add(voterId);
      }
    }
    const now = FieldValue.serverTimestamp();
    const updatedProposal = {
      ...proposal,
      id: proposalId,
      status: "finalized" as const,
      finalCandidateId: candidateId,
      updatedAt: now,
    };
    transaction.set(
      proposalRef,
      {
        status: "finalized",
        finalCandidateId: candidateId,
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(
      roomRef.collection("messages").doc(proposal.messageId),
      {
        calendarProposal: updatedProposal,
        updatedAt: now,
      },
      { merge: true },
    );
    for (const ownerId of ownerIds) {
      const eventRef = db
        .collection("users")
        .doc(ownerId)
        .collection("calendarEvents")
        .doc(`${safeId(proposalId)}_${safeId(candidateId)}`);
      transaction.set(
        eventRef,
        calendarEventFromProposal(
          ownerId,
          roomId,
          proposalId,
          proposal,
          candidate,
        ),
        { merge: true },
      );
    }
  });
  return { ok: true };
});

export const addFinalizedProposalToMyCalendar = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const proposalId = requiredString(request.data?.proposalId, "proposalId");
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const snapshot = await roomRef
    .collection("calendarProposals")
    .doc(proposalId)
    .get();
  const proposal = proposalSnapshot(snapshot, roomId, proposalId);
  if (proposal.status !== "finalized" || !proposal.finalCandidateId) {
    throw new HttpsError(
      "failed-precondition",
      "Only finalized proposals can be added to a calendar.",
    );
  }
  const candidate = proposal.candidates.find(
    (item) => item.candidateId === proposal.finalCandidateId,
  );
  if (!candidate) {
    throw new HttpsError("not-found", "Final candidate was not found.");
  }
  await db
    .collection("users")
    .doc(uid)
    .collection("calendarEvents")
    .doc(`${safeId(proposalId)}_${safeId(candidate.candidateId)}`)
    .set(
      calendarEventFromProposal(uid, roomId, proposalId, proposal, candidate),
      { merge: true },
    );
  return { ok: true };
});

export const cancelCalendarProposal = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const proposalId = requiredString(request.data?.proposalId, "proposalId");
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const member = await roomRef.collection("members").doc(uid).get();
  const role = roomMemberRole(member.data()?.role);
  const proposalRef = roomRef.collection("calendarProposals").doc(proposalId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(proposalRef);
    const proposal = proposalSnapshot(snapshot, roomId, proposalId);
    if (proposal.createdBy !== uid && role !== "owner" && role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Calendar proposal manager permission is required.",
      );
    }
    const now = FieldValue.serverTimestamp();
    const updatedProposal = {
      ...proposal,
      id: proposalId,
      status: "cancelled" as const,
      updatedAt: now,
    };
    transaction.set(
      proposalRef,
      {
        status: "cancelled",
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(
      roomRef.collection("messages").doc(proposal.messageId),
      {
        calendarProposal: updatedProposal,
        updatedAt: now,
      },
      { merge: true },
    );
  });
  return { ok: true };
});

export const createTranscriptionDraft = onCall(
  { secrets: [deepgramApiKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const draftId =
      optionalString(request.data?.draftId) || db.collection("_ids").doc().id;
    const audioPath = requiredString(request.data?.audioPath, "audioPath");
    const language = optionalString(request.data?.language) || "ko";
    const transcriptOverride = sanitizeVoiceTranscript(
      request.data?.transcriptOverride,
    );
    const durationMs = numberValue(request.data?.durationMs, 0);
    assertVoiceDuration(durationMs);

    if (!audioPath.startsWith(`voice_drafts/${uid}/`)) {
      throw new HttpsError(
        "permission-denied",
        "Draft audio path is not owned by the caller.",
      );
    }
    await recordDailyUsage(uid, { voiceCount: 1, voiceMs: durationMs });

    const draftRef = db.collection("transcriptionDrafts").doc(draftId);
    const draftAudioExpiresAt = retentionExpiryTimestamp(
      DRAFT_AUDIO_RETENTION_DAYS,
    );
    await draftRef.set({
      ownerId: uid,
      audioPath,
      language,
      durationMs,
      audioExpiresAt: draftAudioExpiresAt,
      audioRetentionDays: DRAFT_AUDIO_RETENTION_DAYS,
      audioRetentionStatus: "active",
      status: "processing",
      transcript: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (transcriptOverride) {
      await draftRef.set(
        {
          status: "completed",
          transcript: transcriptOverride,
          audioHash: null,
          sttCacheHit: false,
          errorCode: null,
          manualTranscript: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return {
        id: draftId,
        audioPath,
        transcript: transcriptOverride,
        status: "completed",
        durationMs,
        audioHash: null,
        sttCacheHit: false,
      };
    }

    try {
      const transcription = await transcribeStorageAudio(audioPath, language);
      await draftRef.set(
        {
          status: "completed",
          transcript: transcription.transcript,
          audioHash: transcription.audioHash,
          sttCacheHit: transcription.cacheHit,
          errorCode: null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return {
        id: draftId,
        audioPath,
        transcript: transcription.transcript,
        status: "completed",
        durationMs,
        audioHash: transcription.audioHash,
        sttCacheHit: transcription.cacheHit,
      };
    } catch (error) {
      logger.error("createTranscriptionDraft failed", {
        draftId,
        audioPath,
        error: errorDetails(error),
      });
      await draftRef.set(
        {
          status: "failed",
          errorCode: errorCode(error),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw new HttpsError("internal", "Transcription failed.");
    }
  },
);

export const createCalendarIntentDraft = onCall(
  { secrets: [deepgramApiKey] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const draftId =
      optionalString(request.data?.draftId) || db.collection("_ids").doc().id;
    const audioPath = requiredString(request.data?.audioPath, "audioPath");
    const language = optionalString(request.data?.language) || "ko";
    const transcriptOverride = sanitizeVoiceTranscript(
      request.data?.transcriptOverride,
    );
    const durationMs = numberValue(request.data?.durationMs, 0);
    assertVoiceDuration(durationMs);

    if (!audioPath.startsWith(`voice_drafts/${uid}/`)) {
      throw new HttpsError(
        "permission-denied",
        "Calendar draft audio path is not owned by the caller.",
      );
    }

    await recordDailyUsage(uid, { voiceCount: 1, voiceMs: durationMs });

    let transcript = transcriptOverride;
    try {
      if (!transcript) {
        const transcription = await transcribeStorageAudio(audioPath, language);
        transcript = transcription.transcript;
      }
    } catch (error) {
      logger.error("createCalendarIntentDraft failed", {
        draftId,
        audioPath,
        error: errorDetails(error),
      });
      throw new HttpsError("internal", "Calendar voice transcription failed.");
    } finally {
      await deleteStorageFile(audioPath);
    }

    const parsed = parseCalendarCommand(transcript, {
      now: new Date(),
      timezone: "Asia/Seoul",
      defaultDurationMinutes: 60,
    });

    return {
      draftId,
      transcript,
      parsedTitle: parsed.title,
      startAt: parsed.startAt ? parsed.startAt.toISOString() : null,
      endAt: parsed.endAt ? parsed.endAt.toISOString() : null,
      timezone: parsed.timezone,
      missingFields: parsed.missingFields,
    };
  },
);

export const createCalendarEvent = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const eventRef = db
    .collection("users")
    .doc(uid)
    .collection("calendarEvents")
    .doc();
  const event = calendarEventPayload(uid, request.data, true);
  await eventRef.set(event);
  const snapshot = await eventRef.get();
  return {
    eventId: eventRef.id,
    event: {
      id: eventRef.id,
      ...(serializeData(snapshot.data() || {}) as Record<string, unknown>),
    },
  };
});

export const updateCalendarEvent = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const eventId = requiredString(request.data?.eventId, "eventId");
  const eventRef = db
    .collection("users")
    .doc(uid)
    .collection("calendarEvents")
    .doc(eventId);
  const snapshot = await eventRef.get();
  const data = snapshot.data() as CalendarEventData | undefined;
  if (!snapshot.exists || !data || data.ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Calendar event is not owned by the caller.",
    );
  }
  await eventRef.set(
    calendarEventPayload(
      uid,
      {
        ...(request.data || {}),
        source: data.source,
        details: request.data?.details ?? data.details,
        transcript: data.transcript,
      },
      false,
    ),
    {
      merge: true,
    },
  );
  const updated = await eventRef.get();
  return {
    eventId,
    event: {
      id: eventId,
      ...(serializeData(updated.data() || {}) as Record<string, unknown>),
    },
  };
});

export const deleteCalendarEvent = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const eventId = requiredString(request.data?.eventId, "eventId");
  const eventRef = db
    .collection("users")
    .doc(uid)
    .collection("calendarEvents")
    .doc(eventId);
  const snapshot = await eventRef.get();
  const data = snapshot.data() as CalendarEventData | undefined;
  if (!snapshot.exists || !data || data.ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Calendar event is not owned by the caller.",
    );
  }
  await eventRef.delete();
  return { eventId, deleted: true };
});

export const updateCalendarNotificationSettings = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const settings = calendarNotificationSettingsPayload(
    (request.data || {}) as Record<string, unknown>,
  );
  await db
    .collection("users")
    .doc(uid)
    .set(
      {
        ...settings,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return settings;
});

export const sendVoiceMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const draftId = requiredString(request.data?.draftId, "draftId");
  const finalText = requiredString(request.data?.finalText, "finalText").trim();
  const sendMode = sendModeValue(request.data?.sendMode);

  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const draft = await db.collection("transcriptionDrafts").doc(draftId).get();
  const draftData = draft.data();
  if (!draft.exists || draftData?.ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Draft is not owned by the caller.",
    );
  }
  if (draftData.status !== "completed") {
    throw new HttpsError(
      "failed-precondition",
      "Draft transcription is not completed.",
    );
  }

  const messageRef = roomRef.collection("messages").doc();
  const retentionDays = roomAudioRetentionDays(room);
  const sourceAudioPath = String(draftData.audioPath || "");
  const targetAudioPath = `voice_messages/${roomId}/${messageRef.id}${audioExtension(sourceAudioPath)}`;
  await copyAudioObject(sourceAudioPath, targetAudioPath, {
    roomId,
    ownerId: uid,
    durationMs: numberValue(draftData.durationMs, 0).toString(),
    language: String(draftData.language || "ko"),
    audioHash:
      typeof draftData.audioHash === "string" ? draftData.audioHash : "",
  });
  const replyTo = await replyToValue(
    roomRef,
    optionalString(request.data?.replyToMessageId),
  );
  const message: MessageData = {
    senderId: uid,
    kind: "voice",
    text: finalText,
    transcript: String(draftData.transcript || ""),
    audioPath: targetAudioPath,
    audioHash:
      typeof draftData.audioHash === "string" ? draftData.audioHash : null,
    audioExpiresAt: retentionExpiryTimestamp(retentionDays),
    audioRetentionDays: retentionDays,
    audioRetentionStatus: "active",
    durationMs: numberValue(draftData.durationMs, 0),
    sttStatus: "completed",
    sttCacheHit: draftData.sttCacheHit === true,
    sendMode,
    language: String(draftData.language || "ko"),
    replyTo,
  };
  await createMessage(
    roomRef,
    room,
    messageRef.id,
    message,
    finalText || "\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC \uC5C6\uC74C",
  );
  await deleteStorageFile(sourceAudioPath);
  await draft.ref.set(
    {
      audioDeletedAt: FieldValue.serverTimestamp(),
      audioRetentionStatus: "moved",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { messageId: messageRef.id };
});

export const sendInstantVoiceMessage = onCall(
  VOICE_STT_CALL_OPTIONS,
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const roomId = requiredString(request.data?.roomId, "roomId");
    const messageId =
      optionalString(request.data?.messageId) || db.collection("_ids").doc().id;
    const audioPath = requiredString(request.data?.audioPath, "audioPath");
    const durationMs = numberValue(request.data?.durationMs, 0);
    const language = optionalString(request.data?.language) || "ko";
    const transcriptOverride = sanitizeVoiceTranscript(
      request.data?.transcriptOverride,
    );
    const sendMode = sendModeValue(request.data?.sendMode);
    assertVoiceDuration(durationMs);

    if (!audioPath.startsWith(`voice_drafts/${uid}/`)) {
      throw new HttpsError(
        "permission-denied",
        "Draft audio path is not owned by the caller.",
      );
    }

    const { roomRef, room } = await requireRoomParticipant(roomId, uid);
    await recordDailyUsage(uid, { voiceCount: 1, voiceMs: durationMs });
    const retentionDays = roomAudioRetentionDays(room);
    const targetAudioPath = `voice_messages/${roomId}/${messageId}${audioExtension(audioPath)}`;
    await copyAudioObject(audioPath, targetAudioPath, {
      roomId,
      ownerId: uid,
      durationMs: durationMs.toString(),
      language,
    });
    const replyTo = await replyToValue(
      roomRef,
      optionalString(request.data?.replyToMessageId),
    );

    let transcript = transcriptOverride;
    let audioHash: string | null = null;
    let sttCacheHit = false;
    let sttStatus: SttStatus = transcript ? "completed" : "processing";
    let sttErrorCode: string | null = null;
    if (!transcript) {
      try {
        const transcription = await transcribeStorageAudio(
          targetAudioPath,
          language,
        );
        transcript = sanitizeVoiceTranscriptForLanguage(
          transcription.transcript,
          language,
        );
        if (!transcript) {
          throw new HttpsError(
            "internal",
            "Speech-to-text returned an empty transcript.",
          );
        }
        audioHash = transcription.audioHash;
        sttCacheHit = transcription.cacheHit;
        sttStatus = "completed";
      } catch (error) {
        logger.error("sendInstantVoiceMessage inline STT failed", {
          roomId,
          messageId,
          error,
        });
        await Promise.allSettled([
          deleteStorageFile(audioPath),
          deleteStorageFile(targetAudioPath),
        ]);
        throw new HttpsError(
          "internal",
          "\uC74C\uC131 \uC778\uC2DD\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB179\uC74C\uD574 \uC8FC\uC138\uC694.",
        );
      }
    }

    const message: MessageData = {
      senderId: uid,
      kind: "voice",
      text: transcript,
      transcript,
      audioPath: targetAudioPath,
      audioHash,
      audioExpiresAt: retentionExpiryTimestamp(retentionDays),
      audioRetentionDays: retentionDays,
      audioRetentionStatus: "active",
      durationMs,
      sttStatus,
      sttCacheHit,
      errorCode: sttErrorCode,
      sendMode,
      language,
      replyTo,
    };
    await createMessage(
      roomRef,
      room,
      messageId,
      message,
      transcript || "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328",
    );
    await deleteStorageFile(audioPath);
    return { messageId };
  },
);

async function waitForMessageData(
  messageRef: admin.firestore.DocumentReference,
  notFoundMessage: string,
  timeoutMs = 2500,
): Promise<{ message: MessageData }> {
  const startedAt = Date.now();
  let delayMs = 80;
  for (;;) {
    const snapshot = await messageRef.get();
    const message = snapshot.data() as MessageData | undefined;
    if (snapshot.exists && message) {
      return { message };
    }
    if (Date.now() - startedAt >= timeoutMs) {
      throw new HttpsError("not-found", notFoundMessage);
    }
    await sleepMs(delayMs);
    delayMs = Math.min(240, delayMs + 40);
  }
}

export const finalizeClientVoiceMessage = onCall(
  VOICE_STT_CALL_OPTIONS,
  async (request) => {
    const startedAt = Date.now();
    const uid = requireUid(request.auth?.uid);
    const roomId = requiredString(request.data?.roomId, "roomId");
    const messageId = requiredString(request.data?.messageId, "messageId");
    const audioPath = requiredString(request.data?.audioPath, "audioPath");
    const durationMs = numberValue(request.data?.durationMs, 0);
    const language = optionalString(request.data?.language) || "ko";
    const transcriptOverride = sanitizeVoiceTranscript(
      request.data?.transcriptOverride,
    );
    const clientUploadMs = numberValue(request.data?.clientUploadMs, 0);
    const deferStt = request.data?.deferStt === true;
    const forceServerSttCorrection =
      request.data?.forceServerSttCorrection === true;
    assertVoiceDuration(durationMs);

    if (!audioPath.startsWith(`voice_drafts/${uid}/`)) {
      throw new HttpsError(
        "permission-denied",
        "Draft audio path is not owned by the caller.",
      );
    }
    if (!path.basename(audioPath).startsWith(messageId)) {
      throw new HttpsError(
        "permission-denied",
        "Draft audio path does not match the target message.",
      );
    }

    const { roomRef, room } = await requireRoomParticipant(roomId, uid);
    const messageRef = roomRef.collection("messages").doc(messageId);
    const { message } = await waitForMessageData(
      messageRef,
      "Pending voice message was not found.",
    );
    if (
      message.kind !== "voice" ||
      message.senderId !== uid ||
      message.clientCreated !== true ||
      message.deliveryStatus !== "sending" ||
      message.audioPath
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Message is not a pending client voice message.",
      );
    }

    await recordDailyUsage(uid, { voiceCount: 1, voiceMs: durationMs });
    const retentionDays = roomAudioRetentionDays(room);
    const targetAudioPath = `voice_messages/${roomId}/${messageId}${audioExtension(audioPath)}`;
    await copyAudioObject(audioPath, targetAudioPath, {
      roomId,
      ownerId: uid,
      durationMs: durationMs.toString(),
      language,
    });

    let transcript = preferBetterVoiceTranscript(
      transcriptOverride,
      voiceTranscriptFromMessage(message),
    );
    let audioHash: string | null = null;
    let sttCacheHit = false;
    let sttStatus: SttStatus = transcript ? "completed" : "processing";
    let sttErrorCode: string | null = null;
    if (!transcript) {
      const latestBeforeSttSnapshot = await messageRef.get();
      const latestBeforeStt = latestBeforeSttSnapshot.data() as
        | MessageData
        | undefined;
      const latestTranscript = voiceTranscriptFromMessage(latestBeforeStt);
      if (latestTranscript) {
        transcript = latestTranscript;
        audioHash =
          typeof latestBeforeStt?.audioHash === "string"
            ? latestBeforeStt.audioHash
            : null;
        sttStatus = "completed";
        sttErrorCode = null;
      }
    }
    if (!transcript || forceServerSttCorrection || deferStt) {
      // Finalization only makes the voice message deliverable and playable.
      // Deepgram STT runs through inline client STT and the update trigger, so
      // the user-facing send path does not wait on a network transcription.
      sttCacheHit = false;
    }
    if (!transcript) {
      sttStatus = "processing";
      sttErrorCode = null;
    }

    const now = FieldValue.serverTimestamp();
    const latestSnapshot = await messageRef.get();
    const latestMessage = latestSnapshot.data() as MessageData | undefined;
    const latestTranscript = voiceTranscriptFromMessage(latestMessage);
    if (isBetterVoiceTranscriptCandidate(latestTranscript, transcript)) {
      transcript = latestTranscript;
      sttStatus = "completed";
      sttErrorCode = null;
    }
    const preview =
      transcript ||
      (sttStatus === "processing" ? "\uC74C\uC131 \uBCC0\uD658 \uC911..." : "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328");
    const latestRoomSnapshot = await roomRef.get();
    const latestRoom = latestRoomSnapshot.data() as RoomData | undefined;
    const shouldUpdateLastMessage =
      latestRoom?.lastMessage?.messageId === messageId;
    const messageUpdate: Record<string, unknown> = {
      audioPath: targetAudioPath,
      audioExpiresAt: retentionExpiryTimestamp(retentionDays),
      audioRetentionDays: retentionDays,
      audioRetentionStatus: "active",
      durationMs,
      deliveryStatus: "sent",
      updatedAt: now,
    };
    if (transcript) {
      messageUpdate.text = transcript;
      messageUpdate.transcript = transcript;
      messageUpdate.audioHash = audioHash;
      messageUpdate.sttStatus = sttStatus;
      messageUpdate.sttCacheHit = sttCacheHit;
      messageUpdate.errorCode = sttErrorCode;
    } else if (deferStt) {
      // Keep the message explicitly recoverable. The audioPath update below
      // wakes the Firestore update trigger, which then runs the storage STT
      // fallback without blocking client-side send completion.
      messageUpdate.sttStatus = "processing";
      messageUpdate.errorCode = null;
    } else if (!deferStt) {
      messageUpdate.audioHash = audioHash;
      messageUpdate.sttStatus = sttStatus;
      messageUpdate.sttCacheHit = sttCacheHit;
      messageUpdate.errorCode = sttErrorCode;
    }
    const batch = db.batch();
    batch.set(messageRef, messageUpdate, { merge: true });
    if (shouldUpdateLastMessage && (transcript || !deferStt)) {
      batch.set(
        roomRef,
        {
          lastMessage: {
            messageId,
            kind: "voice",
            preview: transcript || preview,
            senderId: uid,
            createdAt: message.createdAt || now,
          },
          updatedAt: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
    await deleteStorageFile(audioPath);
    logger.info("finalizeClientVoiceMessage completed", {
      roomId,
      messageId,
      clientUploadMs,
      sttMs: 0,
      deferStt,
      forceServerSttCorrection,
      finalizeFunctionMs: Date.now() - startedAt,
    });
    return { messageId, sttStatus };
  },
);

export const updateClientVoiceTranscript = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const transcript = sanitizeVoiceTranscript(request.data?.transcript);
  if (!transcript) {
    throw new HttpsError("invalid-argument", "Transcript is required.");
  }

  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const messageSnapshot = await messageRef.get();
  const message = messageSnapshot.data() as MessageData | undefined;
  if (!messageSnapshot.exists || !message) {
    throw new HttpsError("not-found", "Voice message was not found.");
  }
  if (
    message.kind !== "voice" ||
    message.senderId !== uid ||
    message.clientCreated !== true ||
    message.deletedAt
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Message is not an editable client voice message.",
    );
  }
  const deliveryStatus = message.deliveryStatus || "sent";
  if (deliveryStatus !== "sending" && deliveryStatus !== "sent") {
    throw new HttpsError(
      "failed-precondition",
      "Voice message cannot accept transcript updates.",
    );
  }
  const existingTranscript = voiceTranscriptFromMessage(message);
  if (!isBetterVoiceTranscriptCandidate(transcript, existingTranscript)) {
    logger.info("updateClientVoiceTranscript ignored stale transcript", {
      roomId,
      messageId,
      incomingTranscriptLength: transcript.length,
      existingTranscriptLength: existingTranscript.length,
    });
    return {
      messageId,
      sttStatus: "completed",
      transcriptLength: existingTranscript.length,
      ignoredStaleTranscript: true,
    };
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    messageRef,
    {
      text: transcript,
      transcript,
      sttStatus: "completed",
      errorCode: null,
      updatedAt: now,
    },
    { merge: true },
  );
  const roomSnapshot = await roomRef.get();
  const room = roomSnapshot.data() as RoomData | undefined;
  if (room?.lastMessage?.messageId === messageId) {
    batch.set(
      roomRef,
      {
        lastMessage: {
          messageId,
          kind: "voice",
          preview: transcript,
          senderId: uid,
          createdAt: message.createdAt || now,
        },
        updatedAt: now,
      },
      { merge: true },
    );
  }
  await batch.commit();
  logger.info("updateClientVoiceTranscript completed", {
    roomId,
    messageId,
    transcriptLength: transcript.length,
  });
  return { messageId, sttStatus: "completed" };
});

export const recoverClientVoiceMessageTranscript = onCall(
  VOICE_STT_RECOVERY_CALL_OPTIONS,
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const roomId = requiredString(request.data?.roomId, "roomId");
    const messageId = requiredString(request.data?.messageId, "messageId");

    const { roomRef } = await requireRoomParticipant(roomId, uid);
    const messageRef = roomRef.collection("messages").doc(messageId);
    const messageSnapshot = await messageRef.get();
    const message = messageSnapshot.data() as MessageData | undefined;
    if (!messageSnapshot.exists || !message) {
      throw new HttpsError("not-found", "Voice message was not found.");
    }
    if (
      message.kind !== "voice" ||
      message.clientCreated !== true ||
      message.deletedAt
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Message is not a recoverable client voice message.",
      );
    }

    const existingTranscript = voiceTranscriptFromMessage(message);
    if (existingTranscript) {
      return {
        messageId,
        sttStatus: "completed",
        transcript: existingTranscript,
        transcriptLength: existingTranscript.length,
        alreadyCompleted: true,
      };
    }

    const audioPath = optionalString(message.audioPath);
    if (!audioPath.startsWith("voice_messages/")) {
      return {
        messageId,
        sttStatus: message.sttStatus || "processing",
        transcriptLength: 0,
        recoverable: false,
      };
    }

    const startedAt = Date.now();
    await transcribePendingMessage(roomRef, messageId, message);
    const updatedSnapshot = await messageRef.get();
    const updated = updatedSnapshot.data() as MessageData | undefined;
    const transcript = voiceTranscriptFromMessage(updated);
    const sttStatus =
      updated?.sttStatus || (transcript ? "completed" : "processing");
    logger.info("recoverClientVoiceMessageTranscript completed", {
      roomId,
      messageId,
      sttStatus,
      transcriptLength: transcript.length,
      totalMs: Date.now() - startedAt,
    });
    return {
      messageId,
      sttStatus,
      transcript,
      transcriptLength: transcript.length,
      totalMs: Date.now() - startedAt,
      recoverable: true,
    };
  },
);

export const transcribeClientVoiceMessageInline = onCall(
  VOICE_STT_CALL_OPTIONS,
  async (request) => {
    const startedAt = Date.now();
    const uid = requireUid(request.auth?.uid);
    const roomId = requiredString(request.data?.roomId, "roomId");
    const messageId = requiredString(request.data?.messageId, "messageId");
    const language = optionalString(request.data?.language) || "ko";
    const contentType =
      optionalString(request.data?.contentType) || "application/octet-stream";
    const durationMs = numberValue(request.data?.durationMs, 0);
    assertVoiceDuration(durationMs);

    const base64 = requiredString(request.data?.audioBase64, "audioBase64");
    const maxInlineBytes = boundedInt(
      process.env.INLINE_STT_MAX_BYTES,
      2 * 1024 * 1024,
      256 * 1024,
      8 * 1024 * 1024,
    );
    const audioBytes = Buffer.from(base64, "base64");
    if (!audioBytes.length || audioBytes.length > maxInlineBytes) {
      throw new HttpsError(
        "invalid-argument",
        "Inline voice audio size is invalid.",
      );
    }

    const { roomRef } = await requireRoomParticipant(roomId, uid);
    const messageRef = roomRef.collection("messages").doc(messageId);
    const { message } = await waitForMessageData(
      messageRef,
      "Voice message was not found.",
    );
    if (
      message.kind !== "voice" ||
      message.senderId !== uid ||
      message.clientCreated !== true ||
      message.deletedAt
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Message is not an editable client voice message.",
      );
    }
    const deliveryStatus = message.deliveryStatus || "sent";
    if (deliveryStatus !== "sending" && deliveryStatus !== "sent") {
      throw new HttpsError(
        "failed-precondition",
        "Voice message cannot accept transcript updates.",
      );
    }

    const apiKey = normalizeSecretValue(
      process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
    );
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "DEEPGRAM_API_KEY is not configured.",
      );
    }
    const model = deepgramPrerecordedModel(language);
    const sttStartedAt = Date.now();
    const transcription = await transcribeAudioBytesCached({
      apiKey,
      audioBytes,
      language: normalizeDeepgramLanguage(language),
      model,
      contentType,
    });
    const transcript = sanitizeVoiceTranscriptForLanguage(
      transcription.transcript,
      language,
    );
    if (!transcript) {
      const latestSnapshot = await messageRef.get();
      const latestMessage = latestSnapshot.data() as MessageData | undefined;
      const latestTranscript = voiceTranscriptFromMessage(latestMessage);
      if (latestTranscript) {
        logger.info("transcribeClientVoiceMessageInline empty result ignored", {
          roomId,
          messageId,
          audioBytes: audioBytes.length,
          sttMs: Date.now() - sttStartedAt,
          totalMs: Date.now() - startedAt,
          cacheHit: transcription.cacheHit,
          existingTranscriptLength: latestTranscript.length,
        });
        return {
          messageId,
          sttStatus: "completed",
          transcript: latestTranscript,
          sttMs: Date.now() - sttStartedAt,
          totalMs: Date.now() - startedAt,
          transcriptLength: latestTranscript.length,
          cacheHit: transcription.cacheHit,
          ignoredEmptyResult: true,
        };
      }
      const now = FieldValue.serverTimestamp();
      const batch = db.batch();
      batch.set(
        messageRef,
        {
          sttStatus: "processing",
          sttCacheHit: transcription.cacheHit,
          audioHash: transcription.audioHash,
          errorCode: "inline_stt_empty_transcript",
          updatedAt: now,
        },
        { merge: true },
      );
      const roomSnapshot = await roomRef.get();
      const room = roomSnapshot.data() as RoomData | undefined;
      if (room?.lastMessage?.messageId === messageId) {
        batch.set(
          roomRef,
          {
            lastMessage: {
              messageId,
              kind: "voice",
              preview: "\uC74C\uC131 \uBCC0\uD658 \uC911...",
              senderId: uid,
              createdAt: message.createdAt || now,
            },
            updatedAt: now,
          },
          { merge: true },
        );
      }
      await batch.commit();
      logger.warn("transcribeClientVoiceMessageInline empty transcript", {
        roomId,
        messageId,
        audioBytes: audioBytes.length,
        sttMs: Date.now() - sttStartedAt,
        totalMs: Date.now() - startedAt,
        cacheHit: transcription.cacheHit,
      });
      return {
        messageId,
        sttStatus: "processing",
        sttMs: Date.now() - sttStartedAt,
        totalMs: Date.now() - startedAt,
        transcriptLength: 0,
        cacheHit: transcription.cacheHit,
        errorCode: "inline_stt_empty_transcript",
      };
    }

    const latestSnapshot = await messageRef.get();
    const latestMessage = latestSnapshot.data() as MessageData | undefined;
    const latestTranscript = voiceTranscriptFromMessage(latestMessage);
    const transcriptForWrite = preferBetterVoiceTranscript(
      transcript,
      latestTranscript,
    );
    const ignoredStaleTranscript = transcriptForWrite !== transcript;
    const now = FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(
      messageRef,
      {
        text: transcriptForWrite,
        transcript: transcriptForWrite,
        audioHash: transcription.audioHash,
        sttStatus: "completed",
        sttCacheHit: transcription.cacheHit,
        errorCode: null,
        updatedAt: now,
      },
      { merge: true },
    );
    const roomSnapshot = await roomRef.get();
    const room = roomSnapshot.data() as RoomData | undefined;
    if (room?.lastMessage?.messageId === messageId) {
      batch.set(
        roomRef,
        {
          lastMessage: {
            messageId,
            kind: "voice",
            preview: transcriptForWrite,
            senderId: uid,
            createdAt: message.createdAt || now,
          },
          updatedAt: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
    logger.info("transcribeClientVoiceMessageInline completed", {
      roomId,
      messageId,
      audioBytes: audioBytes.length,
      transcriptLength: transcriptForWrite.length,
      ignoredStaleTranscript,
      sttMs: Date.now() - sttStartedAt,
      totalMs: Date.now() - startedAt,
      cacheHit: transcription.cacheHit,
    });
    return {
      messageId,
      sttStatus: "completed",
      transcript: transcriptForWrite,
      sttMs: Date.now() - sttStartedAt,
      totalMs: Date.now() - startedAt,
      transcriptLength: transcriptForWrite.length,
      cacheHit: transcription.cacheHit,
      ignoredStaleTranscript,
    };
  },
);

export const transcribeVoiceAudioDraft = onCall(
  VOICE_STT_RECOVERY_CALL_OPTIONS,
  async (request) => {
    const startedAt = Date.now();
    const uid = requireUid(request.auth?.uid);
    const roomId = requiredString(request.data?.roomId, "roomId");
    const language = optionalString(request.data?.language) || "ko";
    const contentType =
      optionalString(request.data?.contentType) || "application/octet-stream";
    const durationMs = numberValue(request.data?.durationMs, 0);
    assertVoiceDuration(durationMs);

    const base64 = requiredString(request.data?.audioBase64, "audioBase64");
    const maxInlineBytes = boundedInt(
      process.env.INLINE_STT_MAX_BYTES,
      2 * 1024 * 1024,
      256 * 1024,
      8 * 1024 * 1024,
    );
    const audioBytes = Buffer.from(base64, "base64");
    if (!audioBytes.length || audioBytes.length > maxInlineBytes) {
      throw new HttpsError(
        "invalid-argument",
        "Inline voice audio size is invalid.",
      );
    }

    await requireRoomParticipant(roomId, uid);
    const apiKey = normalizeSecretValue(
      process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
    );
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "DEEPGRAM_API_KEY is not configured.",
      );
    }

    const model = deepgramPrerecordedModel(language);
    const sttStartedAt = Date.now();
    const transcription = await transcribeAudioBytesCached({
      apiKey,
      audioBytes,
      language: normalizeDeepgramLanguage(language),
      model,
      contentType,
    });
    const transcript = sanitizeVoiceTranscriptForLanguage(
      transcription.transcript,
      language,
    );
    const sttMs = Date.now() - sttStartedAt;
    const totalMs = Date.now() - startedAt;
    logger.info("transcribeVoiceAudioDraft completed", {
      roomId,
      uid,
      audioBytes: audioBytes.length,
      transcriptLength: transcript.length,
      sttMs,
      totalMs,
      cacheHit: transcription.cacheHit,
    });
    return {
      messageId: "draft",
      sttStatus: transcript ? "completed" : "processing",
      transcript,
      transcriptLength: transcript.length,
      sttMs,
      totalMs,
      cacheHit: transcription.cacheHit,
    };
  },
);

export const markClientVoiceMessageFailed = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const reason = optionalString(request.data?.reason).slice(0, 500);
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const messageSnapshot = await messageRef.get();
  const message = messageSnapshot.data() as MessageData | undefined;
  if (!messageSnapshot.exists || !message) {
    throw new HttpsError("not-found", "Pending voice message was not found.");
  }
  if (
    message.kind !== "voice" ||
    message.senderId !== uid ||
    message.clientCreated !== true ||
    message.deliveryStatus !== "sending"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Message is not a pending client voice message.",
    );
  }
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    messageRef,
    {
      deliveryStatus: "failed",
      sttStatus: "failed",
      errorCode: reason || "client_voice_finalize_failed",
      updatedAt: now,
    },
    { merge: true },
  );
  if (room.lastMessage?.messageId === messageId) {
    batch.set(
      roomRef,
      {
        lastMessage: {
          messageId,
          kind: "voice",
          preview: "\uC74C\uC131 \uBA54\uC2DC\uC9C0 \uC804\uC1A1 \uC2E4\uD328",
          senderId: uid,
          createdAt: message.createdAt || now,
        },
        updatedAt: now,
      },
      { merge: true },
    );
  }
  await batch.commit();
  return { messageId };
});

export const editMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const text = requiredString(request.data?.text, "text").trim();
  if (text.length === 0 || text.length > 4000) {
    throw new HttpsError("invalid-argument", "Text message length is invalid.");
  }

  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const message = await messageRef.get();
  const messageData = message.data() as MessageData | undefined;
  if (
    !message.exists ||
    !messageData ||
    messageData.senderId !== uid ||
    messageData.deletedAt
  ) {
    throw new HttpsError(
      "permission-denied",
      "Only the sender can edit this message.",
    );
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    messageRef,
    { text, editedAt: now, updatedAt: now },
    { merge: true },
  );
  if (room.lastMessage?.messageId === messageId) {
    batch.set(
      roomRef,
      {
        lastMessage: {
          messageId,
          kind: messageData.kind,
          preview: text,
          senderId: messageData.senderId,
          createdAt: messageData.createdAt || now,
        },
        updatedAt: now,
      },
      { merge: true },
    );
  }
  await batch.commit();
  return { ok: true };
});

export const deleteMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const message = await messageRef.get();
  const messageData = message.data() as MessageData | undefined;
  if (!message.exists || !messageData || messageData.senderId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the sender can delete this message.",
    );
  }
  if (messageData.audioPath) {
    await deleteStorageFile(messageData.audioPath);
  }
  if (messageData.attachment?.storagePath) {
    await deleteStorageFile(messageData.attachment.storagePath);
  }
  const now = FieldValue.serverTimestamp();
  const previousLastMessage =
    room.lastMessage?.messageId === messageId
      ? await latestVisibleMessage(roomRef, messageId)
      : null;
  const batch = db.batch();
  batch.delete(messageRef);
  batch.delete(roomRef.collection("pins").doc(messageId));
  if (room.lastMessage?.messageId === messageId) {
    if (previousLastMessage) {
      batch.set(
        roomRef,
        {
          lastMessage: {
            messageId: previousLastMessage.id,
            kind: previousLastMessage.data.kind,
            preview: messagePreview(previousLastMessage.data),
            senderId: previousLastMessage.data.senderId,
            createdAt: previousLastMessage.data.createdAt || now,
          },
          updatedAt: now,
        },
        { merge: true },
      );
    } else {
      batch.set(
        roomRef,
        {
          lastMessage: FieldValue.delete(),
          updatedAt: now,
        },
        { merge: true },
      );
    }
  }
  await batch.commit();
  return { ok: true };
});

export const reportMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  await enforceActionCooldown(uid, "report", REPORT_COOLDOWN_MS);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const reason = optionalString(request.data?.reason) || "unspecified";
  await requireRoomParticipant(roomId, uid);
  await db
    .collection("reports")
    .doc(reportDocId(uid, "message", `${roomId}_${messageId}`))
    .set(
      {
        reporterId: uid,
        targetType: "message",
        targetId: messageId,
        roomId,
        messageId,
        reason,
        details: optionalString(request.data?.details),
        status: "open",
        count: FieldValue.increment(1),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true };
});

export const reportRoom = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  await enforceActionCooldown(uid, "report", REPORT_COOLDOWN_MS);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const reason = optionalString(request.data?.reason) || "unspecified";
  await requireRoomParticipant(roomId, uid);
  await db
    .collection("reports")
    .doc(reportDocId(uid, "room", roomId))
    .set(
      {
        reporterId: uid,
        targetType: "room",
        targetId: roomId,
        roomId,
        reason,
        details: optionalString(request.data?.details),
        status: "open",
        count: FieldValue.increment(1),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true };
});

export const blockUser = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  await enforceActionCooldown(uid, "blockUser", BLOCK_COOLDOWN_MS);
  const blockedUid = requiredString(request.data?.blockedUid, "blockedUid");
  if (blockedUid === uid) {
    throw new HttpsError("invalid-argument", "You cannot block yourself.");
  }
  await db
    .collection("blocks")
    .doc(uid)
    .collection("users")
    .doc(blockedUid)
    .set(
      {
        blockedAt: FieldValue.serverTimestamp(),
        reason: optionalString(request.data?.reason),
      },
      { merge: true },
    );
  return { ok: true };
});

export const leaveRoom = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const nextParticipantIds = room.participantIds.filter((id) => id !== uid);
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  const roomUpdate: Record<string, unknown> = {
    participantIds: nextParticipantIds,
    updatedAt: now,
  };
  if (room.ownerId === uid) {
    roomUpdate.ownerId = nextParticipantIds[0] || null;
    if (nextParticipantIds[0]) {
      batch.set(
        roomRef.collection("members").doc(nextParticipantIds[0]),
        {
          role: "owner",
          updatedAt: now,
        },
        { merge: true },
      );
    }
  }
  batch.set(roomRef, roomUpdate, { merge: true });
  batch.set(
    roomRef.collection("members").doc(uid),
    {
      leftAt: now,
      archived: true,
      pinned: false,
      unreadCount: 0,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
  return { ok: true };
});

export const addReaction = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const emoji = emojiValue(request.data?.emoji);
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(messageRef);
    const message = snapshot.data() as MessageData | undefined;
    if (!snapshot.exists || !message || message.deletedAt) {
      throw new HttpsError("not-found", "Message was not found.");
    }
    const reactions = reactionMap(message.reactions);
    const users = new Set(reactions[emoji] || []);
    users.add(uid);
    reactions[emoji] = [...users];
    transaction.set(
      messageRef,
      {
        reactions,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return { ok: true };
});

export const removeReaction = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const emoji = emojiValue(request.data?.emoji);
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(messageRef);
    const message = snapshot.data() as MessageData | undefined;
    if (!snapshot.exists || !message) {
      throw new HttpsError("not-found", "Message was not found.");
    }
    const reactions = reactionMap(message.reactions);
    reactions[emoji] = (reactions[emoji] || []).filter((id) => id !== uid);
    if (reactions[emoji].length === 0) {
      delete reactions[emoji];
    }
    transaction.set(
      messageRef,
      {
        reactions,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return { ok: true };
});

export const translateMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const targetLanguage = normalizeTargetLanguage(
    optionalString(request.data?.targetLanguage) || "en",
  );
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const snapshot = await messageRef.get();
  const message = snapshot.data() as MessageData | undefined;
  if (!snapshot.exists || !message || message.deletedAt) {
    throw new HttpsError("not-found", "Message was not found.");
  }
  const source = messagePreview(message);
  if (!source.trim()) {
    throw new HttpsError(
      "failed-precondition",
      "Message has no translatable text.",
    );
  }
  const text = await translateText(source, targetLanguage);
  await messageRef.set(
    {
      [`translations.${targetLanguage}`]: {
        text,
        createdAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return {
    targetLanguage,
    text,
    createdAt: new Date().toISOString(),
  };
});

export const pinMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  const message = await messageRef.get();
  const messageData = message.data() as MessageData | undefined;
  if (!message.exists || !messageData || messageData.deletedAt) {
    throw new HttpsError("not-found", "Message was not found.");
  }
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    messageRef,
    {
      pinnedAt: now,
      pinnedBy: uid,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(roomRef.collection("pins").doc(messageId), {
    messageId,
    pinnedBy: uid,
    preview: messagePreview(messageData),
    createdAt: now,
  });
  await batch.commit();
  return { ok: true };
});

export const unpinMessage = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const messageId = requiredString(request.data?.messageId, "messageId");
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  const messageRef = roomRef.collection("messages").doc(messageId);
  await messageRef.set(
    {
      pinnedAt: FieldValue.delete(),
      pinnedBy: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await roomRef.collection("pins").doc(messageId).delete();
  return { ok: true };
});

export const markRoomRead = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const roomId = requiredString(request.data?.roomId, "roomId");
  const lastMessageId = optionalString(request.data?.lastMessageId) || null;
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  await roomRef.collection("members").doc(uid).set(
    {
      lastReadAt: FieldValue.serverTimestamp(),
      lastReadMessageId: lastMessageId,
      unreadCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

export const setRoomPinned = onCall(async (request) => {
  return updateMemberRoomFlag(
    request.auth?.uid,
    request.data?.roomId,
    "pinned",
    request.data?.pinned,
  );
});

export const setRoomArchived = onCall(async (request) => {
  return updateMemberRoomFlag(
    request.auth?.uid,
    request.data?.roomId,
    "archived",
    request.data?.archived,
  );
});

export const setRoomMuted = onCall(async (request) => {
  return updateMemberRoomFlag(
    request.auth?.uid,
    request.data?.roomId,
    "muted",
    request.data?.muted,
  );
});

export const onMessageCreated = onDocumentCreated(
  {
    document: "rooms/{roomId}/messages/{messageId}",
    secrets: [deepgramApiKey],
  },
  async (event) => {
    const message = event.data?.data() as MessageData | undefined;
    if (!message) {
      return;
    }
    if (message.deliveryStatus === "scheduled") {
      return;
    }

    const roomId = event.params.roomId;
    const messageId = event.params.messageId;
    const roomRef = db.collection("rooms").doc(roomId);
    const room = await roomRef.get();
    const roomData = room.data() as RoomData | undefined;
    if (!roomData) {
      return;
    }

    if (
      message.kind === "voice" &&
      message.sttStatus === "processing" &&
      message.audioPath
    ) {
      await transcribePendingMessage(roomRef, messageId, message);
    }

    if (message.clientCreated === true) {
      await syncClientCreatedMessage(roomRef, roomData, messageId, message);
    }

    await sendPushForMessage(roomId, messageId, roomData, message);
  },
);

export const onMessageUpdated = onDocumentUpdated(
  {
    document: "rooms/{roomId}/messages/{messageId}",
    secrets: [deepgramApiKey],
    timeoutSeconds: 180,
    memory: "512MiB",
  },
  async (event) => {
    const before = event.data?.before.data() as MessageData | undefined;
    const after = event.data?.after.data() as MessageData | undefined;
    if (!after || after.kind !== "voice" || after.deletedAt) {
      return;
    }
    if (after.sttStatus !== "processing" || voiceTranscriptFromMessage(after)) {
      return;
    }
    const audioPath = optionalString(after.audioPath);
    if (!audioPath.startsWith("voice_messages/")) {
      return;
    }
    const previousAudioPath = optionalString(before?.audioPath);
    const previousStatus = before?.sttStatus;
    if (previousAudioPath === audioPath && previousStatus === "processing") {
      return;
    }

    const roomRef = db.collection("rooms").doc(event.params.roomId);
    await transcribePendingMessage(roomRef, event.params.messageId, after);
  },
);

export const deliverScheduledMessages = onSchedule(
  "every 1 minutes",
  async () => {
    const dueMessages = await db
      .collectionGroup("messages")
      .where("deliveryStatus", "==", "scheduled")
      .where("scheduledAt", "<=", admin.firestore.Timestamp.now())
      .limit(50)
      .get();

    for (const doc of dueMessages.docs) {
      const roomRef = doc.ref.parent.parent;
      if (!roomRef) {
        continue;
      }
      const roomSnapshot = await roomRef.get();
      const room = roomSnapshot.data() as RoomData | undefined;
      const message = doc.data() as MessageData | undefined;
      if (
        !room ||
        !message ||
        message.deliveryStatus !== "scheduled" ||
        message.deletedAt
      ) {
        continue;
      }
      await deliverScheduledMessage(roomRef, room, doc.id, message);
    }
  },
);

export const deliverCalendarReminders = onSchedule(
  "every 5 minutes",
  async () => {
    const now = new Date();
    const nowMs = now.getTime();
    const dueWindowStart = new Date(nowMs - 10 * 60 * 1000);
    const lookupEnd = new Date(nowMs + 24 * 60 * 60 * 1000);
    const eventsSnapshot = await db
      .collectionGroup("calendarEvents")
      .where("status", "==", "active")
      .where(
        "startAt",
        ">=",
        admin.firestore.Timestamp.fromDate(dueWindowStart),
      )
      .where("startAt", "<=", admin.firestore.Timestamp.fromDate(lookupEnd))
      .orderBy("startAt", "asc")
      .limit(200)
      .get();

    for (const doc of eventsSnapshot.docs) {
      const event = doc.data() as CalendarEventData | undefined;
      const startAt = timestampToDate(event?.startAt);
      const uid = optionalString(event?.ownerId) || doc.ref.parent.parent?.id;
      if (!event || !startAt || !uid) {
        continue;
      }

      const userRef = db.collection("users").doc(uid);
      const userSnapshot = await userRef.get();
      const userData = userSnapshot.data();
      if (!userData || userData.calendarReminderEnabled === false) {
        continue;
      }

      const leadMinutes = boundedInt(
        userData.calendarReminderLeadMinutes,
        30,
        0,
        1440,
      );
      const reminderAtMs = startAt.getTime() - leadMinutes * 60 * 1000;
      if (reminderAtMs > nowMs || reminderAtMs <= dueWindowStart.getTime()) {
        continue;
      }

      const deliveryRef = userRef
        .collection("calendarNotificationDeliveries")
        .doc(`reminder_${safeId(doc.id)}_${startAt.getTime()}_${leadMinutes}`);
      const shouldSend = await createNotificationDelivery(deliveryRef, {
        type: "calendarReminder",
        eventId: doc.id,
        startAt: admin.firestore.Timestamp.fromDate(startAt),
        leadMinutes,
      });
      if (!shouldSend) {
        continue;
      }

      const timezone = safeCalendarTimezone(userData.calendarTimezone);
      const title = optionalString(event.title) || "\uC77C\uC815";
      await sendPushToUser(
        uid,
        "\uC77C\uC815 \uC54C\uB9BC",
        `${title} \u00B7 ${formatCalendarPushTime(startAt, timezone)} \uC2DC\uC791`,
        {
          type: "calendarReminder",
          eventId: doc.id,
          startAt: startAt.toISOString(),
        },
      );
    }
  },
);

export const deliverMorningBriefings = onSchedule(
  "every 15 minutes",
  async () => {
    const now = new Date();
    const kstParts = timeZoneParts(now, "Asia/Seoul");
    const kstMinuteOfDay = kstParts.hour * 60 + kstParts.minute;
    const briefingWindowStart = Math.max(0, kstMinuteOfDay - 14);
    const usersSnapshot = await db
      .collection("users")
      .where("morningBriefingEnabled", "==", true)
      .where("morningBriefingMinuteOfDay", ">=", briefingWindowStart)
      .where("morningBriefingMinuteOfDay", "<=", kstMinuteOfDay)
      .limit(500)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const timezone = safeCalendarTimezone(userData.calendarTimezone);
      const localParts = timeZoneParts(now, timezone);
      const localMinuteOfDay = localParts.hour * 60 + localParts.minute;
      const briefingMinuteOfDay = boundedInt(
        userData.morningBriefingMinuteOfDay,
        480,
        0,
        1439,
      );
      if (
        localMinuteOfDay < briefingMinuteOfDay ||
        localMinuteOfDay >= briefingMinuteOfDay + 15
      ) {
        continue;
      }

      const dateKey = timeZoneDateKey(now, timezone);
      const range = localDayUtcRange(now, timezone);
      const eventSnapshot = await userDoc.ref
        .collection("calendarEvents")
        .where("status", "==", "active")
        .where("startAt", ">=", admin.firestore.Timestamp.fromDate(range.start))
        .where("startAt", "<", admin.firestore.Timestamp.fromDate(range.end))
        .orderBy("startAt", "asc")
        .limit(30)
        .get();
      const events = eventSnapshot.docs
        .map((eventDoc) => {
          const event = eventDoc.data() as CalendarEventData;
          return {
            id: eventDoc.id,
            title: optionalString(event.title) || "\uC77C\uC815",
            startAt: timestampToDate(event.startAt),
          };
        })
        .filter(
          (event): event is { id: string; title: string; startAt: Date } =>
            event.startAt != null,
        );
      const briefingText = calendarMorningBriefingText(events, timezone, now);

      const deliveryRef = userDoc.ref
        .collection("calendarNotificationDeliveries")
        .doc(`morning_${dateKey}_${briefingMinuteOfDay}`);
      const shouldSend = await createNotificationDelivery(deliveryRef, {
        type: "calendarMorningBriefing",
        dateKey,
        eventCount: events.length,
      });
      if (!shouldSend) {
        continue;
      }

      await sendPushToUser(
        userDoc.id,
        "\uC624\uB298\uC758 \uC77C\uC815 \uBE0C\uB9AC\uD551",
        truncateNotificationBody(briefingText),
        {
          type: "calendarMorningBriefing",
          dateKey,
          eventCount: `${events.length}`,
          briefingText: truncateDataPayload(briefingText),
        },
      );
    }
  },
);

export const expireVoiceAudio = onSchedule("every 1 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const expiredMessages = await db
    .collectionGroup("messages")
    .where("audioRetentionStatus", "==", "active")
    .where("audioExpiresAt", "<=", now)
    .limit(100)
    .get();

  for (const doc of expiredMessages.docs) {
    const message = doc.data() as MessageData | undefined;
    const audioPath = message?.audioPath;
    if (!audioPath) {
      await doc.ref.set(
        {
          audioRetentionStatus: "deleted",
          audioDeletedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      continue;
    }
    await deleteStorageFile(audioPath);
    await doc.ref.set(
      {
        audioPath: null,
        audioDeletedAt: FieldValue.serverTimestamp(),
        audioRetentionStatus: "deleted",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  const expiredDrafts = await db
    .collection("transcriptionDrafts")
    .where("audioRetentionStatus", "==", "active")
    .where("audioExpiresAt", "<=", now)
    .limit(100)
    .get();
  for (const doc of expiredDrafts.docs) {
    const audioPath = doc.data().audioPath;
    if (typeof audioPath === "string" && audioPath) {
      await deleteStorageFile(audioPath);
    }
    await doc.ref.set(
      {
        audioDeletedAt: FieldValue.serverTimestamp(),
        audioRetentionStatus: "deleted",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
});

export const rollupUsageAndCost = onSchedule("every 1 hours", async () => {
  await writeUsageRollup(kstDateKey());
  await writeUsageRollup(
    kstDateKey(new Date(Date.now() - 24 * 60 * 60 * 1000)),
  );
});

export const recoverStaleVoiceMessages = onSchedule(
  {
    schedule: "every 5 minutes",
    secrets: [deepgramApiKey],
  },
  async () => {
    const staleBefore = Date.now() - STALE_PENDING_VOICE_MS;
    const roomsSnapshot = await db
      .collection("rooms")
      .orderBy("updatedAt", "desc")
      .limit(100)
      .get();
    let inspected = 0;
    let recovered = 0;
    let failed = 0;

    for (const roomDoc of roomsSnapshot.docs) {
      const sendingSnapshot = await roomDoc.ref
        .collection("messages")
        .where("deliveryStatus", "==", "sending")
        .limit(25)
        .get();
      const processingSnapshot = await roomDoc.ref
        .collection("messages")
        .where("sttStatus", "==", "processing")
        .limit(25)
        .get();
      const failedSnapshot = await roomDoc.ref
        .collection("messages")
        .where("sttStatus", "==", "failed")
        .limit(100)
        .get();
      const recentSnapshot = await roomDoc.ref
        .collection("messages")
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();
      const messageDocs = new Map<
        string,
        admin.firestore.QueryDocumentSnapshot
      >();
      for (const doc of recentSnapshot.docs) {
        messageDocs.set(doc.id, doc);
      }
      for (const doc of sendingSnapshot.docs) {
        if (!messageDocs.has(doc.id)) {
          messageDocs.set(doc.id, doc);
        }
      }
      for (const doc of processingSnapshot.docs) {
        if (!messageDocs.has(doc.id)) {
          messageDocs.set(doc.id, doc);
        }
      }
      for (const doc of failedSnapshot.docs) {
        if (!messageDocs.has(doc.id)) {
          messageDocs.set(doc.id, doc);
        }
      }
      for (const messageDoc of messageDocs.values()) {
        if (inspected >= 20) {
          break;
        }
        const message = messageDoc.data() as MessageData | undefined;
        if (!message || message.kind !== "voice") {
          continue;
        }
        const deliveryStatus = message.deliveryStatus || "sent";
        const audioPath = optionalString(message.audioPath);
        const hasRecoverableAudioPath = audioPath.startsWith("voice_messages/");
        const hasVoiceTranscript = !!voiceTranscriptFromMessage(message);
        const needsDeliveryRecovery = deliveryStatus === "sending";
        const needsSttRecovery =
          message.sttStatus === "processing" && !hasVoiceTranscript;
        const retryCount = numberValue(message.sttRetryCount, 0);
        const needsFailedSttRecovery =
          message.sttStatus === "failed" &&
          !hasVoiceTranscript &&
          retryCount < STT_FAILED_RECOVERY_MAX_ATTEMPTS &&
          isRetryableSttFailure(optionalString(message.errorCode));
        const needsBlankDeliveredRecovery =
          deliveryStatus === "sent" &&
          hasRecoverableAudioPath &&
          !hasVoiceTranscript &&
          (message.sttStatus === "completed" ||
            message.sttStatus === "none" ||
            !message.sttStatus);
        if (
          !needsDeliveryRecovery &&
          !needsSttRecovery &&
          !needsFailedSttRecovery &&
          !needsBlankDeliveredRecovery
        ) {
          continue;
        }
        const referenceTime =
          timestampToDate(message.updatedAt) ||
          timestampToDate(message.createdAt);
        if (referenceTime && referenceTime.getTime() > staleBefore) {
          continue;
        }
        inspected += 1;
        if (hasRecoverableAudioPath) {
          await transcribePendingMessage(roomDoc.ref, messageDoc.id, message);
          recovered += 1;
          continue;
        }
        await failPendingVoiceMessage(
          roomDoc.ref,
          messageDoc.id,
          message,
          audioPath ? "stale_invalid_audio_path" : "stale_missing_audio_path",
        );
        failed += 1;
      }
    }

    logger.info("recoverStaleVoiceMessages completed", {
      inspected,
      recovered,
      failed,
    });
  },
);

async function transcribePendingMessage(
  roomRef: admin.firestore.DocumentReference,
  messageId: string,
  message: MessageData,
) {
  try {
    const messageRef = roomRef.collection("messages").doc(messageId);
    const latestSnapshot = await messageRef.get();
    const latestMessage = latestSnapshot.data() as MessageData | undefined;
    if (!latestMessage || latestMessage.kind !== "voice") {
      return;
    }
    const latestTranscript = voiceTranscriptFromMessage(latestMessage);
    if (latestTranscript) {
      return;
    }
    const latestAudioPath = optionalString(latestMessage.audioPath);
    if (!latestAudioPath.startsWith("voice_messages/")) {
      return;
    }
    message = latestMessage;
    const language = message.language || "ko";
    const transcription = await transcribeStorageAudio(
      latestAudioPath,
      language,
    );
    const transcript = sanitizeVoiceTranscriptForLanguage(
      transcription.transcript,
      language,
    );
    const beforeWriteSnapshot = await messageRef.get();
    const beforeWriteMessage = beforeWriteSnapshot.data() as
      | MessageData
      | undefined;
    const beforeWriteTranscript =
      voiceTranscriptFromMessage(beforeWriteMessage);
    if (!transcript && beforeWriteTranscript) {
      return;
    }
    const previousRetryCount = numberValue(
      beforeWriteMessage?.sttRetryCount,
      0,
    );
    const selectedTranscript = preferBetterVoiceTranscript(
      transcript,
      beforeWriteTranscript,
    );
    const hasTranscript = !!selectedTranscript;
    const nextRetryCount = hasTranscript ? 0 : previousRetryCount + 1;
    const keepProcessing =
      !hasTranscript && nextRetryCount <= DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_COUNT;
    await messageRef.set(
      {
        text: selectedTranscript,
        transcript: selectedTranscript,
        audioHash: transcription.audioHash,
        sttCacheHit: transcription.cacheHit,
        sttStatus: hasTranscript
          ? "completed"
          : keepProcessing
            ? "processing"
            : "failed",
        errorCode: hasTranscript ? null : "stt_empty_transcript",
        sttRetryCount: hasTranscript
          ? FieldValue.delete()
          : FieldValue.increment(1),
        lastSttRetryAt: hasTranscript
          ? FieldValue.delete()
          : FieldValue.serverTimestamp(),
        deliveryStatus: "sent",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await roomRef.set(
      {
        lastMessage: {
          messageId,
          kind: "voice",
          preview:
            selectedTranscript ||
            (keepProcessing ? "\uC74C\uC131 \uBCC0\uD658 \uC911..." : "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328"),
          senderId: message.senderId,
          createdAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    logger.error("transcribePendingMessage failed", { messageId, error });
    const code = errorCode(error);
    const transient = isTransientSttError(code);
    await roomRef
      .collection("messages")
      .doc(messageId)
      .set(
        {
          sttStatus: transient ? "processing" : "failed",
          errorCode: code,
          sttRetryCount: FieldValue.increment(1),
          lastSttRetryAt: FieldValue.serverTimestamp(),
          deliveryStatus: "sent",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }
}

async function failPendingVoiceMessage(
  roomRef: admin.firestore.DocumentReference,
  messageId: string,
  message: MessageData,
  code: string,
) {
  const now = FieldValue.serverTimestamp();
  const roomSnapshot = await roomRef.get();
  const room = roomSnapshot.data() as RoomData | undefined;
  const shouldUpdateLastMessage =
    room?.lastMessage?.messageId === messageId || !room?.lastMessage?.messageId;
  const batch = db.batch();
  batch.set(
    roomRef.collection("messages").doc(messageId),
    {
      sttStatus: "failed",
      errorCode: code,
      deliveryStatus: "failed",
      updatedAt: now,
    },
    { merge: true },
  );
  if (shouldUpdateLastMessage) {
    batch.set(
      roomRef,
      {
        lastMessage: {
          messageId,
          kind: "voice",
          preview: "\uC74C\uC131 \uBA54\uC2DC\uC9C0 \uC804\uC1A1 \uC2E4\uD328",
          senderId: message.senderId,
          createdAt: message.createdAt || now,
        },
        updatedAt: now,
      },
      { merge: true },
    );
  }
  await batch.commit();
}

async function sendPushForMessage(
  roomId: string,
  messageId: string,
  room: RoomData,
  message: MessageData,
) {
  const recipientIds = room.participantIds.filter(
    (id) => id !== message.senderId,
  );
  const body = messagePreview(message);
  const activeTokens: Array<{
    token: string;
    ref: admin.firestore.DocumentReference;
  }> = [];
  for (const recipientId of recipientIds) {
    const member = await db
      .collection("rooms")
      .doc(roomId)
      .collection("members")
      .doc(recipientId)
      .get();
    const memberData = member.data();
    if (memberData?.muted === true || memberData?.leftAt) {
      continue;
    }
    const tokenSnapshot = await db
      .collection("users")
      .doc(recipientId)
      .collection("fcmTokens")
      .get();
    for (const tokenDoc of tokenSnapshot.docs) {
      const token = tokenDoc.data().token;
      if (typeof token === "string" && token.trim()) {
        activeTokens.push({ token, ref: tokenDoc.ref });
      }
    }
  }
  if (activeTokens.length === 0) {
    return;
  }
  for (let index = 0; index < activeTokens.length; index += 500) {
    const batch = activeTokens.slice(index, index + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: batch.map((item) => item.token),
      notification: {
        title: room.title || "Verbal",
        body,
      },
      data: {
        roomId,
        messageId,
        kind: message.kind,
      },
    });

    const staleRefs: admin.firestore.DocumentReference[] = [];
    response.responses.forEach((sendResponse, responseIndex) => {
      const code = sendResponse.error?.code || "";
      if (isInvalidFcmTokenCode(code)) {
        staleRefs.push(batch[responseIndex].ref);
      }
    });
    if (staleRefs.length > 0) {
      await Promise.all(staleRefs.map((ref) => ref.delete()));
    }
    if (response.failureCount > 0) {
      logger.warn("Some FCM sends failed", {
        roomId,
        messageId,
        failureCount: response.failureCount,
        staleTokenCount: staleRefs.length,
      });
    }
  }
}

async function sendPushToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const tokenSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("fcmTokens")
    .get();
  const activeTokens: Array<{
    token: string;
    ref: admin.firestore.DocumentReference;
  }> = [];
  for (const tokenDoc of tokenSnapshot.docs) {
    const token = tokenDoc.data().token;
    if (typeof token === "string" && token.trim()) {
      activeTokens.push({ token, ref: tokenDoc.ref });
    }
  }
  if (activeTokens.length === 0) {
    return;
  }
  for (let index = 0; index < activeTokens.length; index += 500) {
    const batch = activeTokens.slice(index, index + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: batch.map((item) => item.token),
      notification: { title, body },
      data,
    });
    const staleRefs: admin.firestore.DocumentReference[] = [];
    response.responses.forEach((sendResponse, responseIndex) => {
      const code = sendResponse.error?.code || "";
      if (isInvalidFcmTokenCode(code)) {
        staleRefs.push(batch[responseIndex].ref);
      }
    });
    if (staleRefs.length > 0) {
      await Promise.all(staleRefs.map((ref) => ref.delete()));
    }
    if (response.failureCount > 0) {
      logger.warn("Some calendar FCM sends failed", {
        uid,
        failureCount: response.failureCount,
        staleTokenCount: staleRefs.length,
      });
    }
  }
}

function isInvalidFcmTokenCode(code: string) {
  return (
    code === "messaging/invalid-registration-token" ||
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-argument"
  );
}

async function createMessage(
  roomRef: admin.firestore.DocumentReference,
  room: RoomData,
  messageId: string,
  message: MessageData,
  preview: string,
) {
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(roomRef.collection("messages").doc(messageId), {
    ...message,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(
    roomRef,
    {
      lastMessage: {
        messageId,
        kind: message.kind,
        preview,
        senderId: message.senderId,
        createdAt: now,
      },
      updatedAt: now,
    },
    { merge: true },
  );
  for (const participantId of room.participantIds) {
    batch.set(
      roomRef.collection("members").doc(participantId),
      participantId === message.senderId
        ? {
            lastReadAt: now,
            lastReadMessageId: messageId,
            unreadCount: 0,
            updatedAt: now,
          }
        : {
            unreadCount: FieldValue.increment(1),
            updatedAt: now,
          },
      { merge: true },
    );
  }
  await batch.commit();
}

async function syncClientCreatedMessage(
  roomRef: admin.firestore.DocumentReference,
  room: RoomData,
  messageId: string,
  message: MessageData,
) {
  const latestMessageSnapshot = await roomRef
    .collection("messages")
    .doc(messageId)
    .get();
  const latestMessage =
    (latestMessageSnapshot.data() as MessageData | undefined) || message;
  if (
    (latestMessage.kind !== "text" && latestMessage.kind !== "voice") ||
    latestMessage.deletedAt
  ) {
    return;
  }
  const now = FieldValue.serverTimestamp();
  const preview = messagePreview(latestMessage);
  const batch = db.batch();
  batch.set(
    roomRef,
    {
      lastMessage: {
        messageId,
        kind: latestMessage.kind,
        preview,
        senderId: latestMessage.senderId,
        createdAt: latestMessage.createdAt || message.createdAt || now,
      },
      updatedAt: now,
    },
    { merge: true },
  );
  for (const participantId of room.participantIds) {
    batch.set(
      roomRef.collection("members").doc(participantId),
      participantId === latestMessage.senderId
        ? {
            lastReadAt: now,
            lastReadMessageId: messageId,
            unreadCount: 0,
            updatedAt: now,
          }
        : {
            unreadCount: FieldValue.increment(1),
            updatedAt: now,
          },
      { merge: true },
    );
  }
  await batch.commit();
  if (latestMessage.kind === "text") {
    await recordDailyUsage(latestMessage.senderId, { textCount: 1 });
  }
}

async function deliverScheduledMessage(
  roomRef: admin.firestore.DocumentReference,
  room: RoomData,
  messageId: string,
  message: MessageData,
) {
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(
    roomRef.collection("messages").doc(messageId),
    {
      deliveryStatus: "sent",
      deliveredAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    roomRef,
    {
      lastMessage: {
        messageId,
        kind: message.kind,
        preview: messagePreview(message),
        senderId: message.senderId,
        createdAt: now,
      },
      updatedAt: now,
    },
    { merge: true },
  );
  for (const participantId of room.participantIds) {
    batch.set(
      roomRef.collection("members").doc(participantId),
      participantId === message.senderId
        ? {
            lastReadAt: now,
            lastReadMessageId: messageId,
            unreadCount: 0,
            updatedAt: now,
          }
        : { unreadCount: FieldValue.increment(1), updatedAt: now },
      { merge: true },
    );
  }
  await batch.commit();
  await sendPushForMessage(roomRef.id, messageId, room, {
    ...message,
    deliveryStatus: "sent",
  });
}

async function requireRoomParticipant(roomId: string, uid: string) {
  const roomRef = db.collection("rooms").doc(roomId);
  const room = await roomRef.get();
  const data = room.data() as RoomData | undefined;
  if (
    !data ||
    !Array.isArray(data.participantIds) ||
    !data.participantIds.includes(uid)
  ) {
    throw new HttpsError("permission-denied", "Room access denied.");
  }
  const member = await roomRef.collection("members").doc(uid).get();
  if (member.data()?.leftAt) {
    throw new HttpsError("permission-denied", "Room access denied.");
  }
  return { roomRef, room: data };
}

async function requireRoomManager(roomId: string, uid: string) {
  const { roomRef, room } = await requireRoomParticipant(roomId, uid);
  const member = await roomRef.collection("members").doc(uid).get();
  const role = roomMemberRole(member.data()?.role);
  if (role !== "owner" && role !== "admin") {
    throw new HttpsError("permission-denied", "Admin permission is required.");
  }
  return { roomRef, room, memberRole: role };
}

async function updateMemberRoomFlag(
  uidValue: string | undefined,
  roomIdValue: unknown,
  field: "pinned" | "archived" | "muted",
  value: unknown,
) {
  const uid = requireUid(uidValue);
  const roomId = requiredString(roomIdValue, "roomId");
  const flag = booleanValue(value, field);
  const { roomRef } = await requireRoomParticipant(roomId, uid);
  await roomRef
    .collection("members")
    .doc(uid)
    .set(
      {
        [field]: flag,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true };
}

async function storageBucketStatus() {
  try {
    const exists = await storageBucketExists();
    return {
      ok: exists,
      name: bucket.name,
      exists,
    };
  } catch (error) {
    logger.warn("Storage health check failed", {
      error: errorDetails(error),
    });
    return {
      ok: false,
      name: bucket.name,
      exists: false,
      errorCode: errorCode(error),
      errorMessage: errorDetails(error).message,
    };
  }
}

async function recordDailyUsage(
  uid: string,
  increments: { textCount?: number; voiceCount?: number; voiceMs?: number },
) {
  const usageRef = db.collection("usageDaily").doc(dailyUsageDocId(uid));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(usageRef);
    transaction.set(
      usageRef,
      {
        uid,
        date: kstDateKey(),
        timezone: "Asia/Seoul",
        limitMode: "unlimited",
        textLimit: null,
        voiceLimit: null,
        textCount: FieldValue.increment(increments.textCount || 0),
        voiceCount: FieldValue.increment(increments.voiceCount || 0),
        voiceMs: FieldValue.increment(increments.voiceMs || 0),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: snapshot.exists
          ? snapshot.data()?.createdAt || FieldValue.serverTimestamp()
          : FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

async function writeUsageRollup(dateKey: string) {
  const snapshot = await db
    .collection("usageDaily")
    .where("date", "==", dateKey)
    .limit(10000)
    .get();
  let textCount = 0;
  let voiceCount = 0;
  let voiceMs = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    textCount += numericValue(data.textCount);
    voiceCount += numericValue(data.voiceCount);
    voiceMs += numericValue(data.voiceMs);
  }
  const voiceMinutes = voiceMs / 60_000;
  const sttCostLowUsd = roundCurrency(
    voiceMinutes * DEEPGRAM_COST_LOW_PER_MINUTE_USD,
  );
  const sttCostHighUsd = roundCurrency(
    voiceMinutes * DEEPGRAM_COST_HIGH_PER_MINUTE_USD,
  );
  await db
    .collection("usageRollups")
    .doc(dateKey)
    .set(
      {
        date: dateKey,
        timezone: "Asia/Seoul",
        limitMode: "unlimited",
        textLimit: null,
        voiceLimit: null,
        userCount: snapshot.size,
        textCount,
        voiceCount,
        voiceMs,
        voiceMinutes: roundMetric(voiceMinutes),
        estimatedDeepgramCostUsd: {
          low: sttCostLowUsd,
          high: sttCostHighUsd,
          lowPerMinute: DEEPGRAM_COST_LOW_PER_MINUTE_USD,
          highPerMinute: DEEPGRAM_COST_HIGH_PER_MINUTE_USD,
        },
        truncated: snapshot.size >= 10000,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

function dailyUsageDocId(uid: string) {
  return `${uid}_${kstDateKey()}`;
}

function kstDateKey(date = new Date()) {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  return kst.toISOString().slice(0, 10);
}

function calendarNotificationSettingsPayload(
  data: Record<string, unknown>,
): CalendarNotificationSettings {
  return {
    calendarReminderEnabled: data.calendarReminderEnabled !== false,
    calendarReminderLeadMinutes: boundedInt(
      data.calendarReminderLeadMinutes,
      30,
      0,
      1440,
    ),
    morningBriefingEnabled: data.morningBriefingEnabled === true,
    morningBriefingMinuteOfDay: boundedInt(
      data.morningBriefingMinuteOfDay,
      480,
      0,
      1439,
    ),
    calendarTimezone: calendarTimezoneValue(data.calendarTimezone),
    holidayCountryCode: holidayCountryCodeValue(data.holidayCountryCode),
  };
}

function calendarProposalTitle(value: unknown) {
  const title = requiredString(value, "title").trim();
  if (title.length < 1 || title.length > 120) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar proposal title must be 1-120 characters.",
    );
  }
  return title;
}

function calendarProposalDetails(value: unknown) {
  const details = optionalString(value).trim();
  if (details.length > 2000) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar proposal details must be 2000 characters or fewer.",
    );
  }
  return details;
}

function calendarProposalCandidates(
  value: unknown,
): CalendarProposalCandidateData[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 5) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar proposal candidates must contain 1-5 items.",
    );
  }
  const seen = new Set<string>();
  return value.map((item, index) => {
    if (!item || typeof item !== "object") {
      throw new HttpsError("invalid-argument", "Candidate is invalid.");
    }
    const input = item as Record<string, unknown>;
    const candidateId =
      optionalString(input.candidateId) ||
      optionalString(input.id) ||
      `candidate_${index + 1}`;
    if (candidateId.length > 80 || seen.has(candidateId)) {
      throw new HttpsError("invalid-argument", "Candidate id is invalid.");
    }
    seen.add(candidateId);
    const startAt = dateValue(input.startAt, "candidate.startAt");
    const endAt = dateValue(input.endAt, "candidate.endAt");
    if (startAt.getTime() <= Date.now() + 30_000) {
      throw new HttpsError(
        "invalid-argument",
        "Candidate start time must be in the future.",
      );
    }
    if (endAt.getTime() <= startAt.getTime()) {
      throw new HttpsError(
        "invalid-argument",
        "Candidate end time must be after start time.",
      );
    }
    return {
      candidateId,
      startAt: admin.firestore.Timestamp.fromDate(startAt),
      endAt: admin.firestore.Timestamp.fromDate(endAt),
    };
  });
}

function calendarProposalVotes(value: unknown) {
  const votes: Record<string, string[]> = {};
  if (!value || typeof value !== "object") {
    return votes;
  }
  for (const [uid, selected] of Object.entries(
    value as Record<string, unknown>,
  )) {
    votes[uid] = stringArray(selected);
  }
  return votes;
}

function proposalSnapshot(
  snapshot: admin.firestore.DocumentSnapshot,
  roomId: string,
  proposalId: string,
): CalendarProposalData {
  const proposal = snapshot.data() as CalendarProposalData | undefined;
  if (!snapshot.exists || !proposal || proposal.roomId !== roomId) {
    throw new HttpsError("not-found", "Calendar proposal was not found.");
  }
  return {
    ...proposal,
    roomId,
    votes: calendarProposalVotes(proposal.votes),
    candidates: proposal.candidates || [],
    finalCandidateId: proposal.finalCandidateId || null,
  };
}

function calendarProposalPreview(title: string) {
  return `\uC77C\uC815 \uC81C\uC548: ${title}`.slice(0, 120);
}

function calendarEventFromProposal(
  ownerId: string,
  roomId: string,
  proposalId: string,
  proposal: CalendarProposalData,
  candidate: CalendarProposalCandidateData,
): CalendarEventData {
  return {
    ownerId,
    title: proposal.title,
    startAt: candidate.startAt,
    endAt: candidate.endAt,
    timezone: proposal.timezone || "Asia/Seoul",
    source: "chatProposal",
    details: proposal.details || "",
    transcript: proposal.transcript || "",
    status: "active",
    roomId,
    proposalId,
    messageId: proposal.messageId,
    candidateId: candidate.candidateId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function calendarEventPayload(
  uid: string,
  data: Record<string, unknown> | undefined,
  isCreate: boolean,
): CalendarEventData {
  const title = requiredString(data?.title, "title").trim();
  if (title.length < 1 || title.length > 120) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar event title must be 1-120 characters.",
    );
  }
  const startAt = dateValue(data?.startAt, "startAt");
  const endAt = dateValue(data?.endAt, "endAt");
  if (startAt.getTime() <= Date.now()) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar event start time must be in the future.",
    );
  }
  if (endAt.getTime() <= startAt.getTime()) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar event end time must be after start time.",
    );
  }
  const source = calendarEventSource(data?.source);
  const timezone = calendarTimezoneValue(data?.timezone);
  const details = optionalString(data?.details).trim();
  if (details.length > 2000) {
    throw new HttpsError(
      "invalid-argument",
      "Calendar event details must be 2000 characters or fewer.",
    );
  }
  const now = FieldValue.serverTimestamp();
  return {
    ownerId: uid,
    title,
    startAt: admin.firestore.Timestamp.fromDate(startAt),
    endAt: admin.firestore.Timestamp.fromDate(endAt),
    timezone,
    source,
    details,
    transcript: optionalString(data?.transcript).slice(0, 4000),
    status: "active",
    ...(isCreate ? { createdAt: now } : {}),
    updatedAt: now,
  };
}

function calendarEventSource(value: unknown): CalendarEventSource {
  if (value === "chatProposal") {
    return "chatProposal";
  }
  return value === "voice" ? "voice" : "manual";
}

function calendarTimezoneValue(value: unknown) {
  const timezone = optionalString(value) || "Asia/Seoul";
  if (
    timezone.length > 64 ||
    !/^[A-Za-z_]+(?:\/[A-Za-z_]+){1,3}$/.test(timezone)
  ) {
    throw new HttpsError("invalid-argument", "Calendar timezone is invalid.");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone }).format(new Date());
  } catch {
    throw new HttpsError("invalid-argument", "Calendar timezone is invalid.");
  }
  return timezone;
}

function safeCalendarTimezone(value: unknown) {
  try {
    return calendarTimezoneValue(value);
  } catch {
    return "Asia/Seoul";
  }
}

function holidayCountryCodeValue(value: unknown) {
  if (typeof value !== "string") {
    return "KR";
  }
  const code = value.trim();
  const normalized =
    code.toLowerCase() === "none" ? "none" : code.toUpperCase();
  if (!["none", "KR", "US", "JP", "CN"].includes(normalized)) {
    throw new HttpsError(
      "invalid-argument",
      "Unsupported holiday country code.",
    );
  }
  return normalized;
}

async function createNotificationDelivery(
  ref: admin.firestore.DocumentReference,
  data: Record<string, unknown>,
) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      return false;
    }
    transaction.set(ref, {
      ...data,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

function calendarMorningBriefingText(
  events: Array<{ id: string; title: string; startAt: Date }>,
  timezone: string,
  now = new Date(),
) {
  const parts = timeZoneParts(now, timezone);
  const label = `${parts.month}\uC6D4 ${parts.day}\uC77C`;
  if (events.length === 0) {
    return `\uC88B\uC740 \uC544\uCE68\uC785\uB2C8\uB2E4. \uC624\uB298 ${label} \uB4F1\uB85D\uB41C \uC77C\uC815\uC740 \uC5C6\uC2B5\uB2C8\uB2E4.`;
  }
  const items = events
    .map(
      (event) =>
        `${formatCalendarTime(event.startAt, timezone)} ${event.title}`,
    )
    .join(". ");
  return `\uC88B\uC740 \uC544\uCE68\uC785\uB2C8\uB2E4. \uC624\uB298 ${label} \uC77C\uC815\uC740 \uCD1D ${events.length}\uAC1C\uC785\uB2C8\uB2E4. ${items}.`;
}

function truncateNotificationBody(text: string) {
  return text.length > 140 ? `${text.slice(0, 137)}...` : text;
}

function truncateDataPayload(text: string) {
  return text.length > 900 ? `${text.slice(0, 897)}...` : text;
}

function formatCalendarPushTime(date: Date, timezone: string) {
  const parts = timeZoneParts(date, timezone);
  return `${parts.month}/${parts.day} ${formatCalendarTime(date, timezone)}`;
}

function formatCalendarTime(date: Date, timezone: string) {
  const parts = timeZoneParts(date, timezone);
  const period = parts.hour < 12 ? "\uC624\uC804" : "\uC624\uD6C4";
  const hour = parts.hour % 12 === 0 ? 12 : parts.hour % 12;
  if (parts.minute === 0) {
    return `${period} ${hour}\uC2DC`;
  }
  return `${period} ${hour}\uC2DC ${parts.minute}\uBD84`;
}

function timeZoneDateKey(date: Date, timezone: string) {
  const parts = timeZoneParts(date, timezone);
  return `${parts.year}-${String(parts.month).padStart(2, "0")}-${String(
    parts.day,
  ).padStart(2, "0")}`;
}

function localDayUtcRange(date: Date, timezone: string) {
  const parts = timeZoneParts(date, timezone);
  return {
    start: localDateTimeToUtcDate(
      parts.year,
      parts.month,
      parts.day,
      0,
      0,
      0,
      timezone,
    ),
    end: localDateTimeToUtcDate(
      parts.year,
      parts.month,
      parts.day + 1,
      0,
      0,
      0,
      timezone,
    ),
  };
}

function localDateTimeToUtcDate(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timezone: string,
) {
  const utcGuess = new Date(
    Date.UTC(year, month - 1, day, hour, minute, second),
  );
  const firstOffset = timeZoneOffsetMillis(utcGuess, timezone);
  const firstDate = new Date(utcGuess.getTime() - firstOffset);
  const secondOffset = timeZoneOffsetMillis(firstDate, timezone);
  return new Date(utcGuess.getTime() - secondOffset);
}

function timeZoneOffsetMillis(date: Date, timezone: string) {
  const parts = timeZoneParts(date, timezone);
  const localAsUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  );
  return localAsUtc - (date.getTime() - date.getMilliseconds());
}

function timeZoneParts(date: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  const rawHour = Number(values.hour || 0);
  return {
    year: Number(values.year || 0),
    month: Number(values.month || 1),
    day: Number(values.day || 1),
    hour: rawHour === 24 ? 0 : rawHour,
    minute: Number(values.minute || 0),
    second: Number(values.second || 0),
  };
}

function assertVoiceDuration(durationMs: number) {
  if (durationMs < 500) {
    throw new HttpsError(
      "invalid-argument",
      "Voice message must be at least 0.5 seconds.",
    );
  }
}

function roomAudioRetentionDays(room: RoomData) {
  return boundedInt(
    room.audioRetentionDays,
    DEFAULT_AUDIO_RETENTION_DAYS,
    1,
    30,
  );
}

function retentionExpiryTimestamp(days: number) {
  return admin.firestore.Timestamp.fromMillis(
    Date.now() + days * 24 * 60 * 60 * 1000,
  );
}

function audioRetentionPreset(value: unknown, days: number) {
  if (value === "oneDay" || value === "sevenDays" || value === "custom") {
    return value;
  }
  if (days === 1) {
    return "oneDay";
  }
  if (days === 7) {
    return "sevenDays";
  }
  return "custom";
}

async function copyAudioObject(
  sourcePath: string,
  targetPath: string,
  metadata: Record<string, string>,
) {
  if (!sourcePath) {
    throw new HttpsError("invalid-argument", "Source audio path is missing.");
  }
  const exists = await storageObjectExists(sourcePath);
  if (!exists) {
    throw new HttpsError("not-found", "Source audio file was not found.");
  }
  await copyStorageObject(sourcePath, targetPath, metadata);
}

async function deleteStorageFile(storagePath: string | null | undefined) {
  if (!storagePath) {
    return;
  }
  try {
    await deleteStorageObject(storagePath);
  } catch (error) {
    logger.warn("Storage delete failed", {
      storagePath,
      error: errorDetails(error),
    });
  }
}

function audioExtension(audioPath: string) {
  const ext = path.extname(audioPath).toLowerCase();
  if (ext === ".webm" || ext === ".wav" || ext === ".mp3" || ext === ".m4a") {
    return ext;
  }
  return ".m4a";
}

async function replyToValue(
  roomRef: admin.firestore.DocumentReference,
  messageId: string,
): Promise<MessageReply | null> {
  if (!messageId) {
    return null;
  }
  const replySnapshot = await roomRef
    .collection("messages")
    .doc(messageId)
    .get();
  const replyData = replySnapshot.data() as MessageData | undefined;
  if (!replySnapshot.exists || !replyData) {
    throw new HttpsError("not-found", "Reply target message was not found.");
  }
  return {
    messageId,
    senderId: replyData.senderId,
    preview: messagePreview(replyData),
  };
}

async function latestVisibleMessage(
  roomRef: admin.firestore.DocumentReference,
  excludingMessageId: string,
): Promise<{ id: string; data: MessageData } | null> {
  const snapshot = await roomRef
    .collection("messages")
    .orderBy("createdAt", "desc")
    .limit(25)
    .get();
  for (const doc of snapshot.docs) {
    if (doc.id === excludingMessageId) {
      continue;
    }
    const data = doc.data() as MessageData | undefined;
    if (!data || data.deletedAt) {
      continue;
    }
    return { id: doc.id, data };
  }
  return null;
}

function messagePreview(message: MessageData) {
  if (message.deletedAt) {
    return "\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4.";
  }
  const text =
    message.kind === "voice"
      ? voiceTranscriptFromMessage(message)
      : (message.text || message.transcript || "").trim();
  if (text) {
    return text.slice(0, 120);
  }
  if (message.attachment) {
    return attachmentPreview(message.attachment).slice(0, 120);
  }
  if (message.kind === "voice") {
    if (message.sttStatus === "processing") {
      return "\uC74C\uC131 \uBCC0\uD658 \uC911...";
    }
    if (message.sttStatus === "failed") {
      return "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328";
    }
    return "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328";
  }
  return "\uC0C8 \uBA54\uC2DC\uC9C0";
}
function sanitizeVoiceTranscript(value: unknown): string {
  const text = optionalString(value).slice(0, 4000);
  if (!text) {
    return "";
  }
  const placeholders = new Set([
    "\uC74C\uC131 \uBA54\uC2DC\uC9C0",
    "\uC0C8 \uC74C\uC131 \uBA54\uC2DC\uC9C0",
    "Voice message",
    "\uC74C\uC131 \uBCC0\uD658 \uC911...",
    "\uC74C\uC131 \uBCC0\uD658 \uB300\uAE30 \uC911...",
    "\uC74C\uC131 \uBCC0\uD658 \uC2E4\uD328",
    "\uC74C\uC131 \uBCC0\uD658\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.",
    "\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC \uC5C6\uC74C",
    "\uC74C\uC131 \uBCC0\uD658 \uACB0\uACFC\uAC00 \uBE44\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.",
  ]);
  const mojibakeSignals = [
    "\uFFFD",
    "???",
    "\u7650",
    "\u7B4C",
    "\u56A5",
    "\u91CE",
    "\u63F6",
    "\u69AE",
    "\u63F4",
    "\u6FE1",
    "\u5A9B",
  ];
  const cleanLines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line)
    .filter((line) => !placeholders.has(line))
    .filter((line) => {
      const hasLongQuestionRun = /\?{3,}/.test(line) && line.length > 12;
      return (
        !hasLongQuestionRun &&
        !mojibakeSignals.some((signal) => line.includes(signal))
      );
    });
  return cleanLines.join("\n").trim();
}
function voiceTranscriptFromMessage(message: MessageData | undefined): string {
  return (
    sanitizeVoiceTranscript(message?.transcript) ||
    sanitizeVoiceTranscript(message?.text)
  );
}

function preferBetterVoiceTranscript(
  candidate: string | undefined | null,
  existing: string | undefined | null,
): string {
  const next = sanitizeVoiceTranscript(candidate);
  const current = sanitizeVoiceTranscript(existing);
  if (isBetterVoiceTranscriptCandidate(next, current)) {
    return next;
  }
  return current;
}

function isBetterVoiceTranscriptCandidate(
  candidate: string | undefined | null,
  existing: string | undefined | null,
): boolean {
  const next = sanitizeVoiceTranscript(candidate);
  if (!next) {
    return false;
  }
  const current = sanitizeVoiceTranscript(existing);
  if (!current) {
    return true;
  }
  const nextCompact = compactVoiceTranscript(next);
  const currentCompact = compactVoiceTranscript(current);
  if (!nextCompact) {
    return false;
  }
  if (!currentCompact) {
    return true;
  }
  if (nextCompact === currentCompact) {
    return false;
  }
  if (
    currentCompact.includes(nextCompact) &&
    currentCompact.length >= nextCompact.length
  ) {
    return false;
  }
  if (
    nextCompact.includes(currentCompact) &&
    nextCompact.length > currentCompact.length
  ) {
    return true;
  }
  return nextCompact.length > currentCompact.length;
}

function compactVoiceTranscript(value: string): string {
  return value.replace(/[\s\p{P}\p{S}]+/gu, "").toLowerCase();
}

function sanitizeVoiceTranscriptForLanguage(
  value: unknown,
  language: string,
): string {
  const transcript = sanitizeVoiceTranscript(value);
  if (!transcript) {
    return "";
  }
  const normalizedLanguage = normalizeDeepgramLanguage(language);
  if (
    normalizedLanguage === "ko" &&
    !/[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]/u.test(transcript)
  ) {
    logger.warn("Accepted non-Korean transcript for Korean voice message", {
      transcriptPreview: transcript.slice(0, 80),
      language,
    });
  }
  return transcript;
}

function normalizeSecretValue(value: unknown): string {
  return optionalString(value)
    .trim()
    .replace(/^['"]|['"]$/g, "")
    .replace(/[\r\n\t ]+/g, "");
}

async function transcribeStorageAudio(
  audioPath: string,
): Promise<TranscriptionResult>;
async function transcribeStorageAudio(
  audioPath: string,
  language: string,
): Promise<TranscriptionResult>;
async function transcribeStorageAudio(
  audioPath: string,
  language = "ko",
): Promise<TranscriptionResult> {
  const apiKey = normalizeSecretValue(
    process.env.DEEPGRAM_API_KEY || deepgramApiKey.value(),
  );
  if (!apiKey) {
    throw new HttpsError(
      "failed-precondition",
      "DEEPGRAM_API_KEY is not configured.",
    );
  }
  const model = deepgramPrerecordedModel(language);
  const audioExtension = path.extname(audioPath).toLowerCase() || ".audio";
  const tempPath = path.join(
    os.tmpdir(),
    `${path.basename(audioPath)}-${Date.now()}${audioExtension}`,
  );
  const downloadedAudio = await downloadStorageObject(audioPath);
  await fs.promises.writeFile(tempPath, downloadedAudio);
  try {
    const audioBytes = await fs.promises.readFile(tempPath);
    return transcribeAudioBytesCached({
      apiKey,
      audioBytes,
      language: normalizeDeepgramLanguage(language),
      model,
      contentType: contentTypeForAudioPath(audioPath),
    });
  } finally {
    fs.promises.unlink(tempPath).catch(() => undefined);
  }
}

interface TranscriptionResult {
  transcript: string;
  audioHash: string;
  cacheHit: boolean;
  model: string;
}

async function transcribeAudioBytesCached(options: {
  apiKey: string;
  audioBytes: Buffer;
  language: string;
  model: string;
  contentType: string;
}): Promise<TranscriptionResult> {
  const audioHash = crypto
    .createHash("sha256")
    .update(options.audioBytes)
    .digest("hex");
  const normalizedLanguage = normalizeDeepgramLanguage(options.language);
  const primaryModel = options.model || "nova-3";
  const fallbackModel = deepgramFallbackModel(normalizedLanguage, primaryModel);
  const cacheModelKey = fallbackModel
    ? `${primaryModel}_${fallbackModel}`
    : primaryModel;
  const cacheRef = db
    .collection("transcriptionCache")
    .doc(
      `${normalizedLanguage.replace(/[^a-zA-Z0-9-]/g, "_")}_${cacheModelKey.replace(
        /[^a-zA-Z0-9-]/g,
        "_",
      )}_${audioHash}`,
    );
  const cached = await cacheRef.get();
  const cachedTranscript = cached.data()?.transcript;
  if (typeof cachedTranscript === "string" && cachedTranscript.trim()) {
    await cacheRef.set(
      {
        hitCount: FieldValue.increment(1),
        lastUsedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return {
      transcript: cachedTranscript.trim(),
      audioHash,
      cacheHit: true,
      model:
        typeof cached.data()?.model === "string"
          ? (cached.data()?.model as string)
          : primaryModel,
    };
  }
  let modelUsed = primaryModel;
  let transcript = "";
  if (
    DEEPGRAM_PARALLEL_KO_MODEL_RACE &&
    normalizedLanguage.startsWith("ko") &&
    fallbackModel
  ) {
    const raced = await transcribeAudioBytesWithDeepgramModelRace({
      apiKey: options.apiKey,
      audioBytes: options.audioBytes,
      language: normalizedLanguage,
      contentType: options.contentType,
      models: [primaryModel, fallbackModel],
    });
    transcript = raced.transcript;
    modelUsed = raced.model;
  } else {
    transcript = await transcribeAudioBytesWithDeepgramWithRetry({
      apiKey: options.apiKey,
      audioBytes: options.audioBytes,
      language: normalizedLanguage,
      model: primaryModel,
      contentType: options.contentType,
    });
    if (!transcript && fallbackModel) {
      const fallbackTranscript =
        await transcribeAudioBytesWithDeepgramWithRetry({
          apiKey: options.apiKey,
          audioBytes: options.audioBytes,
          language: normalizedLanguage,
          model: fallbackModel,
          contentType: options.contentType,
        });
      if (fallbackTranscript) {
        transcript = fallbackTranscript;
        modelUsed = fallbackModel;
        logger.info("Deepgram fallback transcription succeeded", {
          language: normalizedLanguage,
          primaryModel,
          fallbackModel,
          transcriptLength: transcript.length,
        });
      } else {
        logger.warn(
          "Deepgram fallback transcription returned empty transcript",
          {
            language: normalizedLanguage,
            primaryModel,
            fallbackModel,
          },
        );
      }
    }
  }
  if (!transcript && DEEPGRAM_DETECT_LANGUAGE_FALLBACK) {
    const detectModel = deepgramDetectLanguageModel(primaryModel);
    const detectedTranscript = await transcribeAudioBytesWithDeepgramWithRetry({
      apiKey: options.apiKey,
      audioBytes: options.audioBytes,
      language: normalizedLanguage,
      model: detectModel,
      contentType: options.contentType,
      detectLanguage: true,
    });
    if (detectedTranscript) {
      transcript = detectedTranscript;
      modelUsed = `${detectModel}:detect_language`;
      logger.info("Deepgram detect-language fallback succeeded", {
        language: normalizedLanguage,
        primaryModel,
        detectModel,
        transcriptLength: transcript.length,
        audioBytes: options.audioBytes.length,
      });
    } else {
      logger.warn("Deepgram detect-language fallback returned empty transcript", {
        language: normalizedLanguage,
        primaryModel,
        detectModel,
        audioBytes: options.audioBytes.length,
      });
    }
  }
  if (transcript.trim()) {
    await cacheRef.set(
      {
        audioHash,
        language: normalizedLanguage,
        model: modelUsed,
        primaryModel,
        fallbackModel: fallbackModel || null,
        transcript,
        hitCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        lastUsedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  return {
    transcript,
    audioHash,
    cacheHit: false,
    model: modelUsed,
  };
}

async function transcribeAudioBytesWithDeepgramModelRace(options: {
  apiKey: string;
  audioBytes: Buffer;
  language: string;
  contentType: string;
  models: string[];
}): Promise<{ transcript: string; model: string }> {
  const models = Array.from(
    new Set(options.models.map((model) => model.trim()).filter(Boolean)),
  );
  const fallbackModel = models[0] || "nova-3";
  if (models.length <= 1) {
    return {
      transcript: await transcribeAudioBytesWithDeepgramWithRetry({
        apiKey: options.apiKey,
        audioBytes: options.audioBytes,
        language: options.language,
        model: fallbackModel,
        contentType: options.contentType,
      }),
      model: fallbackModel,
    };
  }

  logger.info("Deepgram Korean model race started", {
    language: options.language,
    models,
    audioBytes: options.audioBytes.length,
  });

  return new Promise((resolve) => {
    let settled = 0;
    let resolved = false;

    const finishEmptyIfDone = () => {
      if (!resolved && settled >= models.length) {
        resolved = true;
        logger.warn("Deepgram Korean model race returned empty transcript", {
          language: options.language,
          models,
          audioBytes: options.audioBytes.length,
        });
        resolve({ transcript: "", model: fallbackModel });
      }
    };

    for (const model of models) {
      transcribeAudioBytesWithDeepgramWithRetry({
        apiKey: options.apiKey,
        audioBytes: options.audioBytes,
        language: options.language,
        model,
        contentType: options.contentType,
      })
        .then((transcript) => {
          settled += 1;
          if (!resolved && transcript) {
            resolved = true;
            logger.info("Deepgram Korean model race completed", {
              language: options.language,
              model,
              transcriptLength: transcript.length,
              audioBytes: options.audioBytes.length,
            });
            resolve({ transcript, model });
            return;
          }
          finishEmptyIfDone();
        })
        .catch((error) => {
          settled += 1;
          logger.warn("Deepgram Korean model race candidate failed", {
            language: options.language,
            model,
            error: errorDetails(error),
          });
          finishEmptyIfDone();
        });
    }
  });
}

async function transcribeAudioBytesWithDeepgramWithRetry(options: {
  apiKey: string;
  audioBytes: Buffer;
  language: string;
  model: string;
  contentType: string;
  detectLanguage?: boolean;
}) {
  let transcript = "";
  for (
    let attempt = 0;
    attempt <= DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_COUNT;
    attempt += 1
  ) {
    transcript = await transcribeAudioBytesWithDeepgram(options);
    if (transcript) {
      if (attempt > 0) {
        logger.info("Deepgram empty transcript retry succeeded", {
          model: options.model,
          language: options.language,
          detectLanguage: options.detectLanguage === true,
          attempt,
          audioBytes: options.audioBytes.length,
        });
      }
      return transcript;
    }
    if (attempt < DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_COUNT) {
      logger.warn("Deepgram returned empty transcript; retrying", {
        model: options.model,
        language: options.language,
        detectLanguage: options.detectLanguage === true,
        attempt,
        audioBytes: options.audioBytes.length,
      });
      if (DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_DELAY_MS > 0) {
        await sleepMs(DEEPGRAM_EMPTY_TRANSCRIPT_RETRY_DELAY_MS * (attempt + 1));
      }
    }
  }
  return transcript;
}

function deepgramDetectLanguageModel(primaryModel: string) {
  const configured = (process.env.DEEPGRAM_DETECT_LANGUAGE_MODEL || "").trim();
  if (configured) {
    return configured;
  }
  const normalized = primaryModel.trim().toLowerCase();
  if (!normalized || normalized === "nova-3") {
    return "nova-3-general";
  }
  return primaryModel;
}

function deepgramFallbackModel(language: string, primaryModel: string) {
  const configured = (process.env.DEEPGRAM_FALLBACK_MODEL || "").trim();
  const fallback = configured || (language.startsWith("ko") ? "whisper" : "");
  if (!fallback) {
    return "";
  }
  return fallback.toLowerCase() === primaryModel.toLowerCase() ? "" : fallback;
}

function deepgramPrerecordedModel(language: string) {
  const normalizedLanguage = normalizeDeepgramLanguage(language);
  const explicit = (
    process.env.DEEPGRAM_PRERECORDED_MODEL ||
    process.env.DEEPGRAM_BATCH_MODEL ||
    ""
  ).trim();
  if (explicit) {
    return explicit;
  }
  if (normalizedLanguage.startsWith("ko")) {
    return (
      (
        process.env.DEEPGRAM_KO_MODEL ||
        process.env.DEEPGRAM_MODEL ||
        "nova-3"
      ).trim() || "nova-3"
    );
  }
  return (process.env.DEEPGRAM_MODEL || "nova-3").trim() || "nova-3";
}

function errorDetails(error: unknown) {
  const value = error as {
    name?: unknown;
    message?: unknown;
    code?: unknown;
    status?: unknown;
    statusText?: unknown;
    stack?: unknown;
  };
  return {
    name: typeof value?.name === "string" ? value.name : undefined,
    message: typeof value?.message === "string" ? value.message : undefined,
    code: typeof value?.code === "string" ? value.code : undefined,
    status: typeof value?.status === "number" ? value.status : undefined,
    statusText:
      typeof value?.statusText === "string" ? value.statusText : undefined,
    stack:
      typeof value?.stack === "string" ? value.stack.slice(0, 1200) : undefined,
  };
}

async function transcribeAudioBytesWithDeepgram(options: {
  apiKey: string;
  audioBytes: Buffer;
  language: string;
  model: string;
  contentType: string;
  detectLanguage?: boolean;
}) {
  const url = deepgramListenUrl(options.model, options.language, {
    detectLanguage: options.detectLanguage === true,
  });
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    DEEPGRAM_REQUEST_TIMEOUT_MS,
  );
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Token ${options.apiKey}`,
        "Content-Type": options.contentType,
      },
      body: options.audioBytes,
      signal: controller.signal,
    });
  } catch (error) {
    const details = errorDetails(error);
    logger.error("Deepgram transcription request failed", {
      model: options.model,
      language: options.language,
      detectLanguage: options.detectLanguage === true,
      contentType: options.contentType,
      audioBytes: options.audioBytes.length,
      error: details,
    });
    throw new HttpsError(
      details.name === "AbortError" ? "deadline-exceeded" : "unavailable",
      "Deepgram transcription request failed.",
    );
  } finally {
    clearTimeout(timeout);
  }

  const raw = await response.text();
  let payload: DeepgramTranscriptionResponse | undefined;
  try {
    payload = JSON.parse(raw) as DeepgramTranscriptionResponse;
  } catch {
    payload = undefined;
  }

  if (!response.ok) {
    logger.error("Deepgram transcription failed", {
      status: response.status,
      statusText: response.statusText,
      body: raw.slice(0, 1000),
    });
    throw new HttpsError("internal", "Deepgram transcription failed.");
  }

  const transcript =
    payload?.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim();
  if (typeof transcript !== "string") {
    logger.warn("Deepgram transcription response missing transcript", {
      body: raw.slice(0, 1000),
    });
    return "";
  }
  if (!transcript) {
    logger.warn("Deepgram transcription returned empty transcript", {
      model: options.model,
      language: options.language,
      detectLanguage: options.detectLanguage === true,
      body: raw.slice(0, 1000),
    });
  }
  return transcript;
}

interface DeepgramTranscriptionResponse {
  results?: {
    channels?: Array<{
      alternatives?: Array<{
        transcript?: string;
      }>;
    }>;
  };
}

function deepgramListenUrl(
  model: string,
  language: string,
  options: { detectLanguage?: boolean } = {},
) {
  const baseUrl =
    process.env.DEEPGRAM_API_URL || "https://api.deepgram.com/v1/listen";
  const url = new URL(baseUrl);
  url.searchParams.set("model", model || "nova-3");
  if (options.detectLanguage === true) {
    url.searchParams.set("detect_language", "true");
  } else {
    url.searchParams.set("language", normalizeDeepgramLanguage(language));
  }
  url.searchParams.set(
    "smart_format",
    process.env.DEEPGRAM_SMART_FORMAT || "true",
  );
  url.searchParams.set("punctuate", process.env.DEEPGRAM_PUNCTUATE || "true");
  url.searchParams.set("numerals", process.env.DEEPGRAM_NUMERALS || "true");
  for (const keyterm of deepgramKeyterms()) {
    url.searchParams.append("keyterm", keyterm);
  }
  return url;
}

function deepgramStreamingListenUrl(model: string, language: string) {
  const baseUrl =
    process.env.DEEPGRAM_STREAMING_API_URL ||
    "wss://api.deepgram.com/v1/listen";
  const url = new URL(baseUrl);
  url.searchParams.set("model", model);
  url.searchParams.set("language", normalizeDeepgramLanguage(language));
  url.searchParams.set("encoding", "linear16");
  url.searchParams.set("sample_rate", "16000");
  url.searchParams.set("channels", "1");
  url.searchParams.set("interim_results", "true");
  url.searchParams.set("no_delay", process.env.DEEPGRAM_NO_DELAY || "true");
  url.searchParams.set(
    "smart_format",
    process.env.DEEPGRAM_STREAMING_SMART_FORMAT || "false",
  );
  url.searchParams.set(
    "punctuate",
    process.env.DEEPGRAM_STREAMING_PUNCTUATE || "false",
  );
  url.searchParams.set(
    "numerals",
    process.env.DEEPGRAM_STREAMING_NUMERALS || "false",
  );
  url.searchParams.set(
    "endpointing",
    normalizeDeepgramPositiveInteger(process.env.DEEPGRAM_ENDPOINTING_MS, "50"),
  );
  const utteranceEndMs = normalizeDeepgramUtteranceEndMs(
    process.env.DEEPGRAM_UTTERANCE_END_MS,
  );
  if (utteranceEndMs) {
    url.searchParams.set("utterance_end_ms", utteranceEndMs);
  }
  url.searchParams.set("vad_events", "true");
  for (const keyterm of deepgramKeyterms()) {
    url.searchParams.append("keyterm", keyterm);
  }
  return url.toString();
}

function normalizeDeepgramPositiveInteger(
  value: string | undefined,
  fallback: string,
) {
  const parsed = Number((value || "").trim());
  return Number.isInteger(parsed) && parsed > 0 ? String(parsed) : fallback;
}

function normalizeDeepgramUtteranceEndMs(value: string | undefined) {
  const parsed = Number((value || "").trim());
  return Number.isInteger(parsed) && parsed >= 1000 ? String(parsed) : "";
}

function normalizeDeepgramLanguage(language: string) {
  const normalized = language.trim().toLowerCase();
  if (!normalized || normalized.startsWith("ko")) {
    return "ko";
  }
  if (normalized.startsWith("en")) {
    return "en";
  }
  if (normalized.startsWith("ja")) {
    return "ja";
  }
  if (normalized.startsWith("zh")) {
    return "zh";
  }
  return normalized;
}

function deepgramKeyterms() {
  return (process.env.DEEPGRAM_KEYTERMS || "")
    .split(",")
    .map((term) => term.trim())
    .filter(Boolean)
    .slice(0, 100);
}

function contentTypeForAudioPath(audioPath: string) {
  const ext = path.extname(audioPath).toLowerCase();
  if (ext === ".webm") {
    return "audio/webm";
  }
  if (ext === ".wav") {
    return "audio/wav";
  }
  if (ext === ".mp3") {
    return "audio/mpeg";
  }
  return "audio/mp4";
}

async function storageBucketExists() {
  const response = await storageFetch(
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket.name)}`,
  );
  if (response.status === 404) {
    return false;
  }
  if (!response.ok) {
    throw await storageResponseError(response);
  }
  return true;
}

async function storageObjectExists(storagePath: string) {
  const response = await storageFetch(storageObjectUrl(storagePath));
  if (response.status === 404) {
    return false;
  }
  if (!response.ok) {
    throw await storageResponseError(response);
  }
  return true;
}

async function downloadStorageObject(storagePath: string) {
  const response = await storageFetch(
    `${storageObjectUrl(storagePath)}?alt=media`,
  );
  if (!response.ok) {
    throw await storageResponseError(response);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function copyStorageObject(
  sourcePath: string,
  targetPath: string,
  metadata: Record<string, string>,
) {
  const response = await storageFetch(
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(
      bucket.name,
    )}/o/${encodeStorageObjectName(sourcePath)}/copyTo/b/${encodeURIComponent(
      bucket.name,
    )}/o/${encodeStorageObjectName(targetPath)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contentType: contentTypeForAudioPath(targetPath),
        metadata,
      }),
    },
  );
  if (!response.ok) {
    throw await storageResponseError(response);
  }
}

async function deleteStorageObject(storagePath: string) {
  const response = await storageFetch(storageObjectUrl(storagePath), {
    method: "DELETE",
  });
  if (response.status === 404) {
    return;
  }
  if (!response.ok) {
    throw await storageResponseError(response);
  }
}

async function storageFetch(url: string, init: RequestInit = {}) {
  const client = await googleAuth.getClient();
  const accessToken = await client.getAccessToken();
  const token =
    typeof accessToken === "string" ? accessToken : accessToken?.token;
  if (!token) {
    throw new Error("Unable to resolve Google Cloud Storage access token.");
  }
  return fetch(url, {
    ...init,
    headers: {
      ...(init.headers || {}),
      Authorization: `Bearer ${token}`,
    },
  });
}

function storageObjectUrl(storagePath: string) {
  return `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(
    bucket.name,
  )}/o/${encodeStorageObjectName(storagePath)}`;
}

function encodeStorageObjectName(storagePath: string) {
  return encodeURIComponent(storagePath);
}

async function storageResponseError(response: Response) {
  const body = await response.text().catch(() => "");
  const error = new Error(
    `Storage API ${response.status} ${response.statusText}: ${body.slice(
      0,
      500,
    )}`,
  );
  (error as Error & { status?: number; statusText?: string }).status =
    response.status;
  (error as Error & { status?: number; statusText?: string }).statusText =
    response.statusText;
  return error;
}

async function enforceActionCooldown(
  uid: string,
  action: string,
  cooldownMs: number,
) {
  const ref = db
    .collection("actionCooldowns")
    .doc(`${safeId(uid)}_${safeId(action)}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const lastAt = timestampToDate(snapshot.data()?.lastAt);
    if (lastAt && Date.now() - lastAt.getTime() < cooldownMs) {
      throw new HttpsError(
        "resource-exhausted",
        "\uC694\uCCAD\uC774 \uB108\uBB34 \uBE60\uB985\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.",
      );
    }
    transaction.set(
      ref,
      {
        uid,
        action,
        lastAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: snapshot.exists
          ? snapshot.data()?.createdAt || FieldValue.serverTimestamp()
          : FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

function reportDocId(
  uid: string,
  targetType: "message" | "room",
  targetId: string,
) {
  const hash = crypto
    .createHash("sha256")
    .update(`${uid}:${targetType}:${targetId}`)
    .digest("hex")
    .slice(0, 32);
  return `${safeId(uid).slice(0, 32)}_${targetType}_${hash}`;
}

function safeId(value: string) {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120) || "id";
}

function timestampToDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

async function deleteCollection(
  collectionRef: admin.firestore.CollectionReference,
  batchSize: number,
) {
  for (;;) {
    const snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.empty) {
      return;
    }
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snapshot.size < batchSize) {
      return;
    }
  }
}

function serializeData(value: unknown): unknown {
  if (value == null) {
    return value;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return value.map(serializeData);
  }
  if (typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(
      value as Record<string, unknown>,
    )) {
      output[key] = serializeData(item);
    }
    return output;
  }
  return value;
}

function requireUid(uid: string | undefined) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

function pluginRoutePath(url: string) {
  const pathname = new URL(url, "https://verbal.local").pathname;
  const marker = "/v1/";
  const markerIndex = pathname.indexOf(marker);
  const route = markerIndex >= 0 ? pathname.slice(markerIndex) : pathname;
  return route.replace(/\/+$/, "") || "/";
}

function pluginJsonBody(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value) as unknown;
      return pluginJsonBody(parsed);
    } catch {
      throw new PluginApiError(400, "invalid_json", "Request body is invalid.");
    }
  }
  if (
    value &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    !(value instanceof Buffer)
  ) {
    return value as Record<string, unknown>;
  }
  throw new PluginApiError(400, "invalid_json", "Request body is required.");
}

function pluginAudioBase64(value: unknown): Buffer {
  if (typeof value !== "string" || !value.trim()) {
    throw new PluginApiError(
      400,
      "audio_required",
      "audioBase64 is required.",
    );
  }
  const cleaned = value
    .replace(/^data:audio\/[a-z0-9.+-]+;base64,/i, "")
    .replace(/\s+/g, "");
  let audioBytes: Buffer;
  try {
    audioBytes = Buffer.from(cleaned, "base64");
  } catch {
    throw new PluginApiError(400, "invalid_audio", "audioBase64 is invalid.");
  }
  if (!audioBytes.length || audioBytes.length > PLUGIN_MAX_AUDIO_BYTES) {
    throw new PluginApiError(
      400,
      "invalid_audio_size",
      "audioBase64 size is outside the allowed range.",
    );
  }
  return audioBytes;
}

async function authenticatePluginRequest(
  request: PluginHttpRequest,
): Promise<PluginAuthContext> {
  const partnerId = pluginHeader(request, "x-verbal-partner-id");
  const keyId = pluginHeader(request, "x-verbal-key-id");
  const apiKey = pluginHeader(request, "x-verbal-api-key");
  if (!partnerId || !keyId || !apiKey) {
    throw new PluginApiError(
      401,
      "missing_api_key",
      "Plugin partner credentials are required.",
    );
  }
  const partnerRef = db.collection("pluginPartners").doc(partnerId);
  const [partnerSnapshot, keySnapshot] = await Promise.all([
    partnerRef.get(),
    partnerRef.collection("apiKeys").doc(keyId).get(),
  ]);
  const partner = partnerSnapshot.data() as PluginPartnerData | undefined;
  const key = keySnapshot.data();
  if (!partnerSnapshot.exists || !partner || partner.status !== "active") {
    throw new PluginApiError(
      403,
      "partner_disabled",
      "Plugin partner is not active.",
    );
  }
  if (
    !keySnapshot.exists ||
    key?.status !== "active" ||
    key?.keyHash !== pluginApiKeyHash(apiKey)
  ) {
    throw new PluginApiError(401, "invalid_api_key", "API key is invalid.");
  }
  await keySnapshot.ref.set(
    {
      lastUsedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { partnerId, keyId, partner };
}

function assertPluginFeature(auth: PluginAuthContext, feature: string) {
  const features = Array.isArray(auth.partner.enabledFeatures)
    ? auth.partner.enabledFeatures
    : [];
  if (features.length && !features.includes(feature)) {
    throw new PluginApiError(
      403,
      "feature_disabled",
      `Plugin feature ${feature} is not enabled for this partner.`,
    );
  }
}

function pluginHeader(request: PluginHttpRequest, name: string) {
  return optionalString(request.header(name));
}

function pluginApiKeyHash(apiKey: string) {
  return crypto.createHash("sha256").update(apiKey).digest("hex");
}

function pluginAudioRetentionDays(
  auth: PluginAuthContext,
  requestedDays: unknown,
) {
  return boundedInt(
    requestedDays,
    auth.partner.defaultAudioRetentionDays ||
      PLUGIN_DEFAULT_AUDIO_RETENTION_DAYS,
    1,
    30,
  );
}

async function storePluginAudio(options: {
  auth: PluginAuthContext;
  audioBytes: Buffer;
  contentType: string;
  transcript: string;
  retentionDays: number;
  request: PluginHttpRequest;
  externalUserId: string;
  conversationId: string;
  externalMessageId: string;
}) {
  const audioRef = db.collection("pluginAudio").doc();
  const audioId = audioRef.id;
  const storagePath = `plugin_audio/${options.auth.partnerId}/${audioId}${pluginAudioExtension(
    options.contentType,
  )}`;
  const expiresAt = retentionExpiryTimestamp(options.retentionDays);
  await bucket.file(storagePath).save(options.audioBytes, {
    resumable: false,
    metadata: {
      contentType: options.contentType,
      metadata: {
        partnerId: options.auth.partnerId,
        audioId,
      },
    },
  });
  await audioRef.set({
    partnerId: options.auth.partnerId,
    keyId: options.auth.keyId,
    storagePath,
    contentType: options.contentType,
    transcript: options.transcript,
    externalUserId: options.externalUserId || null,
    conversationId: options.conversationId || null,
    externalMessageId: options.externalMessageId || null,
    audioBytes: options.audioBytes.length,
    expiresAt,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    audioId,
    audioUrl: pluginAudioUrl(options.request, audioId),
    expiresAt,
  };
}

function pluginAudioUrl(request: PluginHttpRequest, audioId: string) {
  const host =
    pluginHeader(request, "x-forwarded-host") ||
    pluginHeader(request, "host") ||
    "";
  const protocol = pluginHeader(request, "x-forwarded-proto") || "https";
  const routeIndex = request.url.indexOf("/v1/");
  const prefix = routeIndex >= 0 ? request.url.slice(0, routeIndex) : "";
  return `${protocol}://${host}${prefix}/v1/audio/${encodeURIComponent(
    audioId,
  )}`;
}

async function recordPluginUsage(
  partnerId: string,
  usage: {
    transcriptionCount: number;
    messageCardCount: number;
    calendarIntentCount: number;
    audioBytes: number;
    sttMs: number;
  },
) {
  const date = kstDateKey();
  await db
    .collection("pluginUsageDaily")
    .doc(`${partnerId}_${date}`)
    .set(
      {
        partnerId,
        date,
        transcriptionCount: FieldValue.increment(usage.transcriptionCount),
        messageCardCount: FieldValue.increment(usage.messageCardCount),
        calendarIntentCount: FieldValue.increment(usage.calendarIntentCount),
        audioBytes: FieldValue.increment(usage.audioBytes),
        sttMs: FieldValue.increment(usage.sttMs),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

function sendPluginError(response: PluginHttpResponse, error: unknown) {
  if (error instanceof PluginApiError) {
    response.status(error.status).json({
      error: {
        code: error.code,
        message: error.message,
      },
    });
    return;
  }
  if (error instanceof HttpsError) {
    response.status(400).json({
      error: {
        code: error.code,
        message: error.message,
      },
    });
    return;
  }
  if (error instanceof PluginMessageCardInputError) {
    response.status(400).json({
      error: {
        code: "invalid_message_card",
        message: error.message,
      },
    });
    return;
  }
  logger.error("pluginCoreApi failed", { error: errorDetails(error) });
  response.status(500).json({
    error: {
      code: "internal",
      message: "Plugin API request failed.",
    },
  });
}

function requiredString(value: unknown, field: string) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function optionalString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function inviteToken(value: unknown) {
  const raw = requiredString(value, "token").trim();
  try {
    const url = new URL(raw);
    const parts = url.pathname.split("/").filter(Boolean);
    const inviteIndex = parts.indexOf("invite");
    if (inviteIndex !== -1 && inviteIndex + 1 < parts.length) {
      return parts[inviteIndex + 1];
    }
    if (parts.length > 0) {
      return parts[parts.length - 1];
    }
  } catch {
    // Plain token input is expected for most clients.
  }
  return raw.split("/").filter(Boolean).pop() || raw;
}

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function roomType(value: unknown): RoomType {
  if (value === "group" || value === "open") {
    return value;
  }
  return "direct";
}

function sendModeValue(value: unknown): SendMode {
  return value === "instant" ? "instant" : "confirm";
}

function roomMemberRole(value: unknown): RoomMemberRole {
  if (value === "owner" || value === "admin" || value === "member") {
    return value;
  }
  return "member";
}

function attachmentMessageKind(value: unknown): MessageKind {
  if (value === "image" || value === "file" || value === "location") {
    return value;
  }
  throw new HttpsError("invalid-argument", "Attachment kind is invalid.");
}

function numberValue(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.round(value))
    : fallback;
}

function boundedInt(
  value: unknown,
  fallback: number,
  min: number,
  max: number,
) {
  const parsed =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : Number.NaN;
  const next = Number.isFinite(parsed) ? Math.round(parsed) : fallback;
  return Math.min(max, Math.max(min, next));
}

function boundedFloat(
  value: unknown,
  fallback: number,
  min: number,
  max: number,
) {
  const parsed =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : Number.NaN;
  const next = Number.isFinite(parsed) ? parsed : fallback;
  return Math.min(max, Math.max(min, next));
}

function numericValue(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function roundMetric(value: number) {
  return Math.round(value * 100) / 100;
}

function roundCurrency(value: number) {
  return Math.round(value * 10_000) / 10_000;
}

function dateValue(value: unknown, field: string) {
  const date = typeof value === "string" ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be an ISO date string.`,
    );
  }
  return date;
}

function isExpired(value: unknown) {
  if (!value) {
    return false;
  }
  const date =
    value instanceof admin.firestore.Timestamp
      ? value.toDate()
      : value instanceof Date
        ? value
        : typeof value === "string"
          ? new Date(value)
          : null;
  return (
    !!date && !Number.isNaN(date.getTime()) && date.getTime() <= Date.now()
  );
}

function booleanValue(value: unknown, field: string) {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${field} must be a boolean.`);
  }
  return value;
}

function emojiValue(value: unknown) {
  const emoji = requiredString(value, "emoji").trim();
  if (emoji.length === 0 || emoji.length > 16) {
    throw new HttpsError("invalid-argument", "Emoji value is invalid.");
  }
  return emoji;
}

function reactionMap(value: unknown) {
  const reactions: Record<string, string[]> = {};
  if (!value || typeof value !== "object") {
    return reactions;
  }
  for (const [emoji, users] of Object.entries(
    value as Record<string, unknown>,
  )) {
    if (!Array.isArray(users)) {
      continue;
    }
    reactions[emoji] = users.filter(
      (user): user is string => typeof user === "string",
    );
  }
  return reactions;
}

function attachmentValue(
  value: unknown,
  kind: MessageKind,
  roomId: string,
  uid: string,
): MessageAttachment {
  if (!value || typeof value !== "object") {
    throw new HttpsError("invalid-argument", "attachment is required.");
  }
  const input = value as Record<string, unknown>;
  const expectedType = kind as "image" | "file" | "location";
  const title =
    optionalString(input.title).slice(0, 160) ||
    attachmentFallbackTitle(expectedType);
  const attachment: MessageAttachment = {
    type: expectedType,
    title,
  };
  const url = optionalString(input.url);
  const storagePath = optionalString(input.storagePath);
  const mimeType = optionalString(input.mimeType);
  const address = optionalString(input.address);
  if (expectedType !== "location" && !storagePath) {
    throw new HttpsError(
      "invalid-argument",
      "Uploaded attachment storagePath is required.",
    );
  }
  if (storagePath) {
    const prefix = `attachments/${roomId}/${uid}/`;
    if (!storagePath.startsWith(prefix)) {
      throw new HttpsError(
        "permission-denied",
        "Attachment storage path does not match the room.",
      );
    }
    attachment.storagePath = storagePath.slice(0, 1024);
  }
  if (url) {
    attachment.url = url.slice(0, 2048);
  }
  if (mimeType) {
    attachment.mimeType = mimeType.slice(0, 120);
  }
  if (address) {
    attachment.address = address.slice(0, 240);
  }
  if (typeof input.sizeBytes === "number" && Number.isFinite(input.sizeBytes)) {
    attachment.sizeBytes = Math.max(0, Math.round(input.sizeBytes));
  }
  if (expectedType === "location") {
    if (
      typeof input.latitude !== "number" ||
      typeof input.longitude !== "number"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "location latitude and longitude are required.",
      );
    }
    attachment.latitude = input.latitude;
    attachment.longitude = input.longitude;
  }
  return attachment;
}

function attachmentFallbackTitle(type: "image" | "file" | "location") {
  if (type === "image") {
    return "Photo";
  }
  if (type === "location") {
    return "Location";
  }
  return "File";
}

function attachmentPreview(attachment: MessageAttachment) {
  if (attachment.type === "location") {
    return attachment.address || attachment.title || "Location";
  }
  return attachment.title || attachmentFallbackTitle(attachment.type);
}

function normalizeTargetLanguage(value: string) {
  return (
    value
      .trim()
      .toLowerCase()
      .replace(/[^a-z-]/g, "")
      .slice(0, 12) || "en"
  );
}

async function translateText(source: string, targetLanguage: string) {
  const endpoint = process.env.TRANSLATION_API_URL;
  if (!endpoint) {
    return translateForFreePreview(source, targetLanguage);
  }
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(process.env.TRANSLATION_API_KEY
        ? { Authorization: `Bearer ${process.env.TRANSLATION_API_KEY}` }
        : {}),
    },
    body: JSON.stringify({
      text: source,
      targetLanguage,
      sourceLanguage: "auto",
    }),
  });
  const raw = await response.text();
  let payload: { text?: unknown; translatedText?: unknown } | undefined;
  try {
    payload = JSON.parse(raw) as { text?: unknown; translatedText?: unknown };
  } catch {
    payload = undefined;
  }
  if (!response.ok) {
    logger.error("Translation provider failed", {
      status: response.status,
      statusText: response.statusText,
      body: raw.slice(0, 500),
    });
    throw new HttpsError("internal", "Translation provider failed.");
  }
  const translated =
    typeof payload?.text === "string"
      ? payload.text
      : typeof payload?.translatedText === "string"
        ? payload.translatedText
        : "";
  if (!translated.trim()) {
    throw new HttpsError(
      "internal",
      "Translation provider returned empty text.",
    );
  }
  return translated.trim();
}

function translateForFreePreview(source: string, targetLanguage: string) {
  if (targetLanguage === "ko" || targetLanguage === "ko-kr") {
    return source;
  }
  const dictionary: Record<string, string> = {
    "\uC624\uB298 \uC800\uB141\uC5D0 \uD1B5\uD654 \uAC00\uB2A5\uD574?": "Can we talk this evening?",
    "\uB124, 8\uC2DC \uAD1C\uCC2E\uC544\uC694.": "Yes, 8 PM works for me.",
    "\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4.": "This message was deleted.",
    "\uC0AC\uC9C4": "Photo",
    "\uD30C\uC77C": "File",
    "\uC704\uCE58": "Location",
  };
  return (
    dictionary[source.trim()] ||
    (targetLanguage === "en"
      ? `English draft: ${source}`
      : `${targetLanguage.toUpperCase()}: ${source}`)
  );
}

function normalizeHandle(value: string) {
  return value.trim().replace(/^@/, "").toLowerCase();
}

function validateHandle(value: string) {
  if (
    value.length < HANDLE_MIN_LENGTH ||
    value.length > HANDLE_MAX_LENGTH ||
    !HANDLE_PATTERN.test(value)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Handle must be 3-30 Korean, English, Japanese, Chinese, number, or underscore characters.",
    );
  }
}

function defaultRoomTitle(type: RoomType, handles: string[]) {
  if (type === "direct") {
    return `@${handles[0]}`;
  }
  if (type === "open") {
    if (handles.length === 0) {
      return "\uC624\uD508\uCC44\uD305";
    }
    return `\uC624\uD508\uCC44\uD305 \u00B7 ${handles.map((handle) => `@${handle}`).join(", ")}`;
  }
  return handles.map((handle) => `@${handle}`).join(", ");
}

function errorCode(error: unknown) {
  if (error instanceof HttpsError) {
    return error.code;
  }
  if (error instanceof Error) {
    return error.name || "error";
  }
  return "unknown";
}

function sleepMs(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransientSttError(code: string) {
  const normalized = code.toLowerCase();
  return (
    normalized.includes("timeout") ||
    normalized.includes("deadline") ||
    normalized.includes("unavailable") ||
    normalized.includes("fetch") ||
    normalized.includes("network") ||
    normalized === "aborterror" ||
    normalized === "errorevent"
  );
}

function isRetryableSttFailure(code: string) {
  const normalized = code.toLowerCase();
  return (
    normalized === "stt_empty_transcript" ||
    normalized === "inline_stt_empty_transcript" ||
    isTransientSttError(normalized)
  );
}
