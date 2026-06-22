# Play App Content Worksheet

Korean translation: `docs/ko/PLAY_APP_CONTENT_WORKSHEET.md`

Status date: 2026-06-18

Use this worksheet for Google Play Console > Policy and programs > App content.
It is an operational worksheet, not legal advice. Final answers must match the
actual submitted build.

Generated copy/paste answer pack:
`artifacts/play-console/verbal-app-content-answers-latest.md`

Copy-button HTML sheet:
`artifacts/play-console/verbal-app-content-copy-sheet-latest.html`

The generated answer pack includes a section-by-section console flow with
Korean and English Play Console labels, exact values/sources, and the evidence
flag used by `npm run record:launch-evidence`.

Official basis checked on 2026-06-18:

- Google Play App content includes privacy policy, ads, sign-in details, target
  audience/content, sensitive permissions, content ratings, Data safety, news,
  and COVID-19 declarations.
- Google Play Data safety must cover data collected and processed by the app and
  third-party SDKs/providers.
- Apps that allow account creation must provide an in-app account deletion path
  and a web link where users can request account/data deletion.

## 1. Privacy Policy

- Console answer: provide privacy policy URL.
- URL: `https://verbal.chat/privacy`
- Internal source: `docs/PRIVACY_POLICY.md`
- In-app path: Sign-up consent and Terms/Policies menu.

## 2. App Access / Sign-in Details

- Console answer: access is restricted by phone sign-in.
- Use source: `docs/PLAY_REVIEWER_ACCESS.md`
- Test phone number: `+16505550101`
- Verification code: `123456`
- Payment/subscription required: No
- External membership/invitation required: No

Paste the instructions from `docs/PLAY_REVIEWER_ACCESS.md` into the Play Console
Sign-in details field.

## 3. Ads

- Current submitted-build recommendation: select `No` unless a production ad SDK
  or production ad placement is enabled in the exact AAB being uploaded.
- Current app note: Verbal has planned/simulated native ad surfaces in product
  design, but the Play Console declaration must reflect the submitted build. If
  a real ad SDK, banner, native ad, interstitial, sponsored feed item, or house
  ad is enabled, change this answer to `Yes`.

## 4. Data Safety

- Use source: `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- Public privacy policy: `https://verbal.chat/privacy`
- Account deletion URL: `https://verbal.chat/account/delete`
- Data deletion policy URL: `https://verbal.chat/data-deletion`
- Third-party processing disclosed:
  - Firebase / Google Cloud for authentication, database, storage, functions,
    analytics, crash reporting, and push infrastructure.
  - Deepgram for voice STT processing.
- Data categories to review in the form:
  - Phone number and user/account identifiers.
  - Profile text, display name, user ID, contacts/friends metadata.
  - Messages, voice recordings, voice transcripts, attachments.
  - Calendar events and reminders.
  - Optional shared location.
  - Device IDs, push tokens, diagnostics, app interactions.

## 5. Data Deletion

- App supports account creation: Yes.
- In-app account deletion path: hamburger menu > account/settings area >
  account deletion.
- Web account deletion path: `https://verbal.chat/account/delete`
- Data deletion explanation: `https://verbal.chat/data-deletion`
- Support email: `support@verbal.chat`
- Internal source: `docs/DATA_DELETION_POLICY.md`

## 6. Target Audience And Content

- Conservative initial recommendation for internal testing / early closed beta:
  select adult-oriented target ages only until youth policy, moderation, and
  legal review are completed.
- If Verbal is intentionally opened to teens, complete an additional youth and
  safety review before selecting teen age groups.
- Rationale: the app includes user-generated messaging, voice recordings,
  open-chat/link sharing, optional location sharing, and report/block flows.

## 7. Content Rating

Answer based on the submitted build:

- App category: Communication / social messaging.
- User interaction / user-generated content: Yes.
- Messaging between users: Yes.
- Open chat or invite-link based rooms: Yes if enabled in the build.
- Location sharing: Yes if enabled in the build, user-initiated.
- Purchases/gambling/news/government/medical/financial features: No unless the
  product scope changes.
- Moderation controls: report, block, safety center, community guidelines.

## 8. Sensitive Permissions

Review after AAB upload because Play Console evaluates permissions from the
artifact:

- Microphone: voice message recording and voice calendar input.
- Notifications: message push and calendar reminders.
- Contacts: only if contact sync is enabled in the submitted build.
- Location: only when the user explicitly shares location.
- Camera/photos/files: only when the user attaches media or file content.

If Play Console requests a permission declaration, explain the exact user-facing
feature, whether the permission is optional, and the in-app disclosure path.

## 9. News, Government, COVID-19, Health, Financial

Current Verbal scope:

- News app: No
- Government app: No
- COVID-19 contact tracing/status: No
- Health app: No
- Financial features: No
- Gambling/real-money games: No

Revisit these answers if future features change the product scope.

## 10. App Category, Contact Details, And Store Listing

- App category: Communication / social messaging.
- Contact email: `support@verbal.chat`
- Website: `https://verbal.chat`
- Store listing text: use `artifacts/store/google-play/ko-KR/` and
  `artifacts/store/google-play/en-US/`.
- App icon: `artifacts/store/google-play/assets/app-icon-512.png`
- Feature graphic:
  `artifacts/store/google-play/assets/feature-graphic-1024x500.png`
- Phone screenshots:
  `artifacts/store/google-play/assets/phone-screenshots/`

## 11. UGC And Safety

- UGC present: Yes, because users can create messages, voice content, profiles,
  attachments, and open-chat content.
- Public policy URL: `https://verbal.chat/community-guidelines`
- Safety features to verify before wider testing:
  - Report user/message/chat.
  - Block user.
  - Request message controls.
  - Safety center entry.
  - Moderation/support handling path.

## 12. Manual Owner Review Before Submission

Before clicking submit/send for review, verify:

- Hosted URLs open over HTTPS.
- The Data Safety answers match `docs/GOOGLE_PLAY_DATA_SAFETY.md`.
- The App access credentials work on the submitted build.
- The AAB package name is `com.voicebeta.verbal`.
- Store listing text does not claim unsupported features.
- If any real ad SDK or ad placement is enabled, Ads is changed to `Yes`.
