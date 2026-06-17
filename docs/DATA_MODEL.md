# Data Model

## Firestore

`users/{uid}`

- `displayName`: user-facing name.
- `handle`: lowercase invite ID.
- `phoneHash`: reserved for hashed phone lookup.
- `photoUrl`: optional profile image.
- `defaultSendMode`: `confirm` or `instant`.
- `holidayCountryCode`: calendar holiday overlay country, one of `none`,
  `KR`, `US`, `JP`, or `CN`.
- `deletedAt`: set after account deletion.
- `createdAt`, `updatedAt`.

`users/{uid}/calendarEvents/{eventId}`

- `ownerId`: same as `{uid}`.
- `title`: 1-120 character event title.
- `startAt`: event start timestamp.
- `endAt`: event end timestamp, default 60 minutes after start for voice-created
  drafts unless the user changes it.
- `timezone`: default `Asia/Seoul`.
- `source`: `manual` or `voice`.
- For chat proposal-created events, `source` is `chatProposal` and the event may
  include `roomId`, `proposalId`, `messageId`, and `candidateId`.
- `details`: optional event notes/details, up to 2,000 characters.
- `transcript`: original voice command transcript when the event came from
  voice.
- `status`: currently `active`.
- `createdAt`, `updatedAt`.
- Client reads are allowed only for the owner. Client create, update, and delete
  are blocked; all writes go through Cloud Functions.

`users/{uid}/friends/{friendUid}`

- `uid`: friend user ID, same as `{friendUid}`.
- `displayName`: cached friend display name for the picker.
- `handle`: cached friend handle.
- `defaultSendMode`: cached send-mode preference, currently used for display
  compatibility.
- `photoUrl`: optional cached profile image.
- `addedAt`, `updatedAt`.
- Client reads are allowed only for the owner. Client writes are blocked; friend
  additions go through `addFriendByHandle`.

`handles/{handle}`

- `uid`: owner user ID.
- `updatedAt`.

`rooms/{roomId}`

- `type`: `direct` or `group`.
- `participantIds`: user IDs allowed to read the room.
- `title`: display title.
- `audioRetentionDays`: room-level audio file retention, default `1`.
- `audioRetentionPreset`: `oneDay`, `sevenDays`, or `custom`.
- `lastMessage`: `{ kind, preview, senderId, createdAt }`.
- `createdAt`, `updatedAt`.

`rooms/{roomId}/messages/{messageId}`

- `senderId`.
- `kind`: `text`, `voice`, `image`, `file`, `location`, or
  `calendarProposal`.
- `text`: final display text.
- `transcript`: raw STT output.
- `audioPath`: Firebase Storage path.
- `audioHash`: SHA-256 hash used for duplicate STT caching.
- `audioExpiresAt`: timestamp when audio should be deleted.
- `audioDeletedAt`: timestamp when audio was removed.
- `audioRetentionDays`: retention applied when the message was created.
- `audioRetentionStatus`: `active`, `deleted`, or `none`.
- `durationMs`.
- `sttStatus`: `none`, `processing`, `completed`, or `failed`.
- `sttCacheHit`: whether transcript came from cache.
- `sendMode`: `confirm` or `instant`.
- `senderDeleted`: true when the sender account has been deleted but the
  conversation history is retained.
- `createdAt`, `updatedAt`, `editedAt`.

`rooms/{roomId}/calendarProposals/{proposalId}`

- `roomId`, `messageId`: links the proposal document to the rendered chat
  message card.
- `createdBy`: user who created the proposal.
- `title`: 1-120 character proposed event title.
- `details`: optional notes/details, up to 2,000 characters.
- `timezone`: default `Asia/Seoul`.
- `status`: `open`, `finalized`, or `cancelled`.
- `candidates`: 1-5 candidate windows. Chat composer proposals require at
  least 2 candidates; calendar-to-chat share can use a single candidate.
- `votes`: map of `{ uid: [candidateId] }`; users may select multiple
  candidates.
- `finalCandidateId`: set when the proposer or room admin finalizes the
  proposal.
- `source`, `transcript`: preserve whether the proposal was made manually or
  from a voice draft.
- `createdAt`, `updatedAt`.

`rooms/{roomId}/calendarProposals/{proposalId}/votes/{uid}`

- `uid`.
- `candidateIds`: selected candidate IDs.
- `updatedAt`.
- Client reads are allowed only for room participants. Client writes are
  blocked; all proposal, vote, finalize, add-to-calendar, and cancel writes go
  through Cloud Functions.

`transcriptionDrafts/{draftId}`

- `ownerId`.
- `audioPath`.
- `language`.
- `durationMs`.
- `status`.
- `transcript`.
- `manualTranscript`: true when the user entered text manually after STT
  failure or chose manual recovery.
- `audioHash`, `audioExpiresAt`, `audioDeletedAt`, `audioRetentionStatus`.
- `errorCode`.
- `createdAt`, `updatedAt`.

`usageDaily/{uid}_{yyyy-mm-dd}`

- `uid`, `date`, `timezone`.
- `textCount`, `voiceCount`, `voiceMs`.
- `limitMode`: currently `unlimited`; `textLimit` and `voiceLimit` are stored as `null`.
- `createdAt`, `updatedAt`.

`reports/{reportId}`

- `reporterId`.
- `targetType`: `message` or `room`.
- `targetId`, `roomId`, `messageId`.
- `reason`, `details`.
- `status`: `open`, `reviewing`, `actioned`, or `dismissed`.
- `count`: duplicate reports by the same reporter for the same target.
- `createdAt`, `updatedAt`.

`blocks/{uid}/users/{blockedUid}`

- `blockedAt`.
- `reason`.

`actionCooldowns/{uid}_{action}`

- `uid`, `action`.
- `lastAt`: last sensitive action timestamp.
- Used only for abuse prevention on invite, report, and block actions. Normal
  text, voice count, and voice duration are not capped.

`transcriptionCache/{language}_{audioHash}`

- `audioHash`, `language`, `model`.
- `transcript`.
- `hitCount`, `createdAt`, `lastUsedAt`.

## Storage

- `voice_drafts/{uid}/{draftId}.m4a`: temporary audio awaiting message STT or
  calendar intent parsing.
- `voice_messages/{roomId}/{messageId}.m4a`: sent voice message audio.

## Backend Contract

The mobile app writes audio files to Storage, then calls Cloud Functions. Message documents are created by Functions only, which keeps participant checks, transcript status, notification behavior, usage monitoring, and audio retention centralized.

Friend additions are stored under `users/{uid}/friends/{friendUid}` through
`addFriendByHandle`. Room creation still uses participant handles, but the
mobile picker prefers the caller's saved friends when available and falls back
to the user directory for discovery/search.

Calendar events are stored separately from chat messages under
`users/{uid}/calendarEvents/{eventId}`. Voice calendar commands are transcribed
and parsed by `createCalendarIntentDraft`; complete title/date/time commands are
saved immediately by `createCalendarEvent`, while incomplete commands are rejected
with a retry prompt. Users can edit the title, detailed notes, date, time, and
duration after creation. Update and hard delete also go through Functions.
Country holidays are a display overlay derived from the user's
`holidayCountryCode`; they are not written into `calendarEvents`.

Chat room schedule proposals connect messages and calendar without writing
directly to `calendarEvents` from the client. `createCalendarProposal` creates a
chat card and proposal document, `voteCalendarProposal` stores each member's
candidate selections, and `finalizeCalendarProposal` creates internal calendar
events only for the proposer and members who selected the finalized candidate.
