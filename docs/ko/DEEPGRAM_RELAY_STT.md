# Deepgram Relay STT

## 목적

Deepgram API key가 short-lived streaming token을 만들 권한이 없을 때, Verbal 앱은 Cloud Run relay를 통해 실시간 STT를 사용할 수 있습니다. 이 방식은 앱 APK 안에 Deepgram API key를 넣지 않고, Firebase ID token으로 사용자를 인증한 뒤 서버에서 Deepgram WebSocket에 연결합니다.

## 구조

```text
Flutter 모바일 녹음
-> Firebase ID token
-> Verbal Deepgram relay
-> Deepgram WebSocket
-> 실시간 transcript
-> 낙관적 음성 메시지
```

## Cloud Run 배포

```powershell
gcloud run deploy verbal-deepgram-relay `
  --source services/deepgram-relay `
  --region asia-northeast3 `
  --project voice-messenger-jangs-260522 `
  --allow-unauthenticated `
  --set-secrets DEEPGRAM_API_KEY=DEEPGRAM_API_KEY:latest `
  --set-env-vars "DEEPGRAM_MODEL=nova-3,DEEPGRAM_LANGUAGE=ko,DEEPGRAM_SAMPLE_RATE=16000,DEEPGRAM_ENDPOINTING_MS=300"
```

`--allow-unauthenticated`는 Cloud Run 입구만 여는 설정입니다. relay 내부에서는 WebSocket upgrade 시 Firebase ID token을 검증하므로, 인증되지 않은 클라이언트는 연결할 수 없습니다.

## 앱 빌드

```powershell
C:\Users\jangs\develop\flutter\bin\flutter.bat build apk --debug `
  --dart-define=VERBAL_DEEPGRAM_STREAMING_STT=true `
  --dart-define=VERBAL_DEEPGRAM_RELAY_URL=https://<relay-host>/stt
```

## USB 로컬 테스트

Cloud Run URL이 아직 외부에서 열리지 않거나, 실기기에서 빠르게 검증해야 할 때는 PC에서 relay를 띄우고 ADB reverse를 사용합니다.

```powershell
$env:DEEPGRAM_API_KEY = "<local secret>"
$env:PORT = "8787"
node services/deepgram-relay/server.js
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8787 tcp:8787
C:\Users\jangs\develop\flutter\bin\flutter.bat build apk --debug `
  --dart-define=VERBAL_DEEPGRAM_STREAMING_STT=true `
  --dart-define=VERBAL_DEEPGRAM_RELAY_URL=http://127.0.0.1:8787/stt
```

## 성공 기준

실기기 로그에서 다음 값이 확인되어야 합니다.

```text
sttProvider=deepgram_streaming
finalTranscriptReadyBeforeSend=true
```

이번 검증에서는 전송 버튼 이후 pending bubble이 약 2ms에 생성됐고, 전송 시점에 transcript가 이미 준비된 상태를 확인했습니다.

## 현재 검증 상태

- USB 로컬 relay 경로는 실제 Android 기기에서 검증됐습니다.
- 최신 측정값:
  - `sendTapToPendingBubbleMs=2`
  - `finalTranscriptReadyBeforeSend=true`
  - `pendingWriteMs=217`
  - `totalFinalizeMs=2453`
- 출시 빌드는 가능하면 Deepgram 임시 토큰 경로를 우선 사용합니다. 다음 명령으로 현재 key가 live streaming token을 만들 수 있는지 확인합니다.

```powershell
node functions/scripts/verify-deepgram-streaming-token.js
```

- 결과가 `reason: "deepgram_token_grant_failed"`이면 현재 Deepgram key는 서버 prerecorded STT에는 사용할 수 있지만, 앱이 직접 Deepgram live WebSocket에 붙기 위한 short-lived token 발급 권한은 없습니다.
- 이 경우 Deepgram에서 token-based authentication 권한이 있는 API key를 새로 만들고, Firebase Secret `DEEPGRAM_API_KEY`를 교체한 뒤 `createDeepgramStreamingToken`을 재배포해야 합니다.
- Cloud Run relay를 출시용으로 사용할 경우에는 앱 빌드 전에 production relay URL의 `/healthz`가 `{"ok":true}`를 반환해야 합니다.
