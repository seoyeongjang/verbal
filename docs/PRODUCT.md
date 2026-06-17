# Product Plan

## Positioning

Verbal is a mobile messenger for Korean everyday conversations where speaking is the default fast path. The user records a short message, the app converts it to Korean text, and the recipient can either read the text or play the original audio.

## MVP Scope

- Phone number login and profile setup.
- Handle-based invite for 1:1 and small group rooms.
- Firestore realtime room list and message list.
- Text message sending.
- Voice message recording.
- Voice auto-send: record, transcribe, then send audio plus transcript without a
  confirmation sheet.
- STT recovery: retry failed STT or manually enter a transcript before sending.
- Privacy-preserving push notification body.
- Message deletion and report function endpoints.

## Out Of Scope For MVP

- Payments, ads, desktop app, open chat discovery, and full end-to-end encryption.
- Live captions while speaking. The backend is shaped so Realtime transcription can be added later.
- Large community moderation workflow beyond report capture.

## Success Metrics

- Voice send success rate.
- Average STT latency.
- STT recovery rate.
- Audio playback rate.
- 1-day default audio retention adoption.
- STT cost per DAU and cache hit rate.
- Ad plus B2B/commerce revenue per MAU.
