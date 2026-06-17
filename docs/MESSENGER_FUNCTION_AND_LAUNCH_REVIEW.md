# Messenger Function and Launch Review

Korean translation: `docs/ko/MESSENGER_FUNCTION_AND_LAUNCH_REVIEW.md`

Status date: 2026-06-05

This review compares Verbal's current messenger surface with Instagram DM,
KakaoTalk, and Telegram, then turns the gap into launch-oriented function
lists and remaining launch-preparation work.

## Evidence Checked

- Current Verbal implementation notes: `docs/LAUNCH_CHECKLIST.md`
- Messenger benchmark and data model direction: `docs/MESSENGER_STRUCTURE.md`
- Store and policy checklist: `docs/RELEASE_STORE_CHECKLIST.md`
- Current app/backend source search across `apps/mobile/lib`, `functions/src`,
  Firebase rules, and existing docs
- External source check date: 2026-06-05

## Competitor Signals

| Service | Relevant messenger signals | Verbal implication |
| --- | --- | --- |
| Instagram DM | Message edit, pinned chats, read-receipt controls, sticker/GIF/photo/video/voice replies, themes, translation, music stickers, scheduled messages, pinned chat content, group QR invites | Keep DM-like UI, add read-receipt privacy controls and richer reply/media actions after the core voice loop is stable. |
| KakaoTalk | Chatroom folders, message edit/delete, unread folder, AI unread summaries, VoiceTalk call recording/transcription/summary/search, Open Chat, profile/feed privacy, group participation settings, reporting and safety policy | Korean users expect foldered inboxes, safe group invites, report/block flows, and AI-assisted summaries. Voice/call transcript features are a strong roadmap fit. |
| Telegram | Folders, archive, large groups, channels, granular admin privileges, pinned messages, scheduled messages/reminders, reactions, translation, QR codes, Saved Messages with tags, one-time voice/video, pause/resume recording, detailed read times | Add power-user organization, Saved Messages, advanced voice controls, privacy/read controls, and channel/community features only after safety foundations are strong. |

## Current Verbal Strengths

- Voice-first messaging is already the product center: recording, STT, transcript
  display, auto-send, STT retry/manual recovery, Deepgram backend path, and
  transcript retention after audio expiry.
- Core chat actions are mostly covered: text, reply, reactions, edit, hard
  delete, pin/unpin, search, read-state behavior, schedule, translation,
  attachments, files, and location.
- Calendar is now a differentiated feature: voice calendar add, monthly
  calendar, event details, reminders, morning briefing, external calendar
  integration, country holidays, and chat-room calendar proposal/voting.
- Group and safety basics exist: invite links, QR, approval mode, roles,
  member removal, leave, block, message/room reports, and cooldowns for
  abuse-sensitive actions.
- Launch documentation is broader than a typical MVP: privacy, terms,
  deletion, support macros, moderation runbook, store checklist, data safety,
  QA plan, cost model, accessibility audit, and deployment status are present.

## Function Lists

### P0 Before Public Launch

These are user-facing or compliance-adjacent gaps that should be finished
before broad release.

| Function | Why it matters | Current status |
| --- | --- | --- |
| Full real-device E2E coverage | Verbal depends on phone auth, microphone, STT, push, storage, and native permissions. Emulator/browser checks are not enough for launch. | Remaining launch blocker. |
| FCM foreground/background/terminated verification | A messenger without reliable notifications will feel broken. | Backend path exists; real-device delivery still needs verification. |
| Audio retention expiry verification | Product policy says audio expires while transcript remains. This must be proven in production data. | Function source exists; production behavior still needs verification. |
| Terms/privacy/UGC acceptance during sign-up | Google Play UGC policy expects terms/user policy acceptance before UGC upload. | Policies exist; explicit acceptance gate should be verified or added. |
| Account deletion web endpoint | Google Play requires both in-app deletion and a web resource for deletion requests. | In-app flow exists; external web endpoint must be finalized. |
| Moderation queue and response workflow | Report/block UI is not enough; launch needs an operator path, SLA, appeal/restore path, and audit trail. | Runbook exists; operational tooling/status workflow should be validated. |
| Safety center completeness | Kakao/Apple/Google patterns require report, block, policy, contact, and user protection flows that are easy to find. | Basic menus exist; report status, appeal, and safety education can be deepened. |
| Suspicious link / phishing warnings | Korean messenger abuse risk is high, and Kakao highlights phishing prevention. | Recommended P0 safety hardening. |
| Read-receipt privacy controls | Instagram and Telegram expose read controls; users expect per-user or per-room privacy. | Read-state exists; user controls need product verification. |
| Global search | Telegram-style search across chats, transcripts, saved messages, files, and calendar is core for a transcript-first messenger. | Room search exists; global search remains recommended. |
| Saved Messages v1 | Telegram makes this a core personal storage surface; it also fits Verbal transcripts and calendar notes. | Menu exists; full tagged storage workflow should be completed. |

