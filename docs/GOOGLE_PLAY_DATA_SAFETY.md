# Google Play Data Safety Draft

Korean translation: `docs/ko/GOOGLE_PLAY_DATA_SAFETY.md`

Status date: 2026-05-28

This is a Play Console Data Safety draft for the current Verbal MVP.
Review it before submission, because the final answers must match the actual
production build, privacy policy, and enabled integrations.

## Data Collection Summary

The app collects user-provided and app-generated data needed for messaging,
authentication, safety, and service operation.

| Data category | Collected | Shared | Purpose | Required |
|---|---:|---:|---|---:|
| Phone number | Yes | No | Account creation, login, abuse prevention | Yes |
| User IDs | Yes | No | Profile, handles, chat membership | Yes |
| Name/profile text | Yes | No | Profile display in chats | Yes |
| Text messages | Yes | No | Messaging and user-requested delivery | Yes |
| Voice recordings | Yes | Processed by Deepgram | STT and voice message delivery | Yes for voice |
| Voice transcripts | Yes | No | Message display and search | Yes for voice |
| Photos/files | Yes | No | User-requested attachment delivery | Optional |
| Location | Yes | No | User-requested location sharing | Optional |
| Contacts | No | No | Not collected in current MVP | No |
| Device or other IDs | Yes | No | FCM push tokens, fraud prevention, app operation | Yes |
| App interactions | Yes | No | Usage monitoring, cost monitoring, reliability | Yes |
| Crash logs/diagnostics | Planned | No | Reliability and debugging | Optional |

## Security Practices

- Data is encrypted in transit using HTTPS/TLS.
- Firebase stores production data using Google Cloud managed infrastructure.
- Firestore and Storage security rules restrict room/message data to
  authenticated room participants.
- Cloud Functions perform privileged message, invite, moderation, STT, and
  retention operations.
- Account deletion and data export flows exist in the app.

## Voice Retention

- Default voice file retention: 1 day.
- Room-level retention options: 1 day, 7 days, custom.
- After expiry, audio files are deleted and transcripts remain in chat history.

## Third-Party Processing

- Deepgram processes uploaded voice audio for speech-to-text.
- Google Firebase/Google Cloud provides authentication, database, storage,
  functions, push notification, logging, and monitoring infrastructure.

## Play Console Answer Notes

- Mark data collection as disclosed.
- Mark data sharing carefully:
  - Deepgram is a service provider processing voice audio for app functionality.
  - Google Firebase/Cloud is infrastructure/service provider processing.
- Mark users can request deletion: yes.
- Mark data is encrypted in transit: yes.
- Mark app follows a deletion mechanism: yes, via in-app account deletion and
  the published data deletion policy.
