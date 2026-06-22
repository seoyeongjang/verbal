# Preinternal Release Check

Korean translation: `docs/ko/PREINTERNAL_RELEASE_CHECK.md`

Status date: 2026-06-19

Use this command immediately before creating or updating the Google Play
Internal testing release. It does not publish, upload, or modify Play Console.
It only runs local checks and writes an evidence artifact.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run verify:preinternal
```

The command runs these steps in order:

1. `npm run build`
2. `npm run prepare:play-store-assets`
3. `npm run verify:android-release`
4. `npm run verify:launch-readiness`
5. `npm run prepare:play-console-pack`
6. `npm run prepare:closed-testing-pack`
7. `npm run prepare:launch-evidence`
8. `npm run verify:launch-evidence -- --allow-missing`
9. `npm run report:launch-gate`
10. `npm run prepare:launch-handoff`
11. `npm run verify:launch-consistency`
12. `npm run status:launch`

The `--allow-missing` mode is intentionally used here because Play Console and
real-device evidence is expected to be missing or incomplete before Internal
testing upload. The strict command, `npm run verify:launch-evidence`, must still
fail until those external steps are recorded.

## Output

The command writes:

- `artifacts/preinternal-release-check-<run-id>.json`
- `artifacts/preinternal-release-check-latest.json`
- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`
- `artifacts/play-console/closed-testing/tester-list-template.csv`
- `artifacts/launch-handoff-latest.md`
- `artifacts/launch-handoff-latest.json`
- `artifacts/launch-consistency-latest.json`
- `artifacts/launch-status-latest.md`
- `artifacts/launch-status-latest.json`

The check passes when all local gates required for Google Play Internal testing
upload pass and the launch gate says `readyForInternalTestingUpload: true`.

It is expected that `readyForPublicUserExposure` remains false before Play
Console evidence, Pre-launch report review, closed testing / production
access readiness, real-device E2E, and FCM evidence exist.

## Next Step After Passing

After this command passes:

1. Create the Play Console app record.
2. Upload `dist/android/app-release.aab` to Internal testing.
3. Complete App content and Data Safety forms.
4. Review the generated Google Play Pre-launch report.
5. Complete closed testing if Play Console requires it, or record the
   non-required reason.
6. Confirm `artifacts/launch-consistency-latest.json` passed.
7. Open `artifacts/launch-handoff-latest.md` and follow the exact external
   evidence commands listed there.
8. Open `artifacts/launch-status-latest.md` for the concise next action.
9. Record completed evidence with `npm run record:launch-evidence -- <command>`.
10. Run `npm run verify:launch-evidence`.
11. Run `npm run report:launch-gate`.
