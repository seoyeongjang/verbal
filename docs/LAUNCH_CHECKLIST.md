# Launch Checklist

Korean translation: `docs/ko/LAUNCH_CHECKLIST.md`

Status date: 2026-06-19

This checklist tracks the current Verbal MVP against the work still
needed before a public launch. The app is feature-rich enough for local and
closed beta validation, but it is not production-launch ready until the P0
items are complete.

Related review: `docs/MESSENGER_FUNCTION_AND_LAUNCH_REVIEW.md` compares
Verbal with Instagram DM, KakaoTalk, and Telegram and lists the next product
functions plus launch-preparation gaps.

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
- [x] Messages and channels tabs; request messages moved to the user menu.
- [x] Native ad slot outside private chat content.
- [x] Swipe row actions for pin, mute, delete/leave, and room management flows.
- [x] Unified chat creation: one selected friend opens 1:1, two or more selected
  friends open a group.
- [x] Open chat creation with registered-friend invites and shareable invite
  links/QR.
- [x] Home global search v1 across rooms, message text, voice transcripts,
  attachment metadata, and calendar events.

### Chat and Voice Messaging

- [x] Text message send and realtime room updates.
- [x] Voice recording flow.
- [x] Browser free STT mode for zero-cost UX testing.
- [x] Local Deepgram STT mode for real STT quality testing before Firebase
  Functions deployment.
- [x] Firebase Functions Deepgram STT path in code.
- [x] Voice STT auto-send without a review sheet.
- [x] STT recovery sheet for retry or manual transcript entry when STT fails.
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
- [x] Suspicious-link warning before sending outbound text links.

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
  automatic save for complete commands, retry prompt for incomplete commands.
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
  direct room creation, two-way text send, message edit/delete, reaction,
  pin/unpin, scheduled send, file attachment, location message, translation,
  voice upload, Deepgram transcript, automatic voice send, instant backend
  send, calendar voice event create/edit/delete, chat calendar proposal
  vote/finalize, open-chat invite link join/leave, report, block, and FCM
  stale-token cleanup.
- [x] Google Play store listing text prepared under `artifacts/store/google-play`.
- [x] Google Play submission pack prepared.
- [x] Google Play closed testing operation pack prepared with tester CSV,
  invitation copy, feedback questions, issue template, and evidence commands.
- [x] Play reviewer access instructions prepared for phone sign-in review.
- [x] Play App content worksheet prepared for app access, ads, Data Safety,
  account deletion, target audience, content rating, sensitive permissions, and
  UGC declarations.
- [x] Google Play Data Safety draft prepared.
- [x] Device-free validation plan prepared.
- [x] Android release artifact/signing verifier prepared.
- [x] Launch gate report generator prepared.
- [x] Manual launch evidence template prepared for Play Console and real-device
  proof.
- [x] Manual launch evidence verifier prepared to report missing Play Console,
  real-device E2E, and FCM proof fields.
- [x] Preinternal release check prepared to run build, store assets, Android
  release verification, launch readiness, Play Console pack, closed testing
  pack, evidence template, evidence shape check, launch gate, and launch
  handoff in one command.
- [x] Launch handoff pack prepared to consolidate Play Console, closed testing,
  real-device E2E, FCM, and launch-evidence recording steps into
  `artifacts/launch-handoff-latest.md`.
- [x] Launch consistency verifier prepared so the AAB, Play Console pack,
  launch gate, and handoff must describe the same release candidate.
- [x] Public release hard gate prepared so production/public exposure fails
  until strict launch evidence and `readyForPublicUserExposure` pass.
- [x] Android real-device QA evidence capture script and guide prepared.

## Partially Implemented / Needs Production Verification

- [x] Production Deepgram STT backend path is deployed and verified by server
  E2E for automatic voice send and instant backend send messages.
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
- [x] Deploy Firestore rules and indexes again after final review; latest
  deployment on 2026-06-18 includes sign-up policy-consent fields.
- [x] Run Android emulator production-backend sign-up smoke test with Firebase
  test phone, profile setup, handle reservation, and room-list load.
- [x] Verify Android emulator microphone permission prompt and active recording
  state.
- [x] Run production backend E2E for Firebase Auth test phones, direct room
  creation, two-way text send, voice upload, Deepgram transcript, automatic
  voice send, instant backend send, and FCM stale-token cleanup.
- [x] Run a full production Firebase backend E2E test with Firebase test-phone
  auth: phone auth, profile setup, handle
  reservation, room creation, text send, voice upload, Deepgram transcript,
  automatic voice send, attachment, location, scheduled send, translation,
  invite link/QR, calendar voice event, calendar edit/delete, message edit,
  message delete, report, block, and leave room. Latest expanded run passed on
  2026-06-18 with artifact `artifacts/production-e2e-smoke-20260618150400.json`.
