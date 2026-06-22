# Google Play Submission Pack

Korean translation: `docs/ko/GOOGLE_PLAY_SUBMISSION.md`

Status date: 2026-06-19

This document captures the Google Play Console inputs that can be prepared
without a physical Android device. Final upload and review still require a Play
Console app record.

Manual console-entry checklist: `docs/PLAY_CONSOLE_MANUAL_CHECKLIST.md`
Reviewer app access instructions: `docs/PLAY_REVIEWER_ACCESS.md`
App content worksheet: `docs/PLAY_APP_CONTENT_WORKSHEET.md`
Android release verification guide: `docs/ANDROID_RELEASE_VERIFICATION.md`
Android real-device QA guide: `docs/ANDROID_REAL_DEVICE_QA.md`
FCM real-device QA guide: `docs/FCM_REAL_DEVICE_QA.md`
Public release gate guide: `docs/PUBLIC_RELEASE_GATE.md`
Launch consistency guide: `docs/LAUNCH_CONSISTENCY.md`

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
- Community Guidelines: `docs/COMMUNITY_GUIDELINES.md`
- Account/Data Deletion: `docs/DATA_DELETION_POLICY.md`
- Prepared Firebase Hosting paths:
  - Privacy policy: `/privacy`
  - Terms of service: `/terms`
  - Community guidelines: `/community-guidelines`
  - Account deletion request: `/account/delete`
  - Data deletion policy: `/data-deletion`

Use these public policy URLs in store forms:

- Privacy Policy URL: `https://verbal.chat/privacy`
- Terms URL: `https://verbal.chat/terms`
- Community/UGC Policy URL: `https://verbal.chat/community-guidelines`
- Account deletion URL: `https://verbal.chat/account/delete`
- Data deletion policy URL: `https://verbal.chat/data-deletion`

After connecting the purchased custom domain, the Play Console account deletion
URL should be:
`https://verbal.chat/account/delete`.

Keep the default Firebase Hosting URL as a fallback after deployment:
`https://voice-messenger-jangs-260522.web.app/account/delete`.

Support email for manual account deletion requests:
`support@verbal.chat` routes to `jangseo37@gmail.com` through Cloudflare Email
Routing.

## Internal Testing Notes

Use this Firebase Auth test account for emulator or internal smoke testing:

- Phone number: `+16505550101`
- SMS code: `123456`

This number is configured as a Firebase Auth test phone number. It does not send
real SMS and must not be used as a public support account.

## Release Artifact

- Latest Android App Bundle:
  `dist/android/app-release.aab`

## Automated Readiness Check

Run this before creating or updating the Play Console internal testing release:

```powershell
cd .\functions
npm run verify:hosted-policy-urls
npm run verify:preinternal
```

The Android release verifier checks package identity, Firebase package mapping,
release AAB freshness, build-output parity, version metadata, and upload-key
readability before the AAB is uploaded. It writes
`artifacts/android-release-verification-*.json` and
`artifacts/android-release-verification-latest.json`.

The launch readiness verifier checks the Android package/Firebase identity,
release AAB, public Hosting pages, account/data deletion URLs, store listing
files, policy documents, telemetry wiring, sign-up policy consent, hosted policy
URL checks, and registered validation scripts. The latest run on 2026-06-19 KST
passed with 219 checks and 0 failures. It writes a JSON artifact under
`artifacts/launch-readiness-*.json`.

The hosted policy URL verifier checks the public Play Console URLs and writes
`artifacts/hosted-policy-url-verification-latest.md`.

The Play Console pack generator writes copy/paste-ready JSON and Markdown under
`artifacts/play-console/verbal-play-console-pack-*.json` and
`artifacts/play-console/verbal-play-console-pack-*.md`. It includes app identity,
AAB size and SHA-256, policy URLs, support contact, store descriptions, Data
Safety summary, reviewer test-account access, App content worksheet summary,
screenshot checklist/candidates, validation artifact pointers, Android release
verification reference, real-device QA script reference, and manual remaining
steps.
The App content answers file includes a section-by-section console flow with
Korean/English Play Console labels, exact values/sources, and the evidence flag
that must be recorded after each section is saved.
The closed testing pack generator writes tester invitation copy, a tester-list
CSV template, daily QA tasks, feedback questions, issue template, and production
access evidence commands under `artifacts/play-console/closed-testing`.
If Korean text looks broken in Windows PowerShell, reopen the file with
`Get-Content -Encoding UTF8 ...` or use the generated Markdown in VS Code. The
launch readiness check also verifies that Korean store listing text contains
readable Hangul and no common mojibake markers.

