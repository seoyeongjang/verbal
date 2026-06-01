# Launch Checklist

Korean translation: `docs/ko/LAUNCH_CHECKLIST.md`

Status date: 2026-05-28

This checklist tracks the current Voice Messenger MVP against the work still
needed before a public launch. The app is feature-rich enough for local and
closed beta validation, but it is not production-launch ready until the P0
items are complete.

## Implemented Product Surface

### Account and Profile

- [x] Phone-number authentication flow in the mobile app.
- [x] Profile setup after sign-in.
- [x] User ID/handle reservation in Firestore.
- [x] Handle policy: 3-30 characters, Korean, English, Japanese, Chinese,
  numbers, and underscore.
- [x] Handle validation in app code, Firebase backend code, and Firestore
  rules.
- [x] In-app account data export.
- [x] In-app account deletion flow.

### Messenger Home

- [x] Instagram DM-inspired home layout with notes, tabs, room rows, and camera
  affordances.
- [x] Green app color system and avatar gradient mood.
- [x] Messages, channels, and requests tabs.
- [x] Native ad slot outside private chat content.
- [x] Swipe row actions for pin, mute, delete/leave, and room management flows.
- [x] Direct room and group room entry points.

### Chat and Voice Messaging

- [x] Text message send and realtime room updates.
- [x] Voice recording flow.
- [x] Browser free STT mode for zero-cost UX testing.
- [x] Local Deepgram STT mode for real STT quality testing before Firebase
  Functions deployment.
- [x] Firebase Functions Deepgram STT path in code.
- [x] Review-before-send voice transcript sheet.
- [x] Instant-send voice mode.
- [x] No default transcript fallback text when STT fails.
- [x] STT failure recovery with retry and manual transcript send.
- [x] Korean/UTF-8 transcript display fixes in the app layer.
- [x] Message reply support.
- [x] Message reactions.
- [x] Message pin/unpin.
- [x] Chat search across message text, transcript text, and translations.
- [x] Sent-message edit flow with `수정됨(edited)` label.
- [x] Sent-message hard delete with no visible placeholder.
- [x] Bubble width constrained to a maximum of 80% of the screen and compact
  width for short messages.
- [x] Sending/progress state for voice and attachment actions.
- [x] Read-state and mark-read behavior.

### Attachments and Utility Features

- [x] Image attachment flow.
- [x] File attachment flow.
- [x] Location sharing flow.
- [x] Scheduled text message flow.
- [x] Scheduled-send UI without default preset values; user must choose date and
  time.
- [x] Message translation flow.
- [x] Room-level audio retention setting.
- [x] Default audio retention policy of 1 day, with transcript retained after
  audio expiry.
- [x] No product-level daily text count limit.
- [x] No product-level daily voice count limit.
- [x] No fixed product-level voice-message duration cap.
- [x] In-app calendar screen separated from chat message composition.
- [x] Voice-to-calendar flow: STT, explicit Korean date/time parsing,
  confirmation/edit sheet, then save.
- [x] Direct calendar event add/edit/hard-delete UI, including editable
  detailed notes.
- [x] Calendar events are stored under `users/{uid}/calendarEvents` instead of
  chat message collections.

### Groups, Invites, and Safety

- [x] Handle-based room creation.
- [x] Invite link creation and revocation.
- [x] QR code display for room invites.
- [x] Invite approval mode.
- [x] Join-by-invite flow.
- [x] Member roles: owner, admin, member.
- [x] Member role updates.
- [x] Member removal.
- [x] Leave room.
- [x] Block user.
- [x] Report message.
- [x] Report room.
- [x] Sensitive action cooldowns for invite creation, invite join, reports, and
  blocking without normal message/voice usage caps.

## Implemented Backend and Operations

- [x] Firestore data model for users, handles, rooms, messages, members,
  invites, reports, usage events, calendar events, and transcription cache.
- [x] Firestore security rules.
- [x] Firestore indexes.
- [x] Firebase Storage rules.
- [x] Cloud Functions source for room creation, invites, message send/edit/delete,
  scheduled delivery, Deepgram STT, voice calendar intent parsing, calendar
  event create/update/delete, translation, reports, push notifications, account
  export/deletion, and audio expiry.
- [x] Audio retention expiry job in Functions source.
- [x] SHA-256 based transcription cache to reduce duplicate STT processing.
- [x] Usage logging hooks for text, voice, STT, and cost monitoring.
- [x] Report deduplication and moderation-ready report fields.
- [x] Android Firebase app registration.
- [x] iOS Firebase app registration.
- [x] Android upload keystore generated locally.
- [x] Android release bundle generated previously.
- [x] Local/demo web preview scripts.
- [x] Free browser STT test script.
- [x] Local Deepgram STT test script.
- [x] Firebase Auth test phone number configured for SMS-free emulator/web
  validation.
- [x] Firebase Auth SMS region allowlist configured for `KR` and `US`.
- [x] Android emulator sign-up smoke test passed with Firebase test phone,
  profile setup, handle reservation, and production-mode home load.
- [x] Production backend E2E smoke test passed with Firebase Auth test phones:
  direct room creation, two-way text send, voice upload, Deepgram transcript,
  review-send voice, instant-send voice, and FCM stale-token cleanup.