- [ ] Verify STT latency, failure handling, and Korean transcript quality on real
  devices.
- [x] Prepare Android real-device QA script to capture device info, launch
  screenshot, UIAutomator dump, logcat, and tester checklist under
  `artifacts/android-real-device-qa/<run-id>/`.
- [x] Prepare FCM real-device QA script to capture foreground, background,
  terminated, and lock-screen delivery evidence under
  `artifacts/fcm-real-device/<run-id>/`.
- [x] Verify audio retention deletion while preserving transcripts with emulator
  and production `retention_probe_*` checks on 2026-06-18.
- [ ] Verify FCM push notifications on real Android devices and record
  `artifacts/fcm-real-device-latest.json`.
- [ ] Configure APNs and verify iOS push if iOS launch is in scope.
- [x] Rebuild Android release AAB from the latest source after voice auto-send,
  voice-calendar auto-save, and sign-up policy-consent changes.
- [x] Add Android release artifact verification for package identity, Firebase
  package mapping, AAB freshness/build parity, version metadata, and upload-key
  readability before Play Console upload.
- [x] Add a launch gate report that separates Internal testing upload readiness
  from public user exposure readiness.
- [x] Add a structured manual evidence file flow so Play Console, Data Safety,
  real-device E2E, and FCM proof can close launch gates after they are done.
- [x] Add `npm run verify:launch-evidence` so filled manual evidence can be
  checked independently before rerunning the launch gate.
- [x] Add `npm run verify:preinternal` as the one-command local gate before
  Google Play Internal testing upload.
- [x] Add `npm run prepare:launch-handoff` so external Play Console and
  real-device evidence work can continue from one generated file.
- [x] Add `npm run verify:launch-consistency` to catch stale AAB, Play Console
  pack, launch gate, or handoff artifacts before upload.
- [x] Add `npm run status:launch` as a concise dashboard for the current stage,
  next external evidence step, and remaining public exposure blockers.
- [x] Add `npm run verify:public-release` as the hard gate before production
  or general public exposure.
- [x] Create Google Play Console app listing and upload to internal testing.
  Current Play Console app is `Verbal` / `com.voicebeta.verbal`; the current
  `1 (1.0.0)` AAB was uploaded to Internal testing and tester Gmail was added.
- [ ] Review Google Play Pre-launch report after Internal testing upload and
  record `playConsole.preLaunchReportReviewed` evidence.
- [ ] Complete Google Play closed testing / production access readiness, or
  record why the Play Console account is not subject to that requirement.
- [ ] Complete Google Play Data Safety form in Play Console.
- [x] Prepare privacy policy, terms of service, and account/data deletion policy
  drafts.
- [x] Add required sign-up consent gate for terms, privacy policy, and
  community/UGC policy, and store accepted policy versions on the user record.
- [x] Prepare Firebase Hosting static pages for account deletion and data
  deletion policy.
- [x] Purchase the public launch domain: `verbal.chat`.
- [x] Deploy the default Firebase Hosting site and verify the fallback HTTPS
  account/data deletion URLs.
- [x] Move `verbal.chat` authoritative DNS to Cloudflare, preserve Firebase
  Hosting records, and enable Cloudflare Email Routing for
  `support@verbal.chat` -> `jangseo37@gmail.com`.
- [x] Verify `https://verbal.chat/account/delete` and
  `https://verbal.chat/data-deletion` before Play Console submission.
- [x] Add and run automated launch readiness verification for package identity,
  release AAB, hosted deletion URLs, store listing files, policy documents,
  telemetry wiring, policy consent, and validation scripts. Latest run on
  2026-06-19 KST passed 219 checks with 0 failures.
- [x] Add launch evidence recorder so Play Console, Data Safety, Pre-launch
  report, closed testing/production access, real-device E2E, and FCM evidence
  can be recorded by command instead of direct JSON editing.
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
- [x] Remove voice-message transcript review sheet and send automatically after
  STT succeeds.
- [x] Add offline/reconnect UI states for room list and chat stream failures.
- [x] Add media upload/send progress, retry, and failure states for composer
  actions.
- [x] Add accessibility audit for contrast, tap targets, screen readers, and
  text scaling.
- [x] Complete Korean copy cleanup for the primary messenger buttons, sheets,
  menus, and errors.
- [x] Add Analytics and Crashlytics event taxonomy document.
- [x] Wire Firebase Analytics and Crashlytics packages in Firebase runtime mode
  with core funnel, voice, attachment, report, export, and push-token events.
