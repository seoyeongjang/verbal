# Play Reviewer Access

Korean translation: `docs/ko/PLAY_REVIEWER_ACCESS.md`

Status date: 2026-06-18

Use this document when completing Google Play Console > App content > Sign-in
details / App access. Verbal requires phone sign-in before reviewers can access
messaging, voice STT, calendar, safety, and account settings.

## Reviewer Test Account

- Phone number: `+16505550101`
- SMS verification code: `123456`
- Display name if profile setup appears: `Play Reviewer`
- User ID if profile setup appears: `play_reviewer_001`

This is a Firebase Authentication test phone number. It does not send a real SMS
and should be used only for Play review, internal testing, and smoke testing.

## Copy/Paste Instructions For Play Console

```text
Verbal requires phone sign-in to access the main app.

Use this Firebase test phone credential:
Phone number: +16505550101
Verification code: 123456

Steps:
1. Install and open the app.
2. Accept the required Terms, Privacy Policy, and Community Guidelines consent.
3. Enter +16505550101 in the phone sign-in screen.
4. Enter 123456 as the verification code.
5. If profile setup is shown, use display name "Play Reviewer" and user ID "play_reviewer_001".
6. After sign-in, review the home message list, chat room, voice message STT, voice playback, calendar, report/block, and account deletion entry points.

No payment, subscription, invitation, or external membership is required.
```

## Reviewer QA Path

1. Open Verbal and complete the required consent checkboxes.
2. Sign in with the test phone number and code.
3. Confirm the home screen opens with the message list.
4. Open an existing direct chat or create a new chat.
5. Send a text message.
6. Grant microphone permission if prompted, record a short voice message, and send it.
7. Confirm the voice message bubble appears with transcript text and playback.
8. Open Calendar and confirm monthly calendar rendering.
9. Add a calendar event manually or by voice if microphone permission is available.
10. Open the hamburger menu and confirm Privacy/Security, Data/Storage,
    Customer Support, Terms/Policies, and account deletion access paths.

## Access Notes

- Microphone permission is needed only for voice message and voice calendar flows.
- Notification permission is needed only for push and calendar reminders.
- Location permission is needed only when the user explicitly shares location.
- If STT is temporarily unavailable, the app should still allow message sending
  and should surface the failure without blocking the main chat flow.
- Do not use the Firebase test phone number for public users or production
  marketing screenshots.

## Related Public URLs

- Website: `https://verbal.chat`
- Privacy Policy: `https://verbal.chat/privacy`
- Terms of Service: `https://verbal.chat/terms`
- Community Guidelines: `https://verbal.chat/community-guidelines`
- Account Deletion: `https://verbal.chat/account/delete`
- Data Deletion: `https://verbal.chat/data-deletion`
- Support email: `support@verbal.chat`
