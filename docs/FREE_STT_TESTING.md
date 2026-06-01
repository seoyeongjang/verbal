# Free STT Testing

Use this mode when you want to test speech-to-text without consuming Deepgram credit.

## How It Works

The free local path is:

```text
Chrome or Edge Web Speech API -> Flutter review sheet -> demo chat message
```

It does not require:

- Deepgram API key
- Firebase Blaze
- Firebase Functions
- Firebase Storage
- Google Play app registration

Important limitation: browser speech recognition is useful for zero-cost UX testing, but it is not the production STT engine. Production should still be verified later with Deepgram STT.

## Run

From the repo root:

```powershell
.\scripts\run-free-stt-web.ps1
```

Open:

```text
http://127.0.0.1:55173
```

## Test Order

1. Click `데모로 시작`.
2. Open the `민지` chat room.
3. Keep send mode as `확인 후 전송`.
4. Click the microphone button.
5. Allow microphone access in Chrome or Edge.
6. Say `민지야 지금 뭐하니?`.
7. Stop recording.
8. Confirm that the review sheet contains the recognized text.
9. Send the message.
10. Switch to `즉시 전송` and test another short phrase.

## Troubleshooting

- Use Chrome or Edge. Other browsers may not expose the same speech recognition API.
- If the review sheet says the browser does not support free speech recognition, switch to Chrome or Edge.
- If no transcript appears, test a shorter phrase and speak after the recording timer starts.
- If permission fails, open browser site settings for `127.0.0.1` and allow microphone access.
- If you need production-quality STT quality checks, use `docs/LOCAL_STT_TESTING.md`, which calls Deepgram and consumes Deepgram credit.
