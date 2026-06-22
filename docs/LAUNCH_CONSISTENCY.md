# Launch Consistency Check

Korean translation: `docs/ko/LAUNCH_CONSISTENCY.md`

Status date: 2026-06-19

This document describes the consistency check that verifies the latest release
AAB, Android release verification, Google Play Console pack, launch gate, and
launch handoff all describe the same release candidate.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run verify:launch-consistency
```

The preinternal release check also runs this automatically after the launch
handoff is generated:

```powershell
npm run verify:preinternal
```

## Output

The command writes:

- `artifacts/launch-consistency-<run-id>.json`
- `artifacts/launch-consistency-latest.json`

## What It Checks

- `dist/android/app-release.aab` SHA-256 and size match the latest Play Console
  pack.
- The latest Android release verification SHA-256 and size match the current
  AAB.
- The Play Console pack package name and Firebase App ID match the Android
  release verification.
- The launch handoff policy URLs match the Play Console pack URLs.
- The launch handoff points to existing Play Console and closed testing packs.
- The launch handoff points to the latest timestamped Play Console and closed
  testing packs, not stale generated files.
- Launch handoff readiness/blocker status matches `artifacts/launch-gate-latest.json`.
- The Play Console pack uses the public `verbal.chat` policy URLs and
  `support@verbal.chat`.

## When To Use

Use this before Play Console upload or any public exposure step. It catches
stale generated files, stale AAB metadata, and mismatched handoff instructions.

If this command fails, regenerate the Play Console pack, launch gate, and
handoff with `npm run verify:preinternal` before continuing.
