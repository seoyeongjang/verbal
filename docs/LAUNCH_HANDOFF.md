# Launch Handoff

Korean translation: `docs/ko/LAUNCH_HANDOFF.md`

Status date: 2026-06-19

This document explains the generated handoff file used after local preinternal
checks pass and before Verbal is exposed to general public users.

## Purpose

The launch handoff consolidates the current release artifact, readiness
artifacts, Play Console pack, closed testing pack, manual evidence status, and
the exact external evidence commands into one file.

It does not prove that Play Console, real-device, or FCM work is complete. It
only makes the remaining external sequence explicit so the next person can
continue without reopening every launch document.

For a shorter current-state summary, use `artifacts/launch-status-latest.md`.

## Command

Run from the repository root:

```powershell
cd .\functions
npm run prepare:launch-handoff
```

The preinternal release check also runs this automatically:

```powershell
cd .\functions
npm run verify:preinternal
```

## Output

The command writes:

- `artifacts/launch-handoff-<run-id>.json`
- `artifacts/launch-handoff-<run-id>.md`
- `artifacts/launch-handoff-latest.json`
- `artifacts/launch-handoff-latest.md`

The preinternal release check also writes `artifacts/launch-status-latest.md`
after the handoff and consistency checks pass.

## What It Includes

- Internal testing upload readiness.
- Public user exposure readiness.
- Current public exposure blockers.
- Release AAB path.
- Android release verification path.
- Launch readiness report path.
- Launch gate report path.
- Play Console submission pack path.
- Closed testing pack path.
- Manual launch evidence path.
- Store asset path.
- Public policy URLs for privacy, account deletion, and data deletion.
- Step-by-step external evidence sequence:
  - `play-app-created`
  - `internal-testing-upload`
  - `app-content-submitted`
  - `prelaunch-reviewed`
  - `closed-testing-completed`
  - `real-device-e2e`
  - `fcm`

## How To Use

1. Open `artifacts/launch-handoff-latest.md`.
2. Follow the external work sequence from top to bottom.
3. After each external step, run the matching
   `npm run record:launch-evidence -- ...` command.
4. Run:

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
npm run prepare:launch-handoff
```

5. Continue only when the launch gate says the next exposure level is allowed.

Do not expose Verbal to general public users until
`readyForPublicUserExposure` is true in `artifacts/launch-gate-latest.json`.
