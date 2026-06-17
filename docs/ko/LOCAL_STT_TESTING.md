# 로컬 STT 테스트

이 문서는 현재 Verbal STT 테스트 경로를 정리합니다. 가장 중요한 구분은 다음 세 가지입니다.

- `sendTapToPendingBubbleMs`: 사용자가 음성 메시지 bubble을 보는 데 걸린 시간
- `sendTapToTranscriptAvailableMs`: STT 텍스트가 준비되는 데 걸린 시간
- `totalFinalizeMs`: 음성 파일 업로드/복사/최종화까지 걸린 시간

목표는 GPT Voice에 가까운 STT 지연시간입니다. 현재 무료 경로는 전송 UI 반응은 빠르지만, 최종 transcript가 항상 1초 이내 준비되지는 않습니다.

## 현재 검증 기준값

2026-06-12 실기기에서 검증한 기준값입니다.

```text
Device: SM_F711N
Package: com.voicebeta.verbal
Build: debug
Path: Android PCM capture -> optimistic message -> inline/server STT fallback
```

최신 실측값:

```text
sendTapToPendingBubbleMs=2
pendingWriteMs=150
sendTapToTranscriptAvailableMs=-1 at send time
inline STT totalMs=2097
server STT ms=1151
totalFinalizeMs=3118
```

결론:

- 음성 메시지 bubble 표시는 사실상 즉시입니다.
- transcript 완성은 해당 테스트 기준 약 2초입니다.
- 음성 업로드/최종화는 약 3초입니다.
- 아직 GPT Voice 수준의 transcript 지연시간은 아닙니다.

## 무료 Android 경로

기본 모바일 경로는 다음과 같습니다.

```text
Flutter mobile recording
-> Android PCM capture
-> 녹음 중 기기 STT 시도
-> optimistic pending voice message
-> inline Cloud Function STT
-> Firebase Storage finalization
-> Firestore transcript update
```

이 경로는 OpenAI 키가 필요 없습니다. 베타 테스트에는 적합하지만 Android `SpeechRecognizer`가 짧거나 시끄러운 한국어 발화에서 partial transcript를 반환하지 않을 수 있습니다. 이 경우 bubble은 먼저 보이고, transcript는 서버 STT가 나중에 채웁니다.

기본 빌드:

```powershell
C:\Users\jangs\develop\flutter\bin\flutter.bat build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

## Deepgram Relay 경로

Deepgram relay 경로는 다음과 같습니다.

```text
Flutter mobile recording
-> Firebase ID token
-> Verbal relay
-> Deepgram WebSocket
-> live transcript
-> optimistic voice message
```

Deepgram live streaming은 이제 한국어 음성 메시지 STT의 기본 시도 경로입니다.
앱은 녹음 중 live streaming을 먼저 시도하고, live token 또는 socket을 사용할 수
없을 때 PCM 기기 STT와 서버 보정으로 fallback합니다.

로컬 USB relay override 테스트:

```powershell
$env:DEEPGRAM_API_KEY = "<local secret>"
$env:PORT = "8787"
node services/deepgram-relay/server.js
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8787 tcp:8787
C:\Users\jangs\develop\flutter\bin\flutter.bat build apk --debug `
  --dart-define=VERBAL_REALTIME_STT_PROVIDER=deepgram `
  --dart-define=VERBAL_DEEPGRAM_STREAMING_STT=true `
  --dart-define=VERBAL_USE_REALTIME_STT_FOR_KO=true `
  --dart-define=VERBAL_DEEPGRAM_RELAY_URL=http://127.0.0.1:8787/stt
