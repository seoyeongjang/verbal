# Release and Store Checklist

Korean translation: `docs/ko/RELEASE_STORE_CHECKLIST.md`

## Store Listing Inputs

- App name: Verbal.
- Category: communication/social.
- Short description: voice-first messenger with automatic STT transcripts.
- Screenshots: auth, home, direct chat, voice message with transcript, calendar,
  room info, invite QR.
- Contact email and support URL.
- Privacy policy URL.
- Data deletion URL or in-app deletion instructions.

## Google Play Data Safety Draft

- Collected data: phone number, user ID/handle, profile name, messages,
  voice audio, transcripts, attachments, approximate/precise location when
  shared, device push token, reports, usage diagnostics.
- Purpose: authentication, messaging, STT, safety, notifications, analytics,
  abuse prevention, customer support.
- Sharing: Deepgram receives audio for STT when production STT is enabled.
- Deletion: in-app account deletion and individual message deletion.
- Encryption: Firebase transport encryption; Firestore/Storage at rest through
  Google Cloud.

## Permission Copy

- Microphone: record and send voice messages.
- Notifications: receive new message alerts.
- Photos/files: choose attachments to send.
- Location: share current location in a chat.

## Build

- Rebuild Android AAB from the latest source before upload.
- Upload to internal testing first.
- Run beta QA before production release.
