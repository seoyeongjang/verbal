# Data Deletion Policy

Korean translation: `docs/ko/DATA_DELETION_POLICY.md`

## User-Facing Policy

- Users can request account deletion from
  `Menu -> Account management -> 계정 삭제`.
- Account deletion removes the user's handle reservation, push tokens, profile
  display data, and active room membership.
- Messages already sent to other users are kept for conversation continuity, but
  the sender is marked as deleted and the account profile is anonymized.
- Voice audio follows the room retention period. After expiry, audio is deleted
  and transcript text remains.
- Users can delete individual sent messages before account deletion. Deleted
  messages are removed without a visible placeholder.

## Implementation

- Mobile app: `Menu -> Account management -> 계정 삭제`.
- Firebase callable: `deleteMyAccount`.
- Data export callable: `exportMyData`.
- Auth user is deleted through Firebase Admin SDK after Firestore cleanup.
- `handles/{handle}` is deleted so the ID can be reused later if product policy
  allows it.
- `users/{uid}/fcmTokens/*` is deleted.
- The user is removed from active `rooms/{roomId}.participantIds`.
- `rooms/{roomId}/members/{uid}` is marked with `leftAt` and `accountDeleted`.
- Authored messages are marked with `senderDeleted: true`.

## Operational Checks

- Confirm the user can no longer sign in with the deleted Firebase Auth account.
- Confirm the deleted handle no longer points to the old UID.
- Confirm rooms no longer list the deleted user as an active participant.
- Confirm existing recipients still see conversation history without active
  account identity.