### P1 Strong Beta Differentiators

| Function | Why it matters | Suggested scope |
| --- | --- | --- |
| Inbox folders / archive / unread / voice filters | Kakao and Telegram both rely on chat organization. | Add user-defined folders, archive, unread filter, voice-only filter. |
| Voice pause/resume recording | Telegram users expect long voice recording control. | Lock recording, pause, resume, discard, send. |
| Playback speed and transcript collapse | Voice-first UX needs fast review and lower visual noise. | 1x/1.5x/2x playback, compact transcript toggle. |
| STT confidence and correction history | Makes transcript quality transparent and recoverable. | Show low-confidence segments and keep correction history. |
| Message/report status transparency | Users who report abuse need feedback. | `reported`, `under review`, `actioned`, `closed`, appeal link. |
| Group participation controls | Kakao's group participation settings reduce unwanted invites. | Unknown inviter preview, join/decline before messages load. |
| Per-room notification detail | Messenger users expect precise notification control. | Mute duration, mention-only, voice-only, calendar-only. |
| Message bookmarks / save to Saved Messages | Makes pinned messages less overloaded. | Long-press save, tags, source room backlink. |
| Calendar-share polish | The chat calendar proposal is a differentiator. | Add candidate comments, reminders per proposal, ICS/export later. |
| Crashlytics and analytics production instrumentation | Needed to run beta with evidence. | Wire the existing taxonomy into production analytics/crash reporting. |

### P2 Expansion After Stable Beta

| Function | Why it matters | Launch stance |
| --- | --- | --- |
| Channels / broadcast rooms | Telegram/Kakao channel-style distribution creates growth and business use cases. | Add after moderation and notification systems are stable. |
| Open/community rooms | Good for growth but raises safety risk. | Do not open broadly until safety center, spam controls, and moderation queue are proven. |
| Voice/call recording transcript and AI summary | Kakao's VoiceTalk direction maps well to Verbal's voice-first premise. | High-value roadmap feature after basic voice messaging is stable. |
| AI unread summaries | Strong Kakao-like convenience feature. | Add opt-in with privacy disclosure and cost monitoring. |
| Polls beyond calendar proposals | Useful for groups. | Extend existing calendar vote primitives. |
| Sticker/GIF/music/reaction packs | Youthful messenger mood, but not core. | Add after reliability and safety. |
| Business official accounts | Revenue path without charging personal users. | Add after account/safety/policy groundwork. |
| Commerce/gift/booking links | Revenue path similar to Kakao ecosystem. | Requires partner policy and disclosure. |
| Bots/mini apps | Telegram-like platform power. | Defer until permission boundaries and abuse controls exist. |
| Disappearing/secret rooms | Privacy differentiator. | Requires encryption and retention-policy design before launch. |

## Launch Preparation List

### Product QA

- Run full production Firebase E2E on Android real devices:
  phone auth, profile, handle reservation, room creation, text, voice STT,
  attachment, location, schedule, translation, invite QR, calendar voice add,
  calendar edit/delete, calendar proposal, message edit/delete, report, block,
  leave room.
- Measure STT latency and transcript quality using real Korean speech across
  multiple devices, accents, background noise levels, and network states.
- Verify voice auto-send behavior does not send wrong fallback text and that
  retry/manual recovery only appears on actual STT failure.
- Verify message send speed, reconnect behavior, offline/poor-network states,
  and duplicate-send prevention.
- Verify accessibility with text scaling, tap targets, screen readers, contrast,
  and keyboard focus.

### Notifications And Native Integrations

- Verify FCM on real Android in foreground, background, terminated, locked
  screen, and token-refresh cases.
- If iOS launch is in scope, configure APNs and verify TestFlight push.
- Verify Android runtime permissions for microphone, notifications, photo/file,
  and location with denial/retry flows.
