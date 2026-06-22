# Play Console Manual Checklist

Korean translation: `docs/ko/PLAY_CONSOLE_MANUAL_CHECKLIST.md`

Status date: 2026-06-19

This checklist covers the Play Console steps that still require manual console
entry after the automated readiness checks pass.

Run these commands before using this checklist:

```powershell
cd .\functions
npm run verify:preinternal
```

Use the latest generated pack under
`artifacts/play-console/verbal-play-console-pack-*.md` as the source of truth
for copy/paste values and asset paths.
Use `artifacts/play-console/verbal-app-content-copy-sheet-latest.html` for
copy buttons while filling App content and Data Safety sections.
Use `artifacts/launch-gate-latest.md` as the current release gate summary.
Use `artifacts/next-external-step-latest.md` as the single current next-step
guide after each evidence update.
Use `artifacts/launch-manual-evidence.template.json` as the template for
recording completed Play Console and real-device evidence.

To open the current next-step guide, copy sheet, launch status, and Play Console
app URL together, run:

```powershell
cd .\functions
npm run open:next-launch-step
```

## Current State

- Google Play app record: completed.
- Package name: `com.voicebeta.verbal`.
- Internal testing AAB upload: completed.
- Internal testers: added in Play Console.
- Current stage: `google_play_internal_testing_uploaded`.
- Current next step: complete Google Play App content and Data Safety forms.
- Current single-step guide: `artifacts/next-external-step-latest.md`.
- Copy/paste HTML sheet:
  `artifacts/play-console/verbal-app-content-copy-sheet-latest.html`.
- Copy/paste answers:
  `artifacts/play-console/verbal-app-content-answers-latest.md`.

## 1. App Creation - Completed

- App name: `Verbal`
- Default language: Korean / `ko-KR`
- App or game: App
- Free or paid: Free
- Package name after AAB upload: `com.voicebeta.verbal`

Creating the app does not publish it to users. Users can download it only after
a release track is created, reviewed as required, and rolled out to testers or
production.

Decide the hard-to-change items before creating or uploading the first release:

| Item | Change after app creation | Launch guidance |
|---|---|---|
| Package name / `applicationId` | Effectively no. A different package is treated as a different app. | Keep `com.voicebeta.verbal`. |
| App signing / upload key | Possible only through key reset/recovery flows and operationally costly. | Use the verified release keystore and keep backups private. |
| Firebase Android app mapping | Possible, but changing it requires a new Firebase Android app config and build validation. | Keep the current `google-services.json` mapping. |
| App name, descriptions, screenshots, category | Yes. Update the store listing and submit changes for review if required. | Good enough for internal testing is sufficient. |
| App features and UI | Yes. Upload a new AAB with a higher `versionCode`. | Continue improving during Internal testing and Closed testing. |
| Data Safety and policy answers | Yes, but they must match the submitted build. | Update whenever data collection, permissions, ads, or UGC behavior changes. |

## 2. Store Listing

- Short description: use the generated pack.
- Full description: use the generated pack.
- App icon: `artifacts/store/google-play/assets/app-icon-512.png`
- Feature graphic:
  `artifacts/store/google-play/assets/feature-graphic-1024x500.png`
- Phone screenshots:
  `artifacts/store/google-play/assets/phone-screenshots/*.png`
- Category: Communication
- Contact email: `support@verbal.chat`
- Website: `https://verbal.chat`
- Privacy Policy: `https://verbal.chat/privacy`

## 3. Policy URLs

- Terms of Service: `https://verbal.chat/terms`
- Community Guidelines / UGC Policy:
  `https://verbal.chat/community-guidelines`
- Account deletion URL: `https://verbal.chat/account/delete`
- Data deletion policy: `https://verbal.chat/data-deletion`

## 4. App Content Declarations

- Data Safety: complete from `docs/GOOGLE_PLAY_DATA_SAFETY.md`.
- Ads: select no ads unless an ad SDK or production ad placement is enabled in
  the submitted build.
- App access / sign-in details: complete from
  `docs/PLAY_REVIEWER_ACCESS.md` and provide the Firebase test phone
  credentials `+16505550101` / `123456`.
- Target audience: select the intended audience only after policy review. If
  minors are included, additional youth and content-policy review is required.
- Content rating: answer based on messaging/UGC, user interaction, location
  sharing, and report/block safety controls.
- News apps and government apps: select no unless the app scope changes.
- App content worksheet: use `docs/PLAY_APP_CONTENT_WORKSHEET.md` for ads,
  app access, Data Safety, account deletion, target audience, content rating,
  sensitive permissions, UGC, government app, financial features, health, app
  category/contact details, store listing, and special category declarations.
- After saving App content, record the evidence with
  `npm run record:app-content-submitted`.

## 5. Internal Testing Release - Uploaded

- Upload AAB: `dist/android/app-release.aab`
- Confirm package name: `com.voicebeta.verbal`
- Release notes: use the generated pack.
- Add internal testers by email or Google Group.
- Current status: AAB uploaded and tester Gmail added.
- After upload, review Play Console warnings for signing, permissions, SDK
  versions, privacy, and policy issues.
- When the Pre-launch report is generated, review Stability, Performance,
  Accessibility, Screenshots, and blocking issues before wider testing.
- Record the Pre-launch report review with
  `npm run record:prelaunch-reviewed -- --report-url "https://play.google.com/console/..."`.
- If Play Console requires production access testing, run closed testing with at
  least 12 opted-in testers for at least 14 continuous days before applying for
  production access. Official reference:
  `https://support.google.com/googleplay/android-developer/answer/14151465`.
- Record closed testing completion with
  `npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14`.
- If Play Console confirms this requirement does not apply to the account/app,
  record the exception with
  `npm run record:closed-testing-not-required -- --reason "..."`.
- Confirm `artifacts/launch-gate-latest.md` still says Internal testing upload
  is allowed.
- Record the upload with
  `npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group "..."`.
  The recorder fills the AAB SHA-256 and version code from the latest release
  verification; confirm those values match the uploaded AAB before recording
  the evidence.
- After recording evidence, run `npm run verify:launch-evidence` to confirm the
  required fields are complete before rerunning the launch gate report.

## 6. Required Verification Before Wider Testing

- Real Android device SMS sign-in with a non-test phone number.
- Microphone permission and voice recording.
- Voice STT transcript quality and latency.
- Voice playback from Firebase Storage.
- FCM push in foreground, background, terminated, and lock-screen states.
- Account deletion entry point.
- Report/block flows.
- Audio retention expiry with transcript preserved.

## 7. Known Manual-Only Items

- Play Console app record creation. Completed for `Verbal`.
- Data Safety form submission.
- Internal testing upload and tester rollout. Completed for the current
  `1 (1.0.0)` AAB.
- Play Console Pre-launch report review.
- Closed testing / production access readiness.
- Real-device E2E verification.
- iOS APNs/TestFlight setup if iOS launch is in scope.
