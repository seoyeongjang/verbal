# Voice Messenger MVP

Voice-first mobile messenger MVP for Korean users. The app keeps the familiar messenger base while making voice the fastest input path: record, transcribe, review or instantly send, then keep both audio and text searchable in the chat.

## Structure

- `apps/mobile`: Flutter iOS/Android app.
- `functions`: Firebase Cloud Functions for room creation, message sending, Deepgram STT, push notifications, deletion, and reports.
- `firebase`: Firestore rules, Storage rules, and indexes.
- `docs`: Product, data model, and operations notes.

## Documentation

- Product plan: `docs/PRODUCT.md` / Korean: `docs/ko/PRODUCT.md`
- Data model: `docs/DATA_MODEL.md` / Korean: `docs/ko/DATA_MODEL.md`
- Operations: `docs/OPERATIONS.md` / Korean: `docs/ko/OPERATIONS.md`
- Deployment status: `docs/DEPLOYMENT_STATUS.md` / Korean: `docs/ko/DEPLOYMENT_STATUS.md`
- Launch checklist: `docs/LAUNCH_CHECKLIST.md` / Korean: `docs/ko/LAUNCH_CHECKLIST.md`
- Privacy policy draft: `docs/PRIVACY_POLICY.md` / Korean: `docs/ko/PRIVACY_POLICY.md`
- Terms draft: `docs/TERMS_OF_SERVICE.md` / Korean: `docs/ko/TERMS_OF_SERVICE.md`
- Data deletion policy: `docs/DATA_DELETION_POLICY.md` / Korean: `docs/ko/DATA_DELETION_POLICY.md`
- Moderation runbook: `docs/MODERATION_RUNBOOK.md` / Korean: `docs/ko/MODERATION_RUNBOOK.md`
- Beta QA plan: `docs/BETA_QA_PLAN.md` / Korean: `docs/ko/BETA_QA_PLAN.md`
- Security rules test plan: `docs/SECURITY_RULES_TEST_PLAN.md` / Korean: `docs/ko/SECURITY_RULES_TEST_PLAN.md`
- Accessibility audit: `docs/ACCESSIBILITY_AUDIT.md` / Korean: `docs/ko/ACCESSIBILITY_AUDIT.md`
- Release/store checklist: `docs/RELEASE_STORE_CHECKLIST.md` / Korean: `docs/ko/RELEASE_STORE_CHECKLIST.md`
- Google Play submission pack: `docs/GOOGLE_PLAY_SUBMISSION.md` / Korean: `docs/ko/GOOGLE_PLAY_SUBMISSION.md`
- Google Play Data Safety draft: `docs/GOOGLE_PLAY_DATA_SAFETY.md` / Korean: `docs/ko/GOOGLE_PLAY_DATA_SAFETY.md`
- Device-free validation: `docs/DEVICE_FREE_VALIDATION.md` / Korean: `docs/ko/DEVICE_FREE_VALIDATION.md`
- Analytics event taxonomy: `docs/ANALYTICS_EVENT_TAXONOMY.md` / Korean: `docs/ko/ANALYTICS_EVENT_TAXONOMY.md`
- Load/cost simulation: `docs/LOAD_COST_SIMULATION.md` / Korean: `docs/ko/LOAD_COST_SIMULATION.md`
- Support macros: `docs/SUPPORT_MACROS.md` / Korean: `docs/ko/SUPPORT_MACROS.md`
- User action guide: `docs/USER_ACTION_GUIDE.md` / Korean: `docs/ko/USER_ACTION_GUIDE.md`
- Local testing: `docs/LOCAL_TESTING.md` / Korean: `docs/ko/LOCAL_TESTING.md`
- Free STT testing: `docs/FREE_STT_TESTING.md` / Korean: `docs/ko/FREE_STT_TESTING.md`
- Local STT testing: `docs/LOCAL_STT_TESTING.md` / Korean: `docs/ko/LOCAL_STT_TESTING.md`

Keep Korean translations under `docs/ko/` whenever project documents are added or updated.

## Local Setup

1. Install Flutter, Node.js 22 or newer, and JDK 21 or newer for Firebase emulators.
2. Install dependencies:

   ```powershell
   cd apps/mobile
   C:\Users\jangs\develop\flutter\bin\flutter.bat pub get
   cd ..\..\functions
   npm install
   ```

3. Run the mobile app in demo mode before Firebase is configured:

   ```powershell
   .\scripts\run-local-web.ps1
   ```

   Open `http://127.0.0.1:55173` for a browser-based demo. For Windows desktop, run `.\scripts\run-local-windows.ps1`.
   To serve a static web build, run `.\scripts\build-local-web.ps1`, then `.\scripts\serve-built-web.ps1`.

   For real local speech-to-text testing with Deepgram before Firebase deployment:

   ```powershell
   .\scripts\run-local-stt-web.ps1
   ```

   For zero-cost browser speech-to-text testing:

   ```powershell
   .\scripts\run-free-stt-web.ps1
   ```

4. Configure Firebase for real mode by passing these dart defines:

   ```powershell
   C:\Users\jangs\develop\flutter\bin\flutter.bat run
   ```

   The checked-in Firebase app config targets `voice-messenger-jangs-260522`. You can still override it with `--dart-define` values when switching environments.

5. Set Functions secrets/env before deploy:

   ```powershell
   firebase functions:secrets:set DEEPGRAM_API_KEY
   ```

   The code binds `DEEPGRAM_API_KEY` as a Firebase Functions v2 secret. `DEEPGRAM_MODEL` is optional and defaults to `nova-3`.

6. Run Firebase emulators from the Functions folder:

   ```powershell
   cd functions
   npm run emulators:check
   npm run serve
   ```

   These scripts use `functions/scripts/firebase-cli.js` to prefer the installed JDK 21 path on Windows even when the machine PATH still lists JDK 17 first.

## Verification

```powershell
cd apps/mobile
C:\Users\jangs\develop\flutter\bin\flutter.bat analyze
C:\Users\jangs\develop\flutter\bin\flutter.bat test

cd ..\..\functions
npm run build
npm audit
npm run emulators:check
npm run rules:test

cd ..
.\scripts\verify-production-backend.ps1
```