```

`VERBAL_DEEPGRAM_RELAY_URL`이 없는 운영 유사 빌드에서는 앱이 기본적으로 프로젝트
Cloud Run relay를 사용합니다.

```text
https://live---verbal-deepgram-relay-uhnknahebq-du.a.run.app
```

relay는 Firebase ID token을 검증한 뒤 서버 측 `DEEPGRAM_API_KEY` secret으로
Deepgram에 연결합니다. Deepgram key를 모바일 앱에 포함하지 않습니다.
`createDeepgramStreamingToken`은 fallback 경로로 남겨두지만, 현재 Default role
Deepgram key는 `/auth/grant` 호출 권한이 없어 `403 Insufficient permissions`를
반환합니다.

provider 선택은 기본적으로 `auto`입니다.

```text
OpenAI Realtime relay 우선 -> Deepgram relay fallback -> inline/server STT fallback
```

relay에 `OPENAI_API_KEY`가 없으면 앱은 다음 로그처럼 Deepgram으로 즉시 fallback해야 합니다.

```text
voice_stt_preconnect_fallback_ready primary=openai_realtime provider=deepgram_streaming
```

이후 relay에 `OPENAI_API_KEY` secret을 추가하면 별도 provider 빌드 없이 같은 앱이
OpenAI realtime 경로를 먼저 사용할 수 있습니다.

## OpenAI Realtime 경로

OpenAI realtime 경로가 GPT Voice에 가까운 테스트 경로입니다.

```text
Flutter mobile recording
-> Firebase ID token
-> Verbal relay
-> OpenAI Realtime transcription WebSocket
-> 녹음 중 transcript delta 수신
-> 전송 시 transcript가 준비된 optimistic voice message
```

앱에는 `OPENAI_API_KEY`를 넣지 않습니다. 키는 relay 프로세스 또는 호스팅된 relay 환경에만 있어야 합니다.

1회 설정:

```text
OPENAI_API_KEY=...
```

`.env.local`에 추가한 뒤 실행합니다.

```powershell
.\scripts\run-openai-realtime-stt-android.ps1
```

스크립트가 수행하는 작업:

- `services/deepgram-relay/server.js`를 `8788` 포트에서 시작
- `/healthz`로 OpenAI 사용 가능 상태 확인
- `adb reverse tcp:8788 tcp:8788` 실행
- `VERBAL_REALTIME_STT_PROVIDER=openai`로 앱 빌드
- `com.voicebeta.verbal` 설치 및 실행

### Mock Realtime 검증

아직 `OPENAI_API_KEY`가 없으면 mock 모드로 앱이 전송 전에 streaming transcript를 받을 수 있는지 먼저 검증합니다.

```powershell
.\scripts\run-openai-realtime-stt-android.ps1 -Mock -RelayPort 8791
```

mock 모드는 OpenAI를 호출하지 않습니다. 모바일 녹음, Firebase ID token, relay WebSocket, transcript delta 처리, optimistic message 생성, Firestore write 경로를 검증합니다.

2026-06-12 mock 검증값:

```text
provider=openai_realtime
recordStartToFirstPartialMs=529
firstAudioSentToFirstPartialMs=384
finalTranscriptReadyBeforeSend=true
sendTapToPendingBubbleMs=2
sendTapToTranscriptAvailableMs=2
pendingWriteMs=380
totalFinalizeMs=2415
```

이 결과는 Verbal 앱 내부 pipeline이 GPT와 유사한 realtime transcript 타이밍을 처리할 수 있음을 증명합니다. 단, 실제 OpenAI API 지연시간은 `OPENAI_API_KEY`를 설정하고 `-Mock` 없이 같은 테스트를 반복해야 증명됩니다.

기대 로그:

```text
voice_stt_provider_started provider=openai_realtime
voice_send_client_timing ... sttProvider=openai_realtime ...
finalTranscriptReadyBeforeSend=true
sendTapToPendingBubbleMs<1000
sendTapToTranscriptAvailableMs<1000
```

자동 mock 측정:

```powershell
.\scripts\measure-openai-realtime-stt-android.ps1 -Mock -RelayPort 8792
```

이 측정 스크립트는 OpenAI realtime 빌드를 설치하고, Android 기기에서 녹음/전송을 실행한 뒤 `voice_send_client_timing` 로그를 파싱합니다. bubble 표시와 transcript 준비 시간이 모두 기준을 통과하지 못하면 실패로 종료합니다. 실제 OpenAI 지연시간 검증은 `OPENAI_API_KEY` 설정 후 `-Mock` 없이 같은 테스트를 반복해야 합니다.

relay가 OpenAI transcript 이벤트를 Deepgram 형식의 `Results` payload로 정규화하기 때문에 같은 Flutter streaming adapter를 재사용합니다.

## 문제 해결

- `OPENAI_API_KEY is missing`이 나오면 `.env.local`에 키를 추가합니다.
- 키를 넣기 전에 앱 pipeline만 검증하려면 `-Mock`으로 실행합니다.
- relay health에서 `"openai": false`가 나오면 relay 프로세스가 `OPENAI_API_KEY`를 받지 못한 상태입니다.
- Android가 `127.0.0.1`에 연결하지 못하면 `adb reverse tcp:8788 tcp:8788`을 다시 실행합니다.
- bubble은 빨리 보이지만 텍스트가 늦게 나오면 live transcript delta가 전송 전에 도착하지 않는 상태입니다.
- 로그에 `finalTranscriptReadyBeforeSend=false`가 나오면 아직 GPT Voice 수준이 아닙니다.

## 운영 메모

운영 환경에서는 relay를 앱 밖에 호스팅하고 다음 값을 사용합니다.

```powershell
--dart-define=VERBAL_REALTIME_STT_PROVIDER=openai
--dart-define=VERBAL_DEEPGRAM_RELAY_URL=https://<relay-host>/openai-stt
```

relay는 OpenAI로 오디오를 프록시하기 전에 Firebase ID token을 검증해야 합니다. OpenAI 또는 Deepgram API 키를 모바일 앱에 포함하면 안 됩니다.