- [x] Google Play store listing text prepared under `artifacts/store/google-play`.
- [x] Google Play submission pack prepared.
- [x] Google Play Data Safety draft prepared.
- [x] Device-free validation plan prepared.

## Partially Implemented / Needs Production Verification

- [x] Production Deepgram STT backend path is deployed and verified by server
  E2E for review-send and instant-send voice messages.
- [ ] Real-device voice recording and Korean transcript quality still need
  verification with live microphone input.
- [ ] Firebase Phone Auth provider and test phone number are enabled, but the
  real SMS flow still needs production device verification. Emulator test-phone
  sign-up has passed.
- [x] Firebase Storage default bucket exists and Storage rules are deployed.
- [x] FCM server path is verified with stale-token cleanup during production
  backend E2E.
- [ ] FCM delivery must still be verified on real Android devices in foreground,
  background, and terminated states.
- [ ] iOS push requires APNs key/certificate and TestFlight verification.
- [x] Android release bundle rebuilt after the latest UI and messaging changes.
- [x] Moderation runbook prepared for report triage.
- [ ] Translation exists as a product flow, but production translation quality and
  cost monitoring need beta validation.
- [ ] Unlimited usage policy is reflected at product level, and Firebase/GCP
  budget/log alerts plus usage rollups are active. Deepgram account-level quota
  policy still needs provider-console review before public launch.
- [x] Primary messenger UI Korean copy cleanup completed for home, chat, room
  info, and permission text.

## P0 Launch Blockers

- [x] Upgrade Firebase project `voice-messenger-jangs-260522` to Blaze.
- [x] Enable Firebase Authentication Phone Number sign-in.
- [x] Create or verify the default Cloud Storage for Firebase bucket.
- [x] Deploy Firebase Storage rules.
- [x] Enable Cloud Functions, Cloud Build, Artifact Registry, Cloud Run,
  Eventarc, and Secret Manager.
- [x] Set `DEEPGRAM_API_KEY` as a Firebase Functions secret.
- [x] Deploy Cloud Functions.
- [x] Deploy Firestore rules and indexes again after final review.
- [x] Run Android emulator production-backend sign-up smoke test with Firebase
  test phone, profile setup, handle reservation, and room-list load.
- [x] Verify Android emulator microphone permission prompt, active recording
  state, and review-before-send voice sheet.
- [x] Run production backend E2E for Firebase Auth test phones, direct room
  creation, two-way text send, voice upload, Deepgram transcript, review-send,
  instant-send, and FCM stale-token cleanup.
- [ ] Run a full production Firebase E2E test: phone auth, profile setup, handle
  reservation, room creation, text send, voice upload, Deepgram transcript,
  review send, instant send, attachment, location, scheduled send, translation,
  invite link/QR, calendar voice event, calendar edit/delete, message edit,
  message delete, report, block, and leave room.
- [ ] Verify STT latency, failure handling, and Korean transcript quality on real
  devices.
- [ ] Verify audio retention deletion while preserving transcripts.
- [ ] Verify FCM push notifications on real Android devices.
- [ ] Configure APNs and verify iOS push if iOS launch is in scope.
- [x] Rebuild Android release AAB from the latest source after the emulator
  sign-up fixes.
- [ ] Create Google Play Console app listing and upload to internal testing.
- [ ] Complete Google Play Data Safety form in Play Console.
- [x] Prepare privacy policy, terms of service, and account/data deletion policy
  drafts.
- [x] Configure Firebase/GCP budgets, cost alerts, logging alerts, and Deepgram
  usage monitoring.
- [x] Complete Firestore/Storage security rule audit with allow/deny test cases.
- [x] Complete permissions copy review draft for microphone, notifications,
  photos, files, and location.
- [x] Prepare closed beta QA plan for small Android, large Android, low-end
  device, and slow-network scenarios.

## P1 Before Broad Beta

- [x] Document an internal moderation runbook for reports.
- [x] Add account deletion and data export flows.
- [x] Add invite abuse and spam throttling that does not impose normal user
  message-count limits.
- [x] Add STT retry and manual transcript recovery states.
- [x] Add offline/reconnect UI states for room list and chat stream failures.
- [x] Add media upload/send progress, retry, and failure states for composer
  actions.
- [x] Add accessibility audit for contrast, tap targets, screen readers, and
  text scaling.
- [x] Complete Korean copy cleanup for the primary messenger buttons, sheets,
  menus, and errors.
- [x] Add Analytics and Crashlytics event taxonomy document.
- [x] Prepare load and cost simulation model using realistic DAU, voice length,
  STT error, and replay-rate variables.
- [x] Prepare customer support macros for login, STT failure, lost account,
  report handling, and data deletion.

## Current Verification Commands

These commands have been used during MVP validation and should be run again
after each release-bound change:

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile
C:\Users\jangs\develop\flutter\bin\flutter.bat analyze
C:\Users\jangs\develop\flutter\bin\flutter.bat test

cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run test:calendar-parser
npm run build
npm run emulators:check
npm run rules:test
npm run smoke:prod-e2e

cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger
.\scripts\build-free-stt-web.ps1
.\scripts\verify-production-backend.ps1
```

## Launch Decision

Current decision: do not public-launch yet.

The MVP can continue with local preview, free STT UX testing, local Deepgram STT
testing, and closed Firebase preparation. Public launch should wait until all
P0 blockers are complete and the production E2E path is verified on real
devices.
