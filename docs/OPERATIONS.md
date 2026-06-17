# Operations

## Firebase Checklist

- Create a Firebase project and replace `.firebaserc` default project.
- Enable Authentication phone provider.
- Add Android SHA-1/SHA-256 fingerprints for phone auth.
- Enable Firestore, Cloud Storage, Cloud Functions, and Cloud Messaging.
- Deploy rules and indexes before beta testing.
- Set the `DEEPGRAM_API_KEY` Functions secret.

## Deepgram STT

- Default model: `nova-3`.
- Language hint: `ko-KR`.
- Smart formatting: enabled by default with `DEEPGRAM_SMART_FORMAT=true`.
- Optional keyterm prompting: set comma-separated `DEEPGRAM_KEYTERMS` for names and product terms that are often misrecognized.
- Current path uses file transcription after recording. Add Realtime transcription later for live partial text.
- STT calls are not limited by daily count. Daily usage is logged for cost monitoring only.
- Voice message duration is unlimited. Recordings under 0.5 seconds are rejected as empty or near-empty input.
- Duplicate audio hashes are cached in `transcriptionCache`.

## Retention And Cost Controls

- Default room audio retention is 1 day.
- Room managers can choose 1 day, 7 days, or custom 1-30 days.
- `expireVoiceAudio` runs hourly and deletes expired audio while preserving transcripts.
- Storage rules do not impose a fixed audio upload size cap.
- Track `usageDaily`, `audioRetentionStatus`, and `sttCacheHit` before widening beta access.

## Beta Monitoring

- Track callable function errors by function name.
- Track STT latency from draft creation to completed status.
- Track message documents with `sttStatus = failed`.
- Track daily text/voice volume and cost trend anomalies.
- Track STT cache hit rate and average voice duration.
- Track expired-audio deletion success.
- Review FCM failure counts in `onMessageCreated` logs.
- Audit report documents daily during closed beta.

## Manual QA

- Android real device phone auth.
- iOS real device phone auth.
- Quiet environment Korean voice.
- Noisy environment Korean voice.
- Short voice under 3 seconds.
- Long voice recording and playback.
- Automatic voice send after STT succeeds.
- STT retry and manual transcript recovery.
