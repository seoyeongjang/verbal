# Closed Testing Runbook

Korean translation: `docs/ko/CLOSED_TESTING_RUNBOOK.md`

Status date: 2026-06-19

This runbook prepares Verbal for Google Play closed testing and production
access evidence. It does not publish the app.

## Generate The Pack

Run from the repository root:

```powershell
cd .\functions
npm run prepare:closed-testing-pack
```

The command writes:

- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`
- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.json`
- `artifacts/play-console/closed-testing/tester-list-template.csv`

## When To Use It

Use the pack after the Play Console app is created and the AAB is uploaded to
Internal testing. If Play Console requires production access testing, use it to
run a controlled closed test before public exposure.

If Play Console says the account/app is not subject to the closed-testing
production access requirement, record the non-required reason instead of
inventing test evidence.

## Operating Rules

- Use the latest AAB already verified by `npm run verify:preinternal`.
- Add at least 12 opted-in testers if Play Console requires the production
  access closed test.
- Keep the closed test active for at least 14 continuous days if required.
- Collect feedback before recording the closed-testing gate as complete.
- Triage blocking issues before applying for production access.
- Do not mark the launch gate as complete until the evidence exists.

## Evidence Recording

Required closed testing:

```powershell
npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>
```

Not required:

```powershell
npm run record:closed-testing-not-required -- --reason "<reason>"
```

Then run:

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
```

The public exposure gate must remain red until Play Console, real-device E2E,
FCM, Pre-launch report, and App content/Data Safety evidence are all recorded.