- [x] Prepare load and cost simulation model using realistic DAU, voice length,
  STT error, and replay-rate variables.
- [x] Prepare customer support macros for login, STT failure, lost account,
  report handling, and data deletion.

## Current Verification Commands

These commands have been used during MVP validation and should be run again
after each release-bound change:

```powershell
cd .\apps\mobile
C:\Users\jangs\develop\flutter\bin\flutter.bat analyze
C:\Users\jangs\develop\flutter\bin\flutter.bat test

cd ..\..\functions
npm run test:calendar-parser
npm run build
npm run emulators:check
npm run rules:test
npm run smoke:prod-e2e
npm run verify:preinternal
npm run verify:launch-consistency
npm run status:launch
npm run verify:public-release

cd ..
.\scripts\build-free-stt-web.ps1
.\scripts\verify-production-backend.ps1
```

## 2026-06-04 Update

- [x] Product brand finalized as `Verbal` across app
  labels, store docs, product docs, support docs, local scripts, and demo assets.
- [x] Existing Firebase project ID, Android package ID, iOS bundle ID, and native
  method-channel names remain unchanged to preserve the currently configured
  production backend connection.
- [x] Voice calendar STT now saves complete title/date/time commands
  automatically without opening the add-event sheet.
- [x] Voice calendar auto-save speaks a completion message after successful
  event creation.
- [x] Voice messages now transcribe first and send automatically without opening
  the transcript review sheet.
- [x] Product, QA, operations, support, store, data-model, and launch documents
  updated to match the auto-send behavior.
- [x] Android release AAB rebuilt from the latest source and copied to
  `dist/android/app-release.aab`.
- [ ] Next: real-device spoken QA for voice message STT auto-send and voice
  calendar auto-save.
- [ ] Next: real-device FCM foreground/background/terminated push verification.
- [x] Audio retention expiry verification with transcript preservation passed in
  emulator and production probes.
- [x] Automated launch readiness verification added and passed on 2026-06-19 KST
  with hosted `verbal.chat` account/data deletion URLs, release AAB, policy
  docs, store listing files, telemetry, sign-up consent checks, release
  verification hooks, and 0 failures.
- [x] Android release verification passed on 2026-06-19 KST:
  package identity, Firebase package mapping, AAB freshness/build parity,
  version metadata, and upload key fingerprint all passed.
- [x] Play Console input pack generator added for app identity, AAB metadata,
  policy URLs, support contact, store descriptions, Data Safety summary,
  reviewer access, App content worksheet summary, screenshot checklist/
  candidates, and remaining manual steps.
- [x] Play Store asset generator added for 512px app icon, 1024x500 feature
  graphic, and five 1080x1920 phone screenshots.
- [x] Expanded production E2E smoke coverage for message edit/delete, reaction,
  pin/unpin, scheduled send, file attachment, location, translation, calendar
  proposal vote/finalize, open-chat invite join/leave, report, and block.
- [x] Production Firebase Storage rules redeployed on 2026-06-18 after fixing
  attachment uploads to allow authenticated writes under the sender UID path
  while keeping attachment reads room-member restricted.
- [x] Android real-device QA helper added:
  `scripts/run-android-real-device-qa.ps1`.
- [x] Android real-device precheck helper added:
  `scripts/run-android-real-device-precheck.ps1`.
- [x] FCM real-device QA helper added:
  `scripts/run-fcm-real-device-qa.ps1`.
- [x] Android release verification helper added:
  `scripts/verify-android-release-artifact.ps1`.
- [x] Launch gate report helper added:
  `functions/scripts/generate-launch-gate-report.js`.
- [x] Manual launch evidence template helper added:
  `functions/scripts/prepare-launch-evidence-template.js`.
- [x] Manual launch evidence recorder added:
  `functions/scripts/record-launch-evidence.js`.
- [x] Manual launch evidence verifier added:
  `functions/scripts/verify-launch-evidence.js`.
- [x] Preinternal release check helper added:
  `functions/scripts/run-preinternal-release-check.js`.
- [x] Launch handoff helper added:
  `functions/scripts/generate-launch-handoff.js`.
- [x] Launch consistency verifier added:
  `functions/scripts/verify-launch-consistency.js`.
- [x] Launch status dashboard helper added:
  `functions/scripts/generate-launch-status.js`.
- [x] Public release hard gate helper added:
  `functions/scripts/verify-public-release-gate.js`.
- [ ] Next: Google Play App content and Data Safety form completion.

## Launch Decision

Current decision: do not public-launch yet.

The MVP can continue with local preview, free STT UX testing, local Deepgram STT
testing, and closed Firebase preparation. Public launch should wait until all
P0 blockers are complete and the production E2E path is verified on real
devices.
