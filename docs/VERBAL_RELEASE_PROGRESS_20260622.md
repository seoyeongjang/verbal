# Verbal Release Progress - 2026-06-22

This document records the current Verbal launch preparation state before public user exposure.

## Completed

- Renamed the app and release materials to Verbal.
- Prepared and uploaded the Android release AAB to Google Play internal testing.
- Created the Google Play Console app for package `com.voicebeta.verbal`.
- Completed Google Play App content and Data Safety declarations.
- Published policy pages on `https://verbal.chat`, including:
  - Privacy Policy: `https://verbal.chat/privacy`
  - Terms of Service: `https://verbal.chat/terms`
  - Community Guidelines: `https://verbal.chat/community-guidelines`
  - Account deletion: `https://verbal.chat/account/delete`
  - Data deletion: `https://verbal.chat/data-deletion`
- Configured Play reviewer access with the Firebase test phone account.
- Saved Pre-launch report settings with reviewer credentials.
- Recorded App content/Data Safety completion in local launch evidence.

## Product And Backend Updates Included

- Voice messaging, STT transcript handling, pending voice message finalization, and audio retention workflows.
- Calendar events, voice calendar creation, calendar reminders, morning briefing, external calendar integration, holiday support, and chat calendar proposals.
- Messaging UX improvements including edited/deleted messages, pinned message behavior, message sizing, playback controls, and chat scrolling behavior.
- Home menu and settings IA updates, including profile, requests, support, policies, data/storage, privacy/security, language/theme, and account management surfaces.
- Open chat invitation and link-sharing support.
- Firebase Functions, Firestore rules, Storage rules, launch verification scripts, and Play Console support artifacts.
- Plugin platform planning and initial service/API scaffolding.

## Verification Run

- `npm run record:app-content-submitted`
  - Result: App content gate recorded as complete.
- `npm run status:launch`
  - Current stage: `google_play_internal_testing_uploaded`
  - Next step: `Review Google Play Pre-launch report`
- `npm run verify:launch-evidence`
  - Expected incomplete result until external evidence is recorded.
- `npm run verify:public-release-gate`
  - Expected failure because public exposure is still blocked.

## Remaining Public Exposure Blockers

1. `play_prelaunch_report_reviewed`
   - Wait for Google Play Pre-launch report generation.
   - Review stability, performance, accessibility, and screenshots.
   - Record evidence with:
     `npm run record:prelaunch-reviewed -- --report-url <https-url>`
2. `play_closed_testing_completed`
   - Complete closed testing or record Play Console's non-required reason.
3. `android_real_device_e2e_verified`
   - Run full real-device E2E QA.
4. `fcm_real_device_delivery_verified`
   - Verify FCM foreground, background, terminated, and lock-screen delivery.

## Current Decision

The app is ready for internal testing workflows, but not ready for public user exposure. Public rollout must remain blocked until the four remaining external gates above are completed and `npm run verify:public-release-gate` passes.
