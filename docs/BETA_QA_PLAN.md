# Beta QA Plan

Korean translation: `docs/ko/BETA_QA_PLAN.md`

## Device Matrix

- Small Android phone.
- Large Android phone.
- Low-end Android device.
- Android 13+ notification permission device.
- Slow network and reconnect scenario.
- iOS/TestFlight device if iOS is in scope.

## Core Scenarios

- Phone auth, profile setup, handle validation.
- Create direct room and group room.
- Send, edit, delete, reply, react, pin, and search messages.
- Record voice and verify automatic send after STT succeeds.
- STT failure recovery: retry STT and manual transcript send.
- Send image, file, and location.
- Schedule a message with no default preset.
- Translate a message.
- Create invite link/QR, join, approve, reject, revoke.
- Change group roles, remove member, leave room.
- Report message, report room, block user.
- Export my data and delete account.

## Acceptance

- No broken Korean text.
- No clipped button or bubble text at 360px width.
- Voice transcript remains after audio retention expiry.
- User can retry failed sends without restarting the app.
- App shows a clear sending/progress state for voice and attachments.
- No private chat ad placement.
