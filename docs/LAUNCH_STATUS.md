# Launch Status Dashboard

Korean translation: `docs/ko/LAUNCH_STATUS.md`

Status date: 2026-06-19

This document describes the concise generated status dashboard used between
local preinternal readiness and the remaining external Play Console / real
device work.

## Purpose

The launch status dashboard gives one current answer to:

- Whether Verbal can be uploaded to Google Play Internal testing.
- Whether Verbal is still blocked from general public exposure.
- Which external evidence step should be done next.
- Which artifact should be used for Play Console copy/paste work.

It is intentionally shorter than `artifacts/launch-handoff-latest.md`. Use the
status file for a quick current-state check, and the handoff file for the full
step-by-step external sequence.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run status:launch
```

The preinternal release check also runs this automatically:

```powershell
cd .\functions
npm run verify:preinternal
```

## Output

The command writes:

- `artifacts/launch-status-<run-id>.json`
- `artifacts/launch-status-<run-id>.md`
- `artifacts/launch-status-latest.json`
- `artifacts/launch-status-latest.md`

## How To Use

1. Open `artifacts/launch-status-latest.md`.
2. Read `Current Stage`.
3. Follow `Next External Step`.
4. After completing that external step, run the shown
   `npm run record:launch-evidence -- ...` command.
5. Run:

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
npm run status:launch
```

Do not expose Verbal to general public users until
`readyForPublicUserExposure` is true in `artifacts/launch-gate-latest.json`.
