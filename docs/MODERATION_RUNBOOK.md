# Moderation Runbook

Korean translation: `docs/ko/MODERATION_RUNBOOK.md`

## Scope

This runbook covers reports submitted through `reportMessage` and `reportRoom`.
Reports are stored in `reports/{reportId}` and deduplicated by reporter and
target. Normal message and voice usage is not capped.

## Report Fields

- `reporterId`
- `targetType`: `message` or `room`
- `targetId`
- `roomId`
- `messageId` for message reports
- `reason`: `spam`, `abuse`, `unsafe`, or `other`
- `details`
- `status`: `open`, `reviewing`, `actioned`, or `dismissed`
- `count`
- `createdAt`, `updatedAt`

## Review Flow

- Triage open reports daily during closed beta.
- Prioritize `unsafe`, repeated `abuse`, and rooms with many reporters.
- Inspect only the minimum room/message context needed to decide.
- Mark reports as `reviewing` when an operator starts review.
- Mark as `actioned` after blocking, warning, room removal, or escalation.
- Mark as `dismissed` only when no policy issue is found.

## Actions

- Message issue: ask sender to delete, remove through admin tooling when built,
  or preserve as evidence if severe.
- Room issue: disable invite link, require invite approval, remove members, or
  close the room.
- User issue: block account, disable phone login, or escalate to legal/safety.

## Abuse Controls

- Invite creation, invite join, report, and block actions have cooldowns.
- Text count, voice count, and voice duration are not capped by product policy.
- Provider quota, budget alerts, and anomaly monitoring must protect cost and
  abuse risk before public launch.
