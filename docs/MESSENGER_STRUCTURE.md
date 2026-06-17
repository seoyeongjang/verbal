# Messenger Structure Benchmark

Date checked: 2026-05-27

This document turns competitor messenger features into a practical structure
for Verbal.

The goal is not to clone Instagram DM, KakaoTalk, or Telegram. The goal is to
define a stable feature map, data model direction, and implementation sequence
for a voice-first Korean messenger.

## Competitor Feature Map

### Core Chat

Instagram DM:

- 1:1 and group DMs
- Replies
- Stickers, GIFs, photos, videos, and voice-message replies
- Read-receipt controls

KakaoTalk:

- 1:1 and group chat
- Chatroom folders
- Sent-message edit and delete

Telegram:

- 1:1 chats, groups, large groups, and channels
- Replies, mentions, and pinned messages

Verbal direction:

- Keep 1:1 and group rooms first.
- Add reply, reaction, edit, delete, and read-state features before broad
  social features.

### Inbox Organization

Instagram DM:

- Pinned chats
- Message requests
- Read receipts on or off

KakaoTalk:

- Chatroom folders
- Unread folder

Telegram:

- Folders
- Archive
- Pinned chats inside folders

Verbal direction:

- Add pinned, archived, muted, unread, and voice-focused inbox filters.

### Message Actions

Instagram DM:

- Message edit within a time window
- Pinned messages
- Scheduled messages
- Translation
- Music and location sharing

KakaoTalk:

- Edit and delete sent messages
- Replies or comments
- Search
- Voice-call recording bubbles

Telegram:

- Edit
- Schedule
- Reactions
- Translation
- Search
- Self-destruct behavior in Secret Chats

Verbal direction:

- Add edit, delete, reply, reaction, pin, and search first.
- Add schedule and translation after launch.

### Voice And Calls

Instagram DM:

- Voice messages
- Voice replies
- Audio and video calls depending on account and app support

KakaoTalk:

- VoiceTalk and FaceTalk
- Call recordings shown as chat bubbles
- AI summary rollout direction

Telegram:

- Voice and video calls
- Group calls
- Group voice chats
- Voice and video messages

Verbal direction:

- Make voice message plus transcript the product center.
- Later add call recording, transcript, and summary features.

### Media And Files

Instagram DM:

- Photos, videos, Reels, stickers, GIFs, music previews, and location

KakaoTalk:

- Photos, videos, files, ShortForm sharing, stickers, and emoticons

Telegram:

- Files of any type
- Photos, videos, stickers, bots, and mini apps

Verbal direction:

- Add image and file attachments after voice reliability is stable.
- Keep short-form and social sharing out of the MVP.

### Community

Instagram DM:

- Group chat QR invites

KakaoTalk:

- Open Chat
- Open Chat communities
- Voice Rooms
- Public-surface moderation

Telegram:

- Public groups
- Channels
- Invite links
- Bots and mini apps

Verbal direction:

- Add invite links and QR first.
- Add open rooms and channels only after moderation exists.

### Privacy And Safety

Instagram DM:

- Message requests
- Read-receipt controls
- Reporting
- Disappearing and encrypted-chat features in supported contexts

KakaoTalk:

- Group invite approval
- Report flow
- Stricter Open Chat safety rules
- Privacy-first policy

Telegram:

- Secret Chats
- Self-destruct timers
- 2-step security
- Bot privacy mode

Verbal direction:

- Add block, report, and invite approval before open communities.
- Treat Secret Chat as a later separate mode.

## Benchmark Takeaways

1. Instagram DM wins on lightweight expression and social content flow.
   The useful parts for us are quick replies, reactions, pins, scheduling,
   translation, location, and group QR invites.
2. KakaoTalk wins in Korean everyday-message expectations. The useful parts
   for us are chat folders, sent-message edit/delete, unread organization,
   group invite approval, and voice-call recordings as chat bubbles.
3. Telegram wins on power-user and community structure. The useful parts for us
   are folders/archive, strong search, pinned messages, roles, large rooms,
   channels, bots, and Secret Chat patterns.
4. Verbal should not start as a full social platform. It should first
   be a high-quality voice-to-text messenger, then grow into organized chat,
   then community.

## Product Structure

### Room Types

`direct`

- Launch status: current / keep
- Purpose: 1:1 private conversation
- Rules: exactly two human members; no room title required

`group`

- Launch status: current / harden
- Purpose: small private room
- Rules: invite approval, member list, admin role, optional title

`open`

- Launch status: later
- Purpose: KakaoTalk Open Chat style interest room
- Rules: discoverable, report-heavy, stricter moderation, room-specific
  public profile

`channel`

- Launch status: later
- Purpose: Telegram-style broadcast
- Rules: admins post, followers read, optional linked discussion group

`assistant`

