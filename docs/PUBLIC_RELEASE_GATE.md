# Public Release Gate

Korean translation: `docs/ko/PUBLIC_RELEASE_GATE.md`

Status date: 2026-06-19

This document describes the hard gate that must pass before Verbal is exposed
to general public users through a production Play Store rollout.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run verify:public-release
```

The equivalent alias below is also registered, so either command checks the same
hard gate:

```powershell
npm run verify:public-release-gate
```

## Expected Behavior

Before Play Console and real-device evidence is recorded, this command must
fail. That failure is intentional and protects against accidental production
exposure while launch blockers still exist.

The command runs:

1. `npm run verify:launch-evidence`
2. `npm run report:launch-gate`

Then it checks that `readyForPublicUserExposure` is true and that the latest
launch gate has no blockers.

## Output

The command writes:

- `artifacts/public-release-gate-<run-id>.json`
- `artifacts/public-release-gate-latest.json`

## Passing Criteria

The command passes only when all of these are true:

- Strict launch evidence verification passes.
- `artifacts/launch-gate-latest.json` exists.
- `readyForPublicUserExposure` is true.
- The launch gate blocker list is empty.

## When To Use

Use this command only before a production or public user exposure step. It is
not required for Google Play Internal testing upload, where
`npm run verify:preinternal` is the correct gate.

Do not continue to production rollout if this command fails.
