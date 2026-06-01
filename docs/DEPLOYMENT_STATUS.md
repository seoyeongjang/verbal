# Deployment Status

Korean translation: `docs/ko/DEPLOYMENT_STATUS.md`

## Completed

- Created Google Cloud/Firebase project: `voice-messenger-jangs-260522`.
- Set local ADC quota project to `voice-messenger-jangs-260522`.
- Enabled Firebase project.
- Enabled no-billing Firebase APIs that are available now:
  - Firebase Management
  - Identity Toolkit
  - Firestore
  - Firebase Storage API
  - Firebase Rules
  - FCM
  - Firebase Installations
  - Logging and Monitoring
- Created Firestore default database in `asia-northeast3`.
- Deployed Firestore rules and indexes.
- Registered Firebase Android app:
  - Package: `com.voicebeta.voice_messenger`
  - App ID: `1:203811587610:android:713b3d7faece49f920f3a3`
- Registered Firebase iOS app:
  - Bundle ID: `com.voicebeta.voiceMessenger`
  - App ID: `1:203811587610:ios:25d3ef7152d835c720f3a3`
- Downloaded Firebase app config files:
  - `apps/mobile/android/app/google-services.json`
  - `apps/mobile/ios/Runner/GoogleService-Info.plist`
- Added Flutter `DefaultFirebaseOptions` for real Firebase mode.
- Registered Android debug SHA-1 and SHA-256 certificates.
- Verified:
  - `flutter analyze`
  - `flutter test`
  - `flutter build apk --debug`
  - Android release app bundle from ASCII build path
  - `npm run build`
  - `npm audit`
- Generated Android upload keystore files locally:
  - `apps/mobile/android/app/upload-keystore.jks`
  - `apps/mobile/android/key.properties`
- Generated Android release bundle:
  - `dist/android/app-release.aab`
  - Regenerated from an ASCII build path on 2026-05-28 after the latest UI and
    messaging changes.
  - Regenerated again on 2026-05-28 after the emulator sign-up fixes.
- Google Play Console one-time registration fee has already been paid.

## Completed After Blaze Upgrade

- Verified billing is enabled for `voice-messenger-jangs-260522`.
- Enabled required production backend APIs:
  - Cloud Functions
  - Cloud Build
  - Cloud Billing
  - Artifact Registry
  - Cloud Run
  - Eventarc
  - Pub/Sub
  - Cloud Scheduler
  - Secret Manager
  - Identity Toolkit
- Created/verified the default Cloud Storage for Firebase bucket:
  - `voice-messenger-jangs-260522.firebasestorage.app`
  - Location: `asia-northeast3`
- Deployed Firebase Storage rules.
- Set `DEEPGRAM_API_KEY` as a Firebase Functions secret.
- Enabled Firebase Authentication Phone Number sign-in through the Identity
  Toolkit admin API.
- Configured Firebase Auth SMS-free test phone:
  - Phone: `+16505550101`
  - Code: `123456`
- Configured Firebase Auth E2E test phones:
  - Sender: `+16505550102` / `123456`
  - Receiver: `+16505550103` / `123456`
- Configured Firebase Auth SMS region allowlist:
  - `KR`
  - `US` for the emulator test phone.
- Deployed Firestore rules and indexes after the handle-policy regex fix.
- Deployed Firestore rules and indexes after the room-list query rule fix.
- Deployed Cloud Functions in `asia-northeast3`, including Deepgram STT,
  message, invite, group, safety, scheduled delivery, audio retention expiry,
  and push-trigger functions.
- Deployed operational Functions:
  - `getOperationalHealth`
  - `rollupUsageAndCost`
- Added stale FCM token cleanup after failed push sends.
- Configured Artifact Registry cleanup policy for Functions images.
- Configured project-scoped budget alert:
  - KRW 50,000 monthly budget
  - 50%, 80%, 100% current-spend thresholds
  - 100% forecasted-spend threshold
- Configured logging metrics and alert policies:
  - `voice_messenger_function_errors`
  - `voice_messenger_deepgram_errors`
  - `Voice Messenger Function Errors`
  - `Voice Messenger Deepgram Errors`
- Added production verification scripts:
  - `scripts/configure-auth-test-phone.ps1`
  - `scripts/configure-budget-alerts.ps1`
  - `scripts/configure-logging-alerts.ps1`
  - `scripts/verify-production-backend.ps1`
- Prepared Google Play submission materials:
  - `docs/GOOGLE_PLAY_SUBMISSION.md`
  - `docs/GOOGLE_PLAY_DATA_SAFETY.md`
  - `docs/DEVICE_FREE_VALIDATION.md`
  - `artifacts/store/google-play/`
- Added Firestore/Storage allow/deny rules test script:
  - `functions/scripts/security-rules-test.js`
  - `npm run rules:test`
- Added production backend E2E smoke script:
  - `functions/scripts/production-e2e-smoke.js`
  - `npm run smoke:prod-e2e`
- Verified after deployment:
  - `npm run build`
  - `npm run emulators:check`
  - `npm run rules:test`
  - `npm run smoke:prod-e2e`
  - `firebase functions:list`
  - `scripts/verify-production-backend.ps1`
  - Secret Manager version exists for `DEEPGRAM_API_KEY`
  - Storage bucket list includes the production Firebase bucket
- Verified Android emulator sign-up smoke test on `DecisionHub_API_36`:
  - Test phone `+16505550101` with code `123456`
  - Profile setup and handle reservation
  - Home screen production Firebase mode
  - Room-list query without Firestore permission errors
- Verified Android emulator microphone flow:
  - Microphone permission prompt appears.
  - Recording active state appears after permission grant.
  - Review-before-send voice sheet appears after stopping recording.
  - Evidence: `artifacts/mic-permission-check.png`,
    `artifacts/mic-recording-active.png`, `artifacts/after-record-stop.png`
- Verified production backend E2E on 2026-05-28:
  - Run ID: `20260528180740`
  - Direct room creation
  - Two-way text message send
  - Voice draft upload
  - Deepgram transcript generation
  - Review-send voice message
  - Instant-send voice message through server-side draft copy
  - FCM stale-token cleanup
  - Artifact: `artifacts/production-e2e-smoke-20260528180740.json`
- Rebuilt `dist/android/app-release.aab` from the latest source after the smoke
  test fixes.

## Manual Console Tasks Still Required

- For iOS push notifications, add APNs key/certificate in Firebase console.
- Create the Google Play Console app, complete store listing, and upload the AAB to an internal testing track.
- Build and upload iOS/TestFlight from macOS with Xcode and an Apple Developer account.
- Review Deepgram provider-console quota/usage alerts before public launch.
- Run real-device production E2E: real SMS phone auth, profile setup, handle reservation,
  room creation, text send, voice upload, Deepgram transcript, review send,
  instant send, attachment, location, scheduled send, translation, invite link/QR,
  edit, delete, report, block, leave room, and audio retention expiry.

See `docs/USER_ACTION_GUIDE.md` for exact steps.

## Redeploy Command

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger

.\scripts\deploy-after-user-actions.ps1
```