- Verify Google Calendar and Apple Calendar integration states:
  connected, disconnected, permission denied, and failed sync.

### Data, Security, And Operations

- Re-run Firestore/Storage rules tests after every release-bound data model
  change.
- Verify account deletion deletes or anonymizes all in-scope user data,
  including messages, audio, transcripts, attachments, calendar events, reports
  where legally allowed, and third-party STT data requests if applicable.
- Verify data export JSON covers account, messages, saved messages, calendar,
  and relevant metadata.
- Verify audio retention job deletes audio while preserving transcript and audit
  metadata.
- Confirm Firebase/GCP budgets, logging alerts, Deepgram usage alerts, and
  anomaly alerts are live.
- Confirm backup, incident response, rollback, and release versioning procedures.

### Safety And Policy

- Add or verify sign-up acceptance for terms, privacy policy, and user policy.
- Confirm in-app report/block flows cover message, room, profile, invite, and
  public/community content if enabled.
- Build or verify moderation queue, operator notes, appeal handling, and report
  status to user.
- Add phishing/suspicious-link warning logic before opening broad invite or
  community surfaces.
- Keep open/community rooms behind feature flags until moderation capacity is
  proven.

### Store And Legal

- Create Google Play Console app listing and upload the latest AAB to internal
  testing.
- Complete Google Play Data Safety, content rating, target audience, ads
  declaration, permissions declaration, and account deletion web URL.
- Finalize privacy policy, terms, data deletion policy, location-based service
  terms if location is offered, support contact, and youth/minor protection
  policy for Korea-oriented launch.
- Prepare screenshots/video for auth, home, chat, voice STT, calendar,
  calendar proposal, settings, report/block, and account deletion.
- If iOS is included, prepare App Store metadata, TestFlight, APNs, privacy
  nutrition labels, and account deletion review notes.

## Recommended Next Build Order

1. Finish real-device production QA and close remaining P0 launch blockers.
2. Add explicit terms/user-policy acceptance if not already enforced.
3. Add account deletion web endpoint and link it from Play Console and policy
   documents.
4. Add global search across rooms, transcripts, saved messages, attachments,
   and calendar events.
5. Complete Saved Messages with tags and source-room backlinks.
6. Add inbox folders/archive/unread/voice filters.
7. Add read-receipt privacy controls and group participation preview/decline.
8. Deepen safety center: report status, appeal, phishing warning, report and
   leave.
9. Add advanced voice controls: pause/resume, playback speed, transcript
   collapse, confidence/correction history.
10. Start closed beta only after notification, deletion, retention, moderation,
    and store-policy gates are verified.

## Sources

- Meta Newsroom, Instagram DM updates:
  https://about.fb.com/news/2024/03/instagram-dm-updates/
- Meta Newsroom, Instagram DM translation, scheduling, pinned content, group QR:
  https://about.fb.com/news/2025/02/new-instagram-dm-features-stay-connected/amp/
- Meta Newsroom, Instagram location sharing and nicknames:
  https://about.fb.com/news/2024/11/new-ways-to-connect-through-dms/
- KakaoTalk service page:
  https://www.kakaocorp.com/page/service/service/KakaoTalk?lang=ENG
- Kakao if(kakao)25 AI and KakaoTalk update:
  https://www.kakaocorp.com/page/detail/11725?lang=ENG
- KakaoTalk Safety Report:
  https://talksafety.kakao.com/en/report/overview?lang=en
- KakaoTalk Operation Policy:
  https://talksafety.kakao.com/en/policy?lang=en
- KakaoTalk group participation settings:
  https://talksafety.kakao.com/en/toolandguide/unwanted/joinsettings
- Telegram FAQ:
  https://telegram.org/faq
- Telegram folders:
  https://telegram.org/blog/folders
- Telegram scheduled messages:
  https://telegram.org/blog/scheduled-reminders-themes
- Telegram reactions and translation:
  https://telegram.org/blog/reactions-spoilers-translations
- Telegram Saved Messages and one-time voice:
  https://telegram.org/blog/new-saved-messages-and-9-more
- Google Play account deletion requirement:
  https://support.google.com/googleplay/android-developer/answer/13327111?hl=en-EN
- Google Play UGC policy:
  https://support.google.com/googleplay/android-developer/answer/9876937?hl=en
- Apple App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
- Apple account deletion guidance:
  https://developer.apple.com/support/offering-account-deletion-in-your-app
