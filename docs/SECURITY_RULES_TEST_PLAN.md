# Security Rules Test Plan

Korean translation: `docs/ko/SECURITY_RULES_TEST_PLAN.md`

## Firestore Allow Cases

- Signed-in users can read user profiles.
- A user can create/update their own `users/{uid}` profile with valid handle
  fields only.
- A user can create/update/delete their own `handles/{handle}` reservation.
- Room participants can read their rooms, messages, members, and pins.
- Room managers can read join requests.
- The request owner can read their own join request.

## Firestore Deny Cases

- Anonymous users cannot read or write app data.
- Clients cannot directly create rooms, messages, members, pins, reports,
  usage, cooldowns, or transcription drafts.
- Users cannot reserve invalid handles.
- Users cannot write another user's profile, token, handle, or join request.
- Non-participants cannot read room data.

## Storage Allow Cases

- Users can upload and read their own voice drafts.
- Room participants can read voice messages and attachments for their rooms.
- Clients upload voice audio only as `voice_drafts/{uid}/...`; callable
  Functions copy approved audio into `voice_messages/{roomId}/...` after room
  participant validation.
- Attachment upload size and content type must match the Storage rules.

## Storage Deny Cases

- Anonymous users cannot read or write files.
- Users cannot upload drafts into another user's path.
- Clients cannot write sent voice-message objects directly.
- Users cannot write attachments under another user's UID path.
- Clients cannot delete sent voice messages or sent attachments directly.

## Required Before Launch

Run emulator allow/deny tests after each release-bound Storage rule change:
`npm run rules:test`. The current source rules and production rules passed this
test on 2026-05-28.
