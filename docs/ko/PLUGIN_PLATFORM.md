# Verbal Plugin Platform

원문: `docs/PLUGIN_PLATFORM.md`

## 포지셔닝

Verbal Plugin Platform은 Verbal의 음성-텍스트 메시징 기능을 다른
메신저, 커뮤니티, 업무툴에 붙일 수 있는 B2B 통합 계층으로 제공합니다.
v1은 메신저 전체를 내장하는 제품이 아니라, 호스트 서비스가 음성을
수집하고 transcript를 받고, 필요 시 재생 가능한 음성 링크와
플랫폼별 메시지 카드를 만들 수 있는 파트너 API입니다.

## 구조

- `Verbal Core API`: Firebase Functions의 `pluginCoreApi`로 노출되는
  HTTP API입니다.
- `Verbal Voice Composer`: Telegram Mini Apps, Slack modal, Teams task
  module, 모바일 webview, OS 공유 흐름에서 재사용할 정적 web composer입니다.
- `Platform Connectors`: 플랫폼 요청을 Verbal flow로 변환하는 얇은
  어댑터입니다. v1은 Slack slash command/interactive 진입점을 제공합니다.
- `Partner SDK`: Core API를 감싼 JavaScript SDK입니다. Native SDK는 같은
  HTTP contract를 감싸는 후속 단계입니다.
- `Admin Console`: 파트너 문서 생성, API key hash, smoke-test curl 생성을
  제공하는 정적 bootstrap console입니다. 보안 admin API가 붙은 hosted
  console은 enterprise 후속 단계입니다.

구현된 artifact:

| Layer | Path | Status |
| --- | --- | --- |
| Core API | `functions/src/index.ts` | 구현 |
| Card renderer | `functions/src/plugin-platform.ts` | 구현 |
| Web Composer | `services/plugin-platform/public/composer/` | 구현 |
| Slack connector | `services/plugin-platform/server.js` | 구현 |
| Admin bootstrap console | `services/plugin-platform/public/admin/` | 구현 |
| JavaScript SDK | `packages/verbal-plugin-sdk/` | 구현 |

## Core API v1

모든 요청은 다음 header가 필요합니다.

- `x-verbal-partner-id`: `pluginPartners` 하위 Firestore 문서 ID.
- `x-verbal-key-id`: `pluginPartners/{partnerId}/apiKeys` 하위 API key 문서 ID.
- `x-verbal-api-key`: 원문 API key. Verbal은 SHA-256 hash만 저장합니다.

원문 key를 저장하지 않고 API key 문서 payload를 만들려면 다음을 실행합니다.

```powershell
cd functions
npm run plugin:key-doc -- demoPartner default verbal_live_xxx
```

Endpoint:

| Endpoint | 목적 |
| --- | --- |
| `POST /v1/transcriptions` | `audioBase64`를 받아 transcript metadata를 반환하고, 필요 시 단기 보존 음성을 저장합니다. |
| `POST /v1/message-cards` | transcript, audio, calendar metadata를 플랫폼별 메시지 카드 payload로 변환합니다. |
| `POST /v1/calendar-intents` | transcript 또는 음성 명령을 앱 내부 캘린더 intent 초안으로 변환합니다. |
| `GET /v1/audio/{audioId}` | 파트너를 인증한 뒤 짧은 유효기간의 signed audio URL로 redirect합니다. |

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

Response는 `plainText`와 대상 플랫폼에 맞춘 `richCard`를 포함합니다.
v1은 `generic`, `telegram`, `slack`, `teams`, `kakao`, `line`, `meta`를
지원하며, 알 수 없는 값은 `generic`으로 처리합니다.

## 파트너 데이터 모델

- `pluginPartners/{partnerId}`: 파트너명, 상태, 활성 기능, 기본 음성
  보존기간, 향후 connector 설정.
- `pluginPartners/{partnerId}/apiKeys/{keyId}`: `keyHash`, 상태, 생성 시각,
  마지막 사용 시각.
- `pluginAudio/{audioId}`: 파트너 소유 plugin audio metadata와 만료 시각.
- `pluginUsageDaily/{partnerId}_{yyyy-mm-dd}`: 전사, 메시지 카드, 캘린더
  intent, audio bytes, STT 지연시간 일간 집계.

Firebase rules에서는 모든 client read/write를 차단합니다. Cloud Functions
Admin SDK만 해당 컬렉션을 읽거나 수정합니다.

## 사업 패키징

- Starter: 월 기본료, 제한된 connector, STT 사용량 과금.
- Growth: 더 높은 사용량, 메시지 카드 API, Partner SDK, usage report.
- Enterprise: 전용 connector 지원, SLA, 맞춤 보존 정책, 비공개 과금 조건,
  region/SOC2 검토 지원, 볼륨 할인.

주요 고객군은 업무 메신저, 커뮤니티, 고객상담 SaaS, 교육 플랫폼,
병원/예약/로컬 비즈니스처럼 음성 입력이 마찰을 줄이는 서비스입니다.

## Rollout

1. Core API와 generic card renderer를 출시합니다.
2. `services/plugin-platform`을 host하고 Slack slash command 또는 shortcut을
   `/connectors/slack/command` 또는 `/connectors/slack/interactive`에 연결합니다.
3. `packages/verbal-plugin-sdk`로 partner-side server 또는 web integration을
   구현합니다.
4. 앱/봇 형태의 interaction surface가 있는 Teams, Telegram connector를 다음에
   출시합니다.
5. Kakao, LINE, Instagram, WhatsApp은 플랫폼 정책상 허용되는 business/share
   API 범위에서 추가합니다.
6. 음성 메시징 API 도입이 검증된 뒤 Calendar Add-on을 유료 v1.5 패키지로
   추가합니다.

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
