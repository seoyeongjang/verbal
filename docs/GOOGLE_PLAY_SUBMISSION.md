# Google Play Submission Pack

Korean translation: `docs/ko/GOOGLE_PLAY_SUBMISSION.md`

Status date: 2026-05-28

This document captures the Google Play Console inputs that can be prepared
without a physical Android device. Final upload and review still require a Play
Console app record.

## App Identity

- App name: Verbal
- Default language: Korean
- App type: App
- Category: Communication
- Package name: `com.voicebeta.verbal`
- Firebase project: `voice-messenger-jangs-260522`
- Android Firebase App ID: `1:203811587610:android:60b60d74b332290520f3a3`

## Store Listing Draft

Prepared files:

- Korean short description:
  `artifacts/store/google-play/ko-KR/short-description.txt`
- Korean full description:
  `artifacts/store/google-play/ko-KR/full-description.txt`
- Korean internal testing release notes:
  `artifacts/store/google-play/ko-KR/release-notes-internal.txt`
- English short description:
  `artifacts/store/google-play/en-US/short-description.txt`
- English full description:
  `artifacts/store/google-play/en-US/full-description.txt`
- English internal testing release notes:
  `artifacts/store/google-play/en-US/release-notes-internal.txt`

## Privacy And Policy URLs

Play Console requires public web URLs, not local files. Before production
review, publish these documents and paste their public URLs into Play Console:

- Privacy Policy: `docs/PRIVACY_POLICY.md`
- Terms of Service: `docs/TERMS_OF_SERVICE.md`
- Account/Data Deletion: `docs/DATA_DELETION_POLICY.md`

## Internal Testing Notes

Use this Firebase Auth test account for emulator or internal smoke testing:

- Phone number: `+16505550101`
- SMS code: `123456`

This number is configured as a Firebase Auth test phone number. It does not send
real SMS and must not be used as a public support account.

## Release Artifact

- Latest Android App Bundle:
  `dist/android/app-release.aab`

## Before Internal Testing Upload

- Create the app in Google Play Console.
- Complete app access, ads, content rating, target audience, news, and COVID-19
  declarations.
- Complete Data Safety using `docs/GOOGLE_PLAY_DATA_SAFETY.md`.
- Upload `dist/android/app-release.aab` to the Internal testing track.
- Add at least one internal tester email or Google Group.

## Before Production Review

- Run Android real-device E2E testing.
- Verify real SMS sign-in with a non-test phone number.
- Verify microphone recording and Deepgram transcript quality.
- Verify push notifications in foreground, background, and terminated states.
- Verify voice retention expiry keeps transcript and removes audio.
- Replace local policy references with public URLs.
