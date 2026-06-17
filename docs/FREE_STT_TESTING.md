# Free STT Testing

Use this mode when you want to test speech-to-text without consuming Deepgram
credit.

## How It Works

The free path now supports two runtimes:

```text
Flutter web -> Chrome/Edge Web Speech API -> transcriptOverride -> message send
Android app -> Android SpeechRecognizer -> transcriptOverride -> message send
```

When a free transcript is available, the app sends it as `transcriptOverride`.
That means `sendInstantVoiceMessage` can create a completed voice message without
calling Deepgram. If the free recognizer fails or returns an empty transcript,
the app still sends the voice message and lets the existing server STT fallback
process it when configured.

This is not a paid cloud WebSocket STT engine. It is a zero-cost, device/browser
streaming-like validation path for improving perceived latency before moving to
Deepgram Streaming STT.

## Web Run

From the repo root:

```powershell
.\scripts\run-free-stt-web.ps1
```

Open:

```text
http://127.0.0.1:55173
```

## Android Run

Build or run the Android app normally. Android free STT is enabled by default.
To disable it for a fallback-only test:

```powershell
flutter run --dart-define=VERBAL_FREE_STT=false
```

## Test Order

1. Open the app and enter a chat room.
2. Tap the microphone button.
3. Allow microphone access if prompted.
4. Speak a short message.
5. Tap the send button or stop button.
6. Verify that the voice message is sent immediately.
7. Verify that the transcript appears without a review sheet when the free STT
   engine recognizes the speech.
8. Repeat from the calendar screen with a command such as
   `올해 7월 3일 오후 2시에 데모 리뷰 일정 추가해줘`.

## Limitations

- Android `SpeechRecognizer` quality depends on the device, OS, language pack,
  Google app availability, and network/offline recognition settings.
- Browser recognition depends on Chrome/Edge Web Speech API support.
- Free STT is useful for UX validation, but production-quality, server-controlled
  low-latency STT should still be verified with Deepgram Streaming STT later.
- When the free recognizer returns no transcript, the existing server STT
  fallback may consume Deepgram usage if the backend is configured.
