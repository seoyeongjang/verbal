# Cost Control And Monetization Policy

Voice Messenger is a free personal messenger. Personal chat subscription is not part of the core business model.

## Defaults

- User messaging usage is unlimited. Text and voice counts are tracked only for cost monitoring.
- Voice message duration is unlimited. The app only rejects empty or near-empty recordings under 0.5 seconds.
- Voice recording quality: 16 kHz sample rate and 64 kbps target bitrate where supported.
- Default room audio retention: 1 day.
- Retention options: 1 day, 7 days, or custom 1-30 days.
- After expiry, the audio file is deleted and the transcript remains in Firestore.

## Backend Enforcement

- Cloud Functions write `usageDaily/{uid}_{yyyy-mm-dd}` using Asia/Seoul day boundaries for cost monitoring only; they do not reject messages by daily count.
- STT is counted when transcription is requested, not when a message is finally sent.
- Voice files are hashed with SHA-256 and cached in `transcriptionCache` to avoid duplicate Deepgram calls.
- `expireVoiceAudio` runs hourly and removes expired message and draft audio files.
- Storage rules do not impose a fixed audio upload size cap. Functions only reject empty or near-empty recordings under 0.5 seconds.

## Revenue Surfaces

- Native ads are allowed in the DM list, channel list, request surfaces, and notes-adjacent surfaces.
- Ads are not inserted inside private chat message timelines.
- Business revenue should come from official accounts, business messaging, campaign notifications, reservation/order updates, coupons, local deals, and commerce affiliate fees.
- Enterprise STT or summaries should be opt-in for business channels only.

## KPIs

- STT minutes per DAU.
- Voice messages per DAU.
- Average voice duration.
- STT cache hit rate.
- STT failure rate.
- Audio deletion success rate.
- Active audio TB by retention period.
- Ad ARPU plus B2B/commerce revenue per MAU.
