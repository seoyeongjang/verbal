# Local STT Testing

This document describes the current Verbal STT test paths. The important distinction is:

- `sendTapToPendingBubbleMs`: how quickly the user sees a sent voice bubble.
- `sendTapToTranscriptAvailableMs`: how quickly the transcript text is available.
- `totalFinalizeMs`: how long audio upload/copy/finalization takes.

The product goal is GPT Voice-like STT latency. The free path currently keeps the send UI responsive, but it does not consistently produce final transcript text in under one second.

## Current Verified Baseline

Verified on a real Android device on 2026-06-12:

```text
Device: SM_F711N
Package: com.voicebeta.verbal
Build: debug
Path: Android PCM capture -> optimistic message -> inline/server STT fallback
```

Latest measured result:

```text
sendTapToPendingBubbleMs=2
pendingWriteMs=150
sendTapToTranscriptAvailableMs=-1 at send time
inline STT totalMs=2097
server STT ms=1151
totalFinalizeMs=3118
```

Conclusion:

- Voice bubble display is effectively instant.
- Transcript completion is about 2 seconds in this measured test.
- Audio finalization is about 3 seconds in this measured test.
- This is not yet GPT Voice-level transcript latency.

## Free Android Path

The default mobile path is:

```text
Flutter mobile recording
-> Android PCM capture
-> local/device STT attempt while recording
-> optimistic pending voice message
-> inline Cloud Function STT
-> Firebase Storage finalization
-> Firestore transcript update
```

This path requires no OpenAI key. It is suitable for beta testing, but Android `SpeechRecognizer` may return no partial transcript for short/noisy Korean utterances. When that happens, the transcript is filled by server STT after the bubble is already visible.

Run the default build:

```powershell
C:\Users\jangs\develop\flutter\bin\flutter.bat build apk --debug
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

## Deepgram Relay Path

The Deepgram relay path is:

```text
Flutter mobile recording
-> Firebase ID token
-> Verbal relay
-> Deepgram WebSocket
-> live transcript
-> optimistic voice message
```

Deepgram live streaming is now the default Korean voice-message STT attempt.
The app first tries live streaming while recording, then falls back to PCM
device STT and server-side correction if the live token or socket is not
available.

Local USB relay override test:

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

For production-like builds without `VERBAL_DEEPGRAM_RELAY_URL`, the app uses the
project Cloud Run relay by default:

```text
https://live---verbal-deepgram-relay-uhnknahebq-du.a.run.app
```

The relay validates the Firebase ID token, then connects to Deepgram with the
server-side `DEEPGRAM_API_KEY` secret. Do not ship the Deepgram key in the
mobile app. `createDeepgramStreamingToken` remains a fallback path, but the
current Default-role Deepgram key cannot call `/auth/grant` and returns
`403 Insufficient permissions`.

Provider selection is `auto` by default:

```text
OpenAI Realtime relay first -> Deepgram relay fallback -> inline/server STT fallback
```

If the relay has no `OPENAI_API_KEY`, the app should log:

```text
voice_stt_preconnect_fallback_ready primary=openai_realtime provider=deepgram_streaming
```

Once an `OPENAI_API_KEY` secret is added to the relay, the same app can use the
OpenAI realtime path without rebuilding for a separate provider.

## OpenAI Realtime Path

The OpenAI realtime path is the intended GPT Voice-like test path:

```text
Flutter mobile recording
-> Firebase ID token
-> Verbal relay
-> OpenAI Realtime transcription WebSocket
-> transcript delta while recording
-> optimistic voice message with transcript ready at send time
```

The app never stores `OPENAI_API_KEY`. The key must stay in the relay process or hosted relay environment.

One-time setup:

```text
OPENAI_API_KEY=...
```

Add it to `.env.local`, then run:

```powershell
.\scripts\run-openai-realtime-stt-android.ps1
```

The script:

- starts `services/deepgram-relay/server.js` on port `8788`
- checks `/healthz` for OpenAI readiness
- runs `adb reverse tcp:8788 tcp:8788`
- builds the app with `VERBAL_REALTIME_STT_PROVIDER=openai`
- installs and launches `com.voicebeta.verbal`

### Mock Realtime Verification

If `OPENAI_API_KEY` is not available yet, use mock mode to verify that the app can receive streaming transcript text before send:

```powershell
.\scripts\run-openai-realtime-stt-android.ps1 -Mock -RelayPort 8791
```

Mock mode does not call OpenAI. It validates the mobile recording, Firebase ID token, relay WebSocket, transcript delta handling, optimistic message creation, and Firestore write path.

Mock verification on 2026-06-12:

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

This proves that the Verbal app pipeline can handle GPT-like realtime transcript timing. It does not prove the real OpenAI API latency until `OPENAI_API_KEY` is configured and the same test is repeated without `-Mock`.

Expected verification logs:

```text
voice_stt_provider_started provider=openai_realtime
voice_send_client_timing ... sttProvider=openai_realtime ...
finalTranscriptReadyBeforeSend=true
sendTapToPendingBubbleMs<1000
sendTapToTranscriptAvailableMs<1000
```

Automated mock measurement:

```powershell
.\scripts\measure-openai-realtime-stt-android.ps1 -Mock -RelayPort 8792
```

The measurement script installs the OpenAI realtime build, opens the app, taps
record/send on the Android device, parses `voice_send_client_timing`, and fails
unless both the bubble and transcript thresholds pass. A real OpenAI validation
must be repeated without `-Mock` after `OPENAI_API_KEY` is configured.

The same Flutter streaming adapter is reused for both Deepgram and OpenAI relay responses because the relay normalizes OpenAI transcript events into Deepgram-like `Results` payloads.

## Troubleshooting

- If `OPENAI_API_KEY is missing` appears, add it to `.env.local`.
- If you only need to validate the app pipeline before adding a key, run with `-Mock`.
- If relay health shows `"openai": false`, the relay process did not receive `OPENAI_API_KEY`.
- If Android cannot connect to `127.0.0.1`, rerun `adb reverse tcp:8788 tcp:8788`.
- If the bubble appears quickly but text appears later, the app is not receiving live transcript deltas before send.
- If logs show `finalTranscriptReadyBeforeSend=false`, the current path is still not GPT Voice-level.

## Production Notes

For production, host the relay outside the mobile app and set:

```powershell
--dart-define=VERBAL_REALTIME_STT_PROVIDER=openai
--dart-define=VERBAL_DEEPGRAM_RELAY_URL=https://<relay-host>/openai-stt
```

The relay must validate Firebase ID tokens before proxying audio to OpenAI. Never ship OpenAI or Deepgram API keys in the mobile app.
