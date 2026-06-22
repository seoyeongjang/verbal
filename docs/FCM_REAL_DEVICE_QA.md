# FCM Real Device QA

Korean translation: `docs/ko/FCM_REAL_DEVICE_QA.md`

Status date: 2026-06-19

This document defines the real Android device evidence required for the FCM
launch gate. Backend smoke tests already verify the server path and stale token
cleanup, but they do not prove that a real phone receives notifications in each
Android app state.

## Command

Run from the repository root:

```powershell
.\scripts\run-fcm-real-device-qa.ps1
```

Common options:

```powershell
# Check paths and generated artifacts without requiring a passing phone run.
.\scripts\run-fcm-real-device-qa.ps1 -DryRun

# Select a specific adb device.
.\scripts\run-fcm-real-device-qa.ps1 -DeviceId <adb-device-id>
```

Start the FCM QA with the phone awake and unlocked. The lock-screen delivery
state is tested later inside the script; if the phone is already on Android
keyguard/PIN at startup, the script records `device_unlocked_for_fcm_start:
false` and exits without waiting for push prompts that cannot be observed.

The script writes evidence under:

`artifacts/fcm-real-device/<run-id>/`

It also writes the latest machine-readable summary:

`artifacts/fcm-real-device-latest.json`

DryRun writes a separate setup-check summary:

`artifacts/fcm-real-device-dryrun-latest.json`

DryRun output never replaces the launch evidence summary.

The script also writes a bilingual Korean/English `manual-checklist.md` so the
tester can track the four notification states without cross-referencing this
document.

## Required States

The tester must verify all four states:

1. Foreground: Verbal is open and visible when the push arrives.
2. Background: Verbal is in the background when the push arrives.
3. Terminated: the app process is killed with `adb shell am kill`, not Android
   force-stop.
4. Lock screen: the phone is locked when the push arrives.

For each state the script captures screenshot, logcat, and notification dump
evidence, then records the tester's pass/fail answer.

## Launch Evidence

After a passing run, record it with:

```powershell
cd .\functions
npm run record:fcm-real-device -- --tester "Tester name" --device "Galaxy"
```

The launch evidence verifier accepts FCM only when the referenced JSON artifact
has `ok: true`, is not a DryRun, has a real device ID, and reports all four
states as true.
