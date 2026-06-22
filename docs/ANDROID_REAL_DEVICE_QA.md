# Android Real Device QA

Korean translation: `docs/ko/ANDROID_REAL_DEVICE_QA.md`

Status date: 2026-06-19

This document defines the real-device QA gate before Verbal is exposed to
general users. Emulator and backend smoke tests are already useful, but they do
not prove real SMS, microphone capture, Android notification behavior, native
permission prompts, or device-specific rendering.

## Scripted Evidence Capture

Before the manual E2E run, use the lightweight precheck to confirm the PC can
see the phone, Verbal is installed, the version matches the current release, and
permission state is known:

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run verify:android-device-precheck
```

The precheck writes `artifacts/android-real-device-precheck-latest.json`. This
is useful setup evidence, but it does not satisfy the real-device E2E launch
gate because it does not prove the manual user workflow.
If the phone is locked, sleeping, or dozing, the precheck will still collect
device/package data but will warn that screenshots and permission prompts may
not be visible.

Before running the interactive QA script, wake and unlock the phone so the
launcher and Verbal UI are visible. If Android keyguard/PIN is still active,
the QA script records `device_unlocked_for_qa: false`, skips Verbal UI capture,
and leaves the E2E gate open instead of saving a misleading black screenshot.

Use the QA helper from the repository root:

```powershell
.\scripts\run-android-real-device-qa.ps1
```

Common options:

```powershell
# Check paths and connected devices without requiring a phone.
.\scripts\run-android-real-device-qa.ps1 -DryRun

# Select a specific adb device.
.\scripts\run-android-real-device-qa.ps1 -DeviceId <adb-device-id>

# Build/install a debug APK before launch capture.
.\scripts\run-android-real-device-qa.ps1 -InstallDebug

# Pause while the tester completes the manual flow, then collect final evidence.
.\scripts\run-android-real-device-qa.ps1 -Interactive
```

FCM push delivery has its own state-specific evidence script:

```powershell
.\scripts\run-fcm-real-device-qa.ps1
```

The script writes evidence under:

`artifacts/android-real-device-qa/<run-id>/`

It captures:

- `device.json`: device model, Android version, screen size, and selected device.
- `manual-checklist.md`: bilingual Korean/English manual pass/fail checklist
  for the tester.
- `launch.png`: launch screenshot.
- `window.xml`: Android UIAutomator dump.
- `logcat.txt`: device logs after launch or interactive QA.
- `result.json`: machine-readable script result.
- `artifacts/android-real-device-qa-latest.json`: latest real, non-DryRun run
  summary.
- `artifacts/android-real-device-qa-dryrun-latest.json`: latest DryRun setup
  check summary. This is intentionally separated from launch evidence.

The launch evidence recorder only accepts a real-device E2E artifact when the
interactive script recorded `manual_e2e_confirmed`. A precheck or dry run cannot
close the public exposure gate.
DryRun output never replaces `artifacts/android-real-device-qa-latest.json`.

## Required Manual Checks

The tester must complete and mark the generated `manual-checklist.md`.
The generated checklist is intentionally bilingual so it can be used directly
while testing a Korean Verbal build on the phone.

Required flow:

1. Install or launch Verbal.
2. Sign in with a real SMS phone number, not only a Firebase test number.
3. Confirm required Terms, Privacy Policy, and Community Guidelines consent.
4. Complete profile setup and user ID reservation.
5. Create a direct room.
6. Send, edit, and delete a text message.
7. Grant microphone permission and send a voice message.
8. Confirm the voice transcript appears without broken Korean text.
9. Play the voice message.
10. Send file and location messages.
11. Schedule a message without a default preset.
12. Translate a message.
13. Create, edit, and delete a calendar event.
14. Create a chat calendar proposal, vote, and finalize it.
15. Create an open-chat invite link, join, and leave.
16. Report a message and block a user.
17. Open the account deletion entry point.

FCM foreground, background, terminated, and lock-screen delivery are verified
with `scripts/run-fcm-real-device-qa.ps1` and recorded as a separate launch
evidence artifact.

## Pass Criteria

- No broken Korean text is visible in chat, STT, calendar, policy, or menu UI.
- Voice message bubble appears quickly after tapping send.
- Voice transcript is present or a clear recoverable STT failure state is shown.
- Voice playback works from Firebase Storage.
- FCM push evidence is collected separately with
  `scripts/run-fcm-real-device-qa.ps1` and all four delivery states pass.
- User can recover from failed sends without restarting the app.
- Account deletion and data deletion URLs are reachable from the app.

## Relationship To Automated Checks

The following commands should pass before real-device QA:

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run verify:launch-readiness
npm run smoke:prod-e2e
```

Real-device QA is still required after those commands pass because the backend
smoke test uses Firebase test phone numbers and synthetic audio.
