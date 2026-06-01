# Accessibility Audit

Korean translation: `docs/ko/ACCESSIBILITY_AUDIT.md`

## Current Pass

- Primary icon-only buttons have tooltips.
- Message bubbles are constrained to avoid clipped text.
- Composer buttons keep stable hit areas.
- Error, retry, and sending states are visible as text, not color alone.
- The green palette is paired with black/white/gray text for contrast.

## Manual QA

- Test text scaling at 100%, 130%, and 160%.
- Test 360px width for Korean labels.
- Test screen reader focus order: home tabs, room rows, composer, message action
  sheet, room info.
- Test touch targets on low-end Android devices.
- Confirm all destructive actions have clear labels.

## Known Follow-Up

Run a real TalkBack/VoiceOver pass during device beta. Automated checks cannot
fully verify chat message reading order or bottom sheet interaction quality.
