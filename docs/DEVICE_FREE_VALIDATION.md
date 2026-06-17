# Device-Free Validation Plan

Korean translation: `docs/ko/DEVICE_FREE_VALIDATION.md`

Status date: 2026-05-28

This plan covers validation that can be completed before a physical Android
device is available.

## Completed Without Device

- Firebase Blaze production backend verification.
- Firebase Phone Number sign-in provider enabled.
- Firebase Auth test phone number configured:
  - Phone: `+16505550101`
  - Code: `123456`
- Firebase Auth SMS region allowlist configured for `KR` and `US`.
- Firestore and Storage rules compile.
- Firestore and Storage allow/deny tests pass.
- Functions build passes.
- Calendar parser unit test passes for explicit Korean date/time commands.
- Flutter analyze and widget tests pass.
- Flutter widget test covers in-app calendar create, edit, and hard delete in
  demo mode.
- Web demo build passes.
- Android release AAB build passes.
- Budget alert and logging alert policies exist.
- Android emulator sign-up smoke test passed on `DecisionHub_API_36`.
- Android emulator microphone permission prompt and recording active state were
  verified.
- Production backend E2E smoke test passes with Firebase Auth test phones:
  direct room creation, two-way text send, voice upload, Deepgram transcript,
  automatic voice send, instant backend send, and FCM stale-token cleanup.
- In-app calendar data model and Firestore rule behavior can be validated
  without a physical device because events are stored under the authenticated
  user document and writes are mediated by callable Functions.

## Completed Emulator Smoke Test

Date: 2026-05-28

Device: Android emulator `DecisionHub_API_36` (`emulator-5554`)

Build: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`

Auth:
- Phone: `+16505550101`
- Code: `123456`
- Created test user handle: `smoke_0528170251`

Verified:
- App launches to the phone-number sign-in screen.
- Firebase test phone verification reaches the SMS code screen without real SMS.
- SMS code sign-in succeeds.
- New-user profile setup accepts display name and handle.
- Profile save succeeds after fixing empty-handle cleanup.
- Home screen loads in production Firebase mode.
- Room list query succeeds after deploying the Firestore room-list rule fix.
- Android notification permission prompt appears and can be accepted.

Evidence artifacts:
- `artifacts/after-request-code-region-fixed.png`
- `artifacts/after-login-code.png`
- `artifacts/after-fixed-profile-submit.png`
- `artifacts/after-firestore-rules-retry.png`
- `artifacts/production-e2e-smoke-20260528180740.json`
- `artifacts/mic-permission-check.png`
- `artifacts/mic-recording-active.png`
- `artifacts/after-record-stop.png`

Fixes made during the smoke test:
- Allowed Firebase Auth SMS regions `KR` and `US`.
- Fixed profile save when the previous handle is an empty string.
- Fixed Firestore `rooms` list rule to allow participant-scoped room queries.
- Added a security-rules test for the home room-list query.

## Repeat Emulator Smoke Test

Use the Firebase Auth test number above to verify the sign-up UI without real
SMS.

1. Launch Android emulator:

   ```powershell
   cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile
   C:\Users\jangs\develop\flutter\bin\flutter.bat emulators --launch DecisionHub_API_36
   ```

2. Run the app:

   ```powershell
   C:\Users\jangs\develop\flutter\bin\flutter.bat run -d emulator-5554
   ```

3. Use test auth:
   - Phone: `+16505550101`
   - Code: `123456`

4. Verify:
   - Login screen opens.
   - Test phone sign-in succeeds.
   - Profile and user ID setup works.
   - Room list loads.
   - Demo-free production backend mode is active.

## Still Requires Physical Device

- Real SMS delivery to a non-test phone number.
- Real microphone recording quality on physical devices.
- Deepgram transcript quality from real voice input.
- Voice-to-calendar capture quality from real microphone input.
- Real FCM push delivery in foreground, background, and terminated app states.
- Real network, battery, and OS permission behavior.
- Play Store install/update behavior through Internal Testing.
