# User Action Guide

Korean translation: `docs/ko/USER_ACTION_GUIDE.md`

This guide covers the remaining actions that require account ownership, billing consent, private credentials, or Apple/Firebase console access.

## 1. Upgrade Firebase To Blaze

Project: `voice-messenger-jangs-260522`

Open:

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/usage/details`

Steps:

1. Click `Modify plan` or `Upgrade`.
2. Select `Blaze`.
3. Attach a valid billing account.
4. Set a budget alert before continuing.

Recommended budget controls:

- Create a low initial monthly budget alert.
- Add alerts at 50%, 80%, and 100%.
- Review Firebase usage after every end-to-end test run.

Why this is required:

- New Firebase Storage default buckets require Blaze.
- Cloud Functions v2 deployment requires APIs such as Cloud Build, Artifact Registry, Cloud Run, Eventarc, and Secret Manager.
- Voice STT calls will consume Deepgram credit.

## 2. Enable Firebase Phone Authentication

Open:

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/authentication/providers`

Steps:

1. Click `Get started` if Authentication has not been initialized.
2. Open `Sign-in method`.
3. Select `Phone`.
4. Enable `Phone`.
5. Add test phone numbers for development.

Recommended test setup:

- Add at least one Korean test number.
- Use Firebase test verification codes for QA.
- Do not use real SMS repeatedly during development.

Android debug certificates are already registered:

- SHA-1: `03:39:23:1A:41:06:49:9B:49:13:4A:16:85:7F:CE:E7:BA:91:5F:47`
- SHA-256: `58:26:BC:1D:D1:BC:EF:D8:DD:64:C5:CE:4C:6A:7D:28:25:60:58:C3:40:46:F4:58:93:20:A8:9B:CA:01:44:9A`

## 3. Create The Firebase Storage Bucket

After Blaze is active, either open:

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/storage`

Steps:

1. Click `Get started`.
2. Choose location `asia-northeast3`.
3. Complete setup.

Or run the resume script in this repo after setting `DEEPGRAM_API_KEY`; it will create the default bucket if it is missing.

## 4. Prepare Deepgram API Key

Create or choose a Deepgram API key for the MVP backend.

Before deployment, set it in PowerShell:

```powershell
$env:DEEPGRAM_API_KEY = "..."
```

Do not commit the key to the repository.

The deployment script stores the key as a Firebase Functions secret named `DEEPGRAM_API_KEY`.

## 5. Resume Backend Deployment

After completing Blaze, Phone Auth, Storage setup, and Deepgram key preparation:

```powershell
cd "C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger"
$env:DEEPGRAM_API_KEY = "..."
.\scripts\deploy-after-user-actions.ps1
```

The script will:

- Check that billing is enabled.
- Enable Functions-related APIs.
- Create the default Firebase Storage bucket if missing.
- Build Functions.
- Deploy Storage rules.
- Set `DEEPGRAM_API_KEY` as a Functions secret.
- Deploy Cloud Functions.

## 6. Run Real E2E QA

After backend deployment:

```powershell
cd "C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile"
C:\Users\jangs\develop\flutter\bin\flutter.bat run
```

Verify:

- Phone login with a Firebase test number.
- Profile setup.
- Handle registration.
- Room creation.
- Text message send.
- Voice record.
- Automatic voice send after STT succeeds.
- STT retry and manual transcript recovery.
- Audio playback.
- Push notification on a second device.

## 7. Android Release Upload

The Google Play Console one-time registration fee has already been paid.

Already generated:

`dist/android/app-release.aab`

Before Play Console upload:

1. Create a new app in Google Play Console.
2. Enter app name, default language, app/game type, and free/paid status.
3. Complete app content, data safety, privacy policy URL, target age, and ads declarations.
4. Create an internal testing track.
5. Upload `dist/android/app-release.aab`.
6. Keep the upload key files safe:
   - `apps/mobile/android/app/upload-keystore.jks`
   - `apps/mobile/android/key.properties`
7. Do not delete or regenerate the upload key unless you intentionally rotate it.

## 8. iOS TestFlight

This requires macOS, Xcode, and an Apple Developer account.

Steps:

1. Open `apps/mobile/ios/Runner.xcworkspace` on macOS.
2. Set team signing for bundle ID `com.voicebeta.verbal`.
3. Add APNs key/certificate to Firebase Console.
4. Build archive in Xcode.
5. Upload to App Store Connect.
6. Distribute with TestFlight.

Firebase iOS app is already registered:

- Bundle ID: `com.voicebeta.verbal`
- App ID: `1:203811587610:ios:e953a69e5930e77720f3a3`
