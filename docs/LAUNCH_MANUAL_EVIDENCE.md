# Launch Manual Evidence

Korean translation: `docs/ko/LAUNCH_MANUAL_EVIDENCE.md`

Status date: 2026-06-19

Some launch gates cannot be proven by local code because they happen inside
Google Play Console or on real Android devices. Use the manual evidence file to
record those completed steps in a structured way.

## Create The Template

Run from the repository root:

```powershell
cd .\functions
npm run prepare:launch-evidence
```

This writes:

- `artifacts/launch-manual-evidence.template.json`

If an Android release verification artifact exists, the template pre-fills the
current `versionCode`, `aabSha256`, and release name for the Internal testing
upload evidence. It still leaves every `done` field as `false`; only change
those fields after the external evidence exists.

Copy it to:

- `artifacts/launch-manual-evidence.json`

Then update only the fields that are backed by real evidence.

## Record Evidence By Command

Prefer the recorder over hand-editing JSON:

```powershell
cd .\functions
npm run record:launch-evidence -- init
npm run record:launch-evidence -- status
```

`status` prints the remaining evidence gates plus the exact command to run
after each Play Console or real-device task is actually completed. Do not use
those commands to mark assumed work as done; record only completed external
evidence.

Use the matching command only after the external step is complete:

```powershell
npm run record:launch-evidence -- play-app-created --created-at now --console-url https://play.google.com/console/...
npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group "owner@example.com"
npm run record:app-content-submitted
npm run record:prelaunch-reviewed -- --report-url https://play.google.com/console/...
npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14
npm run record:closed-testing-not-required -- --reason "Organization account does not require production access closed test"
npm run record:real-device-e2e -- --tester "Tester name" --device-model "Galaxy"
npm run record:fcm-real-device -- --tester "Tester name" --device "Galaxy"
```

The shortcut recorders call the strict recorder internally, refresh the launch
gate/status/next-step/handoff artifacts, and reject evidence when the referenced
real-device or FCM artifact does not exist or reports a DryRun/failed state. For
App content evidence, the recorder also requires the latest generated App
content answer pack to include the Data Safety quick answers, detailed Play
Console matrix, Korean console labels, and UGC controls, and requires the latest
hosted policy URL verification to be passing.

## Evidence Rules

- `playConsole.appCreated.done` can be true only after the Play Console app
  record exists.
- `playConsole.internalTestingUpload.done` can be true only after
  `dist/android/app-release.aab` is uploaded to the Internal testing track.
- `playConsole.preLaunchReportReviewed.done` can be true only after the Google
  Play Pre-launch report is generated and stability, performance,
  accessibility, screenshot, and blocking-issue results have been reviewed.
- `playConsole.closedTestingCompleted.done` can be true after the required
  closed test is complete, or after Play Console confirms the account/app is not
  subject to the closed-test production access requirement. For newly created
  personal developer accounts, Google's current requirement is at least 12
  opted-in testers for 14 continuous days before applying for production access:
  `https://support.google.com/googleplay/android-developer/answer/14151465`.
- `playConsole.appContentSubmitted.done` can be true only after Privacy Policy,
  App access, Ads, Data Safety, account deletion, data deletion, Content rating,
  Target audience, Sensitive permissions, UGC, Government app, Financial
  features, Health, App category/contact, and Store listing sections are saved
  in Play Console. The recorder also checks that
  `artifacts/play-console/verbal-app-content-answers-latest.md` and
  `artifacts/hosted-policy-url-verification-latest.json` are current enough to
  support that evidence.
- `realDevice.e2e.done` can be true only after real-device QA has been run with
  a connected Android device, not DryRun.
- `realDevice.fcm.done` can be true only after foreground, background,
  terminated, and lock-screen push delivery have been verified.

After updating the evidence file, run:

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
```

The evidence verifier reports the exact missing fields. The launch gate report
then reads `artifacts/launch-manual-evidence.json` and closes the matching gates
only when the required evidence fields are complete.