- Launch status: later
- Purpose: AI or bot conversation
- Rules: bot member, explicit tool permissions, no access to unrelated chats

### Member Roles

`owner`

- Applies to: group, open, channel
- Permissions: manage room, roles, invites, safety settings, and room deletion

`admin`

- Applies to: group, open, channel
- Permissions: invite/remove members, pin, moderate messages, update room
  metadata

`member`

- Applies to: all user rooms
- Permissions: send and read messages according to room permissions

`guest`

- Applies to: open or channel preview
- Permissions: read or preview only until joined

`bot`

- Applies to: assistant and future group rooms
- Permissions: read only allowed messages and respond through controlled
  commands

### Message Types

`text`

- Launch status: current / keep
- Structure: plain text with edit, delete, and reply metadata

`voice`

- Launch status: current / strengthen
- Structure: audio, duration, transcript, STT status, confidence, and language

`image`

- Launch status: next
- Structure: storage attachment, thumbnail, and dimensions

`file`

- Launch status: later
- Structure: storage attachment, filename, size, and MIME type

`location`

- Launch status: later
- Structure: latitude, longitude, label, and live-location expiry

`system`

- Launch status: next
- Structure: room created, member joined, call ended, or safety notice

`call_recording`

- Launch status: later
- Structure: audio recording, transcript, summary, and call participants

`shared_content`

- Launch status: later
- Structure: link preview, post/Reel/short-form placeholder, and external
  source

### Message Actions

P0:

- Reply to message
- Edit text
- Delete for me / delete for everyone
- Read receipt / last read
- Delivery state: sending, sent, delivered, read, failed

P1:

- Reactions
- Pin message
- Search in room

P2:

- Schedule message
- Translate message

P3:

- Disappearing message

Priority rationale:

- P0 is required for launch-quality conversation and STT correction.
- P1 improves repeated daily use.
- P2 is useful after the core loop is stable.
- P3 needs privacy, retention, and moderation policy decisions first.

## Firestore Structure

`users/{uid}`

- `displayName`, `handle`, `photoUrl`, `phoneHash`
- `defaultSendMode`
- `privacy.readReceipts`
- `privacy.discoverableByHandle`
- `privacy.allowUnknownInvites`
- `createdAt`, `updatedAt`

`rooms/{roomId}`

- `type`: `direct`, `group`, `open`, `channel`, or `assistant`
- `visibility`: `private`, `link`, or `public`
- `title`, `photoUrl`, `description`
- `participantIds`: denormalized list for private rooms
- `ownerId`
- `capabilities.voice`
- `capabilities.text`
- `capabilities.media`
- `capabilities.calls`
- `capabilities.reactions`
- `capabilities.replies`
- `capabilities.pins`
- `capabilities.search`
- `lastMessage.kind`
- `lastMessage.preview`
- `lastMessage.senderId`
- `lastMessage.createdAt`
- `createdAt`, `updatedAt`

`rooms/{roomId}/members/{uid}`

- `role`: `owner`, `admin`, `member`, `guest`, or `bot`
- `nickname`
- `joinedAt`, `lastReadAt`, `lastReadMessageId`
- `unreadCount`
- `notificationMode`: `all`, `mentions`, or `muted`
- `pinned`, `archived`, `folderIds`
- `blockedUntil`, `leftAt`

`rooms/{roomId}/messages/{messageId}`

- `senderId`
- `kind`: `text`, `voice`, `image`, `file`, `location`, `system`,
  `call_recording`, or `shared_content`
- `text`, `transcript`, `language`
- `sttStatus`, `sttConfidence`
- `audioPath`, `durationMs`
- `attachments[]`
- `replyTo.messageId`
- `replyTo.senderId`
- `replyTo.preview`
- `mentions[]`
- `reactions.{emoji}[]`
- `delivery.state`
- `delivery.deliveredToCount`
- `delivery.readByCount`
- `edit.editedAt`
- `edit.version`
- `edit.previousTextHash`
- `delete.deletedAt`
- `delete.deletedBy`
- `delete.mode`
- `expiresAt`
- `createdAt`, `updatedAt`

Attachment fields:

- `type`
- `storagePath`
- `url`
- `mimeType`
- `name`
- `size`
- `width`
- `height`
- `durationMs`

`rooms/{roomId}/pins/{messageId}`

- `messageId`
- `pinnedBy`
- `createdAt`
- `preview`

`roomInvites/{inviteId}`

- `roomId`
- `createdBy`
- `type`: `handle`, `link`, or `qr`
- `status`: `active`, `revoked`, or `expired`
- `expiresAt`, `createdAt`

`reports/{reportId}`

- `reporterId`
- `targetType`
- `targetId`
- `roomId`
- `messageId`
- `reason`
- `details`
- `status`
- `createdAt`, `reviewedAt`

`blocks/{uid}/users/{blockedUid}`

