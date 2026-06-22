# Google Play Data Safety Draft

Korean translation: `docs/ko/GOOGLE_PLAY_DATA_SAFETY.md`

Status date: 2026-06-18

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
| Calendar events/reminders | Yes | No | User-requested calendar scheduling and reminders | Optional |
| Safety reports/moderation metadata | Yes | No | Report handling, abuse prevention, and service safety | Yes for safety features |
| Contacts | No | No | Not collected in current MVP | No |
| Device or other IDs | Yes | No | FCM push tokens, fraud prevention, app operation | Yes |
| App interactions | Yes | No | Usage monitoring, cost monitoring, reliability | Yes |
| Crash logs/diagnostics | Yes | No | Reliability and debugging | Optional |

## Detailed Play Console Input Matrix

Use this matrix when Play Console asks for per-data-type collection, sharing,
purpose, optionality, and deletion details. Final answers must still match the
exact submitted build.

| Category | Data type | Collected | Shared | Required | Purposes | Deletion/retention handling |
|---|---|---:|---:|---:|---|---|
| Personal info | Phone number | Yes | No | Yes | App functionality, account management, fraud prevention, security | Deleted or de-identified through account deletion flow |
| Personal info | User IDs | Yes | No | Yes | App functionality, account management, chat membership | Deleted or de-identified through account deletion flow |
| Personal info | Name / profile text | Yes | No | Yes | App functionality, profile display, communication | Deleted or de-identified through account deletion flow |
| Messages | Text messages | Yes | No | Yes | App functionality, user-requested message delivery | User can delete messages; account deletion may anonymize retained conversation records |
| Audio | Voice recordings | Yes | Yes, service-provider processing by Deepgram | No | App functionality, speech-to-text, voice message delivery | Audio expires by retention policy; transcript may remain for chat history and search |
| Messages | Voice transcripts | Yes | No | Yes for voice messaging | App functionality, accessibility, message display, search | User can delete messages; account deletion may anonymize retained conversation records |
| Photos and videos / Files and docs | Photos, media, and files | Yes | No | No | App functionality, user-requested attachment delivery | User can delete sent messages or request account/data deletion |
| Location | Approximate/precise location when shared | Yes | No | No | App functionality, user-requested location sharing | User can delete sent messages or request account/data deletion |
| Calendar | Calendar events and reminders inside Verbal | Yes | No | No | App functionality, user-requested schedule creation and reminders | User can update/delete calendar events or request account/data deletion |
| App activity | Safety reports and moderation metadata | Yes | No | Yes for safety features | Fraud prevention, security, compliance, abuse handling | May be retained as needed for safety, legal, and abuse-prevention obligations |
| Device or other IDs | FCM tokens and device/service identifiers | Yes | No | Yes | App functionality, notifications, security, service operation | Removed or rotated when no longer needed or on account deletion where applicable |
| App activity | App interactions | Yes | No | Yes | Analytics, reliability, cost monitoring, product improvement | Aggregated or deleted according to retention and account deletion policy |
| App info and performance | Crash logs and diagnostics | Yes | No | No | Crash analysis, reliability, debugging | Retained according to Firebase/Crashlytics diagnostic retention settings |
| Contacts | Contacts | No | No | No | Not collected in the current submitted build unless contact sync is enabled | Not applicable |

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

- Quick answers:

| Console question | Answer |
|---|---|
| Does the app collect or share user data? | Yes |
| Is all user data encrypted in transit? | Yes |
| Can users request that their data be deleted? | Yes |
| Does the app have an account deletion URL? | Yes: `https://verbal.chat/account/delete` |
| Does the app collect data for advertising? | No for the current uploaded AAB |
| Does the app share data with third parties? | Yes only for service-provider processing: Deepgram voice STT and Google Firebase/Cloud infrastructure |
| Is data collection optional where possible? | Yes for voice recordings, media/files, location, calendar events, notifications, crash diagnostics, and future contact sync. Account, messaging, safety, and service identifiers are required for core functionality. |

- Mark data collection as disclosed.
- Mark data sharing carefully:
  - Deepgram is a service provider processing voice audio for app functionality.
  - Google Firebase/Cloud is infrastructure/service provider processing.
- Mark users can request deletion: yes.
- Mark data is encrypted in transit: yes.
- Mark app follows a deletion mechanism: yes, via in-app account deletion and
  the published data deletion policy.

## Public Policy URLs

- Privacy Policy: `https://verbal.chat/privacy`
- Terms of Service: `https://verbal.chat/terms`
- Community Guidelines / UGC Policy:
  `https://verbal.chat/community-guidelines`
- Account Deletion: `https://verbal.chat/account/delete`
- Data Deletion: `https://verbal.chat/data-deletion`
