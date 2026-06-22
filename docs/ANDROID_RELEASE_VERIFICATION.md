# Android Release Verification

Korean translation: `docs/ko/ANDROID_RELEASE_VERIFICATION.md`

Status date: 2026-06-19

This document defines the local Android release gate that should pass before
uploading an AAB to Google Play Internal testing.

## Command

Run from the repository root:

```powershell
.\scripts\verify-android-release-artifact.ps1
```

The script writes:

- `artifacts/android-release-verification-<run-id>.json`
- `artifacts/android-release-verification-latest.json`

## What It Verifies

- Android package name is `com.voicebeta.verbal`.
- Android namespace matches the package name.
- `google-services.json` package name matches the Android package.
- Firebase project/app IDs are present.
- `pubspec.yaml` version contains both version name and version code.
- `dist/android/app-release.aab` exists and is plausibly sized.
- `dist/android/app-release.aab` matches the Gradle build output AAB.
- Release AAB is newer than app source files.
- `key.properties` and `upload-keystore.jks` exist.
- Release build will not fall back to debug signing.
- `keytool` can read the upload key and produce SHA-1/SHA-256 fingerprints.

## Why This Matters

Google Play accepts updates only when the package identity, versioning, and
signing relationship are correct. Catching these issues locally avoids wasting a
Play Console upload/review cycle.

## Required Follow-Up

Keep the upload keystore and `key.properties` backed up securely. Do not commit
passwords to public repositories. If the app has already been uploaded to Play
Console, do not replace the upload key unless intentionally rotating it through
Google Play App Signing.
