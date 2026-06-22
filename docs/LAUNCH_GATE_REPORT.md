# Launch Gate Report

Korean translation: `docs/ko/LAUNCH_GATE_REPORT.md`

Status date: 2026-06-19

Use this report immediately before Play Console work or wider tester rollout.
It consolidates the latest automated artifacts and makes two separate calls:

- whether Verbal is ready for Google Play Internal testing upload;
- whether Verbal is ready for public user exposure.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run prepare:launch-evidence
npm run report:launch-gate
```

The command writes:

- `artifacts/launch-gate-<run-id>.json`
- `artifacts/launch-gate-<run-id>.md`
- `artifacts/launch-gate-latest.json`
- `artifacts/launch-gate-latest.md`

If external Play Console or real-device evidence exists, record it with
`npm run record:launch-evidence -- <command>`. Then run
`npm run verify:launch-evidence` before running the report again.

## Gate Logic

Internal testing upload can proceed when these local gates pass:

- latest launch readiness artifact is passing;
- latest Android release verification artifact is passing;
- Play Console copy/paste pack exists.

Public user exposure remains blocked until these external/manual gates are also
closed:

- Google Play Console app record created;
- AAB uploaded to Internal testing;
- Google Play Pre-launch report reviewed with no blocking issues;
- closed testing / production access readiness recorded, or a Play Console
  non-required reason recorded;
- Data Safety and App content forms submitted;
- Android real-device E2E run with a connected device, not DryRun;
- FCM foreground/background/terminated/lock-screen delivery verified.

## Notes

This script does not publish anything. It only summarizes current evidence and
remaining blockers.
