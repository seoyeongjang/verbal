# Local STT Testing

Use this mode to test the real Deepgram speech-to-text path on a local PC before Google Play registration and before Firebase Functions deployment.

## What This Tests

The local STT path is:

```text
Flutter web recording -> local Node STT server -> Deepgram Pre-recorded Audio API -> Flutter review sheet -> chat message
```

This validates:

- microphone permission and recording on the local PC
- Korean speech recognition quality with Deepgram
- confirm-before-send transcript review
- instant-send pending-to-completed flow
- local audio playback
- UI behavior needed before store screenshots and internal testing

This does not validate Firebase Phone Auth, Firebase Storage, Cloud Functions deployment, FCM, or production Firestore rules.

## One-Time Setup

Create a local secret file at the repo root:

```powershell
Copy-Item .env.example .env.local
notepad .env.local
```

Set:

```text
DEEPGRAM_API_KEY=...
DEEPGRAM_MODEL=nova-3
DEEPGRAM_LANGUAGE=ko-KR
DEEPGRAM_SMART_FORMAT=true
DEEPGRAM_KEYTERMS=
LOCAL_STT_PORT=8787
```

The Deepgram free credit is suitable for early beta testing. Monitor usage in the Deepgram dashboard before widening the test group.

If specific Korean names, product names, or room names are repeatedly misrecognized, add them as comma-separated keyterms, for example:

```text
DEEPGRAM_KEYTERMS=민지,보이스메신저,voice_messenger
```

## Run

From the repo root:

```powershell
.\scripts\run-local-stt-web.ps1
```

Open:

```text
http://127.0.0.1:55173
```

The script starts:

- local STT server at `http://127.0.0.1:8787/transcribe`
- Flutter web app with `VOICE_MESSENGER_LOCAL_STT=true`

## Test Order

1. Click `데모로 시작`.
2. Open the `민지` room.
3. Keep mode as `확인 후 전송`.
4. Click the microphone button.
5. Allow microphone permission in the browser.
6. Say a short Korean phrase, for example `민지야 지금 뭐해?`.
7. Stop recording.
8. Confirm the review sheet shows the recognized transcript.
9. Edit the text if needed and send it.
10. Verify the sent voice bubble includes the final text.
11. Switch the top-right send mode to `즉시 전송`.
12. Record another phrase.
13. Verify the voice bubble first shows a processing state and then updates to the transcript.

## Troubleshooting

- If the review sheet still shows `음성 메시지 초안입니다`, the app is running plain demo mode. Run `.\scripts\run-local-stt-web.ps1`.
- If `DEEPGRAM_API_KEY is not configured` appears, add the key to `.env.local`.
- If the browser cannot reach STT, check `dist/logs/local-stt-server.err.log`.
- If microphone permission does not appear, open Chrome/Edge site settings for `127.0.0.1` and allow microphone access.
- If the transcript is poor, test with shorter utterances first, then compare quiet and noisy environments.

## Production Path

The production STT path is:

```text
Flutter mobile app -> Firebase Storage -> createTranscriptionDraft Cloud Function -> Deepgram STT -> Firestore message
```

That path requires Firebase Blaze, Storage, Functions deployment, and `DEEPGRAM_API_KEY` configured as a Firebase Functions secret.