The launch gate report writes `artifacts/launch-gate-latest.md` and separates
the decision for Internal testing upload from the decision for public user
exposure.
The manual evidence template writes
`artifacts/launch-manual-evidence.template.json`; copy it to
`artifacts/launch-manual-evidence.json` only when there is real Play Console or
real-device evidence to record.

The store asset generator writes upload-ready assets under
`artifacts/store/google-play/assets`: `app-icon-512.png`,
`feature-graphic-1024x500.png`, and five 1080x1920 phone screenshots.
The preinternal release check runs all local upload gates in sequence and writes
`artifacts/preinternal-release-check-latest.json`.
It also writes the launch handoff files
`artifacts/launch-handoff-latest.md` and
`artifacts/launch-handoff-latest.json`, which list the remaining Play Console
and real-device evidence commands in order.
It also verifies `artifacts/launch-consistency-latest.json` so the release AAB,
Play Console pack, launch gate, and handoff describe the same release candidate.
It also writes `artifacts/launch-status-latest.md`, a concise dashboard for the
current stage, next external evidence step, and remaining public exposure
blockers.

The public release gate is stricter and must fail until all Play Console and
real-device evidence is recorded:

```powershell
cd .\functions
npm run verify:public-release
```

Run it only before production/public exposure, not before Internal testing.

## Before Internal Testing Upload

- Create the app in Google Play Console.
  This creates the console record only; it does not make the app downloadable.
  Keep the package name, app signing key, and Firebase Android app mapping fixed
  before uploading the first release. Store listing text, screenshots, policy
  answers, and app functionality can still be updated through later store edits
  or new AAB uploads with higher `versionCode` values.
- Run `npm run verify:preinternal` and confirm Internal testing upload is
  allowed while public exposure remains blocked until Play Console and
  real-device evidence exists.
- Use the generated Play Console Markdown pack as the input worksheet.
- Use `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`
  if Play Console requires closed testing / production access evidence.
- Open `artifacts/launch-handoff-latest.md` and use it as the step-by-step
  handoff for Play Console, closed testing, real-device E2E, and FCM evidence.
- Open `artifacts/launch-status-latest.md` when you only need the current next
  external action.
- Confirm `artifacts/launch-consistency-latest.json` passed before using the
  generated Play Console pack.
- After Play Console or real-device work is complete, update
  `artifacts/launch-manual-evidence.json` through
  `npm run record:launch-evidence -- ...`, run
  `npm run verify:launch-evidence`, and rerun `npm run report:launch-gate`.
- Complete app access from `docs/PLAY_REVIEWER_ACCESS.md`.
- Complete ads, content rating, target audience, news, COVID-19, sensitive
  permissions, account deletion, and UGC declarations from
  `docs/PLAY_APP_CONTENT_WORKSHEET.md`.
- Complete Data Safety using `docs/GOOGLE_PLAY_DATA_SAFETY.md`.
- Confirm the hosted account deletion URL opens over HTTPS.
- Upload `dist/android/app-release.aab` to the Internal testing track.
- Add at least one internal tester email or Google Group.
- After the Pre-launch report is generated, review stability, performance,
  accessibility, screenshots, and blocking issues, then record it with
  `npm run record:prelaunch-reviewed -- --report-url "https://play.google.com/console/..."`.
- If Play Console requires production access testing, complete closed testing
  with at least 12 opted-in testers for at least 14 continuous days, or record
  why the requirement does not apply:
  `npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14`.

## Before Production Review

- Run Android real-device E2E testing.
- Capture real-device evidence with:
  `.\scripts\run-android-real-device-qa.ps1 -Interactive`
- Verify real SMS sign-in with a non-test phone number.
- Verify microphone recording and Deepgram transcript quality.
- Verify push notifications in foreground, background, and terminated states.
- Capture state-specific FCM evidence with:
  `.\scripts\run-fcm-real-device-qa.ps1`
- Verify voice retention expiry keeps transcript and removes audio.
- Confirm public policy URLs still open correctly and match the submitted build.
- Run `npm run verify:public-release` and continue only if it passes.