- `blockedAt`
- `reason`

`userFolders/{uid}/folders/{folderId}`

- `name`
- `filter`: `all`, `unread`, `voice`, `groups`, or `custom`
- `roomIds`
- `sortOrder`
- `createdAt`, `updatedAt`

## Backend API Structure

Rooms:

- `createRoom`
- `updateRoom`
- `joinRoomByInvite`
- `leaveRoom`
- `updateMemberRole`

Messaging:

- `sendTextMessage`
- `sendVoiceMessage`
- `editMessage`
- `deleteMessage`
- `markRead`
- `addReaction`
- `removeReaction`
- `pinMessage`
- `unpinMessage`

Voice and STT:

- `createTranscriptionDraft`
- `finalizeVoiceMessage`
- `retryTranscription`
- `summarizeCallRecording`

Inbox:

- `setRoomPinned`
- `setRoomArchived`
- `setRoomMuted`
- `updateFolder`

Safety:

- `reportMessage`
- `reportRoom`
- `blockUser`
- `resolveReport`

Notifications:

- `registerMessagingToken`
- `sendPrivacySafeNotification`
- `syncBadgeCount`

## UI Structure

### Inbox

- Top tabs: `All`, `Unread`, `Voice`, `Groups`
- Pinned rooms above regular rooms
- Room row: avatar, title, last preview, time, unread badge, mute icon
- Row actions: pin, archive, mute, delete or leave
- Search entry point for people, rooms, and message transcripts

### Chat Thread

- Header: back, room avatar/title, member count/status, search/info
- Message list: grouped bubbles, transcript under voice, edited/deleted labels
- Message long-press menu: reply, edit, copy, pin, delete, report
- Composer: text field, voice record button, attachment button, send button
- Voice review sheet: transcript edit, retry STT, send mode, send

### Room Info

- Members and roles
- Pinned messages
- Shared media and files
- Notification settings
- Invite link and QR
- Report, block, and leave controls

## Implementation Roadmap

### Phase 1: Launch-Critical Messenger Basics

- Message lifecycle: sending, sent, failed, delivered/read later if FCM and
  read tracking are ready.
- `replyTo`, `editedAt`, `deletedAt`, and delete mode.
- Inbox pinned, archived, and muted state per member.
- Unread count and `lastReadAt`.
- Room info screen with members and leave/report/block.
- Transcript search within current room.

### Phase 2: Voice-First Differentiation

- STT confidence and language metadata.
- Retry transcription and correction history.
- Better voice waveform, playback speed, and transcript collapse/expand.
- Call recording bubble model for future VoiceTalk-like flow.
- Voice transcript summary for long recordings.

### Phase 3: Growth And Community

- Invite links and QR codes.
- Group admin roles and permissions.
- Public/open room model behind moderation flags.
- Room discovery only after report, block, keyword filter, and rate-limit
  systems exist.

### Phase 4: Power Features

- Message scheduling.
- Translation.
- Location sharing with expiry.
- File attachments.
- Secret/disappearing rooms as a separate privacy mode.
- Bot/assistant rooms with explicit permission boundaries.

## Build Order Recommendation

1. Add message reply, edit, delete, and read/unread state.
2. Add inbox organization: pinned, archived, muted, unread, and voice filters.
3. Add room info and safety actions: report, block, leave, invite approval.
4. Add transcript search and voice-message quality tools.
5. Add invite links and QR after safety basics.
6. Add media, file, location, schedule, and translation only after the core
   messenger loop is stable.

## Sources

- Meta: Instagram DM updates
  https://about.fb.com/news/2024/03/instagram-dm-updates/
- Meta: Instagram location sharing and nicknames
  https://about.fb.com/news/2024/11/new-ways-to-connect-through-dms/
- Meta: Instagram translation, music, scheduling, pinned messages, group QR
  https://about.fb.com/news/2025/02/new-instagram-dm-features-stay-connected/amp/
- Kakao: KakaoTalk service page
  https://www.kakaocorp.com/page/service/service/KakaoTalk?lang=ENG
- Kakao: if(kakao)25 KakaoTalk AI/features announcement
  https://www.kakaocorp.com/page/detail/11725?lang=ENG
- KakaoTalk Safety: operation policy
  https://talksafety.kakao.com/en/policy?lang=en
- KakaoTalk Safety: group chat participation settings
  https://talksafety.kakao.com/en/toolandguide/unwanted/joinsettings
- Telegram FAQ
  https://telegram.org/faq
- Telegram: folders and archive
  https://telegram.org/blog/folders
- Telegram: edit messages and mentions
  https://telegram.org/blog/edit/
- Telegram: scheduled messages
  https://telegram.org/blog/scheduled-reminders-themes
- Telegram: reactions and translation
  https://telegram.org/blog/Reactions-spoilers-Translations
