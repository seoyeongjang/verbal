# Verbal Plugin Platform

Korean translation: `docs/ko/PLUGIN_PLATFORM.md`

## Positioning

Verbal Plugin Platform packages Verbal's voice-to-text messaging as a B2B
integration layer for other messengers, communities, and workflow tools. The
v1 product is not a full embedded messenger. It is a partner API and web
composer surface that lets a host product capture voice, receive transcript
text, optionally store playable audio, and render a platform-specific message
card.

## Architecture

- `Verbal Core API`: HTTP API exposed by Firebase Functions as
  `pluginCoreApi`.
- `Verbal Voice Composer`: static web composer that calls the Core API from
  Telegram Mini Apps, Slack modals, Teams task modules, mobile webviews, or
  OS share flows.
- `Platform Connectors`: thin adapters that translate platform requests into
  Verbal flows. v1 ships a Slack slash-command/interactive entrypoint.
- `Partner SDK`: JavaScript wrapper around the Core API. Native SDKs can wrap
  the same HTTP contract later.
- `Admin Console`: static bootstrap console for partner document generation,
  API key hashing, and smoke-test curl generation. A secure hosted admin API is
  still a later enterprise step.

Implemented artifacts:

| Layer | Path | Status |
| --- | --- | --- |
| Core API | `functions/src/index.ts` | Implemented |
| Card renderer | `functions/src/plugin-platform.ts` | Implemented |
| Web Composer | `services/plugin-platform/public/composer/` | Implemented |
| Slack connector | `services/plugin-platform/server.js` | Implemented |
| Admin bootstrap console | `services/plugin-platform/public/admin/` | Implemented |
| JavaScript SDK | `packages/verbal-plugin-sdk/` | Implemented |

## Core API v1

All requests require:

- `x-verbal-partner-id`: Firestore document ID under `pluginPartners`.
- `x-verbal-key-id`: API key document ID under
  `pluginPartners/{partnerId}/apiKeys`.
- `x-verbal-api-key`: raw API key. Verbal stores only the SHA-256 hash.

To generate the API key document payload without storing the raw key, run:

```powershell
cd functions
npm run plugin:key-doc -- demoPartner default verbal_live_xxx
```

Endpoints:

| Endpoint | Purpose |
| --- | --- |
| `POST /v1/transcriptions` | Accepts `audioBase64`, returns transcript metadata, and optionally stores short-lived audio. |
| `POST /v1/message-cards` | Converts transcript/audio/calendar metadata into platform-specific card payloads. |
| `POST /v1/calendar-intents` | Converts a transcript or audio command into an internal calendar intent draft. |
| `GET /v1/audio/{audioId}` | Authenticates the partner and redirects to a short-lived signed audio URL. |

### `POST /v1/transcriptions`

Request:

```json
{
  "audioBase64": "...",
  "contentType": "audio/mp4",
  "language": "ko",
  "storeAudio": true,
  "retentionDays": 1,
  "externalUserId": "partner-user-1",
  "conversationId": "room-1",
  "messageId": "msg-1"
}
```

Response:

```json
{
  "transcript": "오늘 저녁 8시에 통화 가능합니까?",
  "sttStatus": "completed",
  "language": "ko",
  "model": "nova-3",
  "cacheHit": false,
  "audioHash": "...",
  "audioId": "...",
  "audioUrl": "https://.../pluginCoreApi/v1/audio/...",
  "audioRetentionDays": 1,
  "audioExpiresAt": "2026-06-18T00:00:00.000Z"
}
```

### `POST /v1/message-cards`

Request:

```json
{
  "platform": "slack",
  "transcript": "Can we talk at 8 PM?",
  "audioUrl": "https://.../v1/audio/...",
  "senderName": "Minji"
}
```

Response contains `plainText` plus a `richCard` object shaped for the target
platform. v1 supports `generic`, `telegram`, `slack`, `teams`, `kakao`, `line`,
and `meta`; unsupported values fall back to `generic`.

## Partner Data Model

- `pluginPartners/{partnerId}`: partner name, status, enabled features,
  default audio retention, and future connector settings.
- `pluginPartners/{partnerId}/apiKeys/{keyId}`: `keyHash`, status, creation
  time, and last-used time.
- `pluginAudio/{audioId}`: partner-owned plugin audio metadata and retention
  timestamp.
- `pluginUsageDaily/{partnerId}_{yyyy-mm-dd}`: daily usage counters for
  transcription, message cards, calendar intents, audio bytes, and STT latency.

All client reads/writes are blocked by Firebase rules. Only Cloud Functions
using Admin SDK may read or mutate these collections.

## Business Packaging

- Starter: monthly base fee, limited connectors, usage-based STT billing.
- Growth: higher volume, message card API, partner SDK, usage reporting.
- Enterprise: dedicated connector support, SLA, custom retention, private
  billing terms, region/SOC2 review support, and volume discounts.

Primary customer segments are workflow messengers, communities, customer
support SaaS, education platforms, healthcare/local booking flows, and any
product where voice input reduces friction.

## Rollout

1. Ship Core API and generic card renderer.
2. Host `services/plugin-platform` and point Slack slash commands or shortcuts
   to `/connectors/slack/command` or `/connectors/slack/interactive`.
3. Use `packages/verbal-plugin-sdk` for partner-side server or web integration.
4. Add Teams and Telegram connectors next because they support app or bot-style
   interaction surfaces.
5. Add Kakao, LINE, Instagram, and WhatsApp through business/share APIs where
   platform policy allows.
6. Add Calendar Add-on as a paid v1.5 package after voice messaging API
   adoption is validated.

## Local Verification

```powershell
cd functions
npm run build
npm run test:plugin-platform
npm run rules:test

cd ..\services\plugin-platform
npm test

cd ..\..\packages\verbal-plugin-sdk
npm test
```

## Metrics

- `sendTapToPartnerMessageMs`
- `sttLatencyMs`
- `transcriptCompletionRate`
- `audioPlaybackRate`
- `calendarIntentCompletionRate`
- `partnerGrossMargin`
- `sttCostPerPartnerMAU`
- `monthlyRecurringRevenue`
