# Play 심사자 접근 정보

원문: `docs/PLAY_REVIEWER_ACCESS.md`

상태 기준일: 2026-06-18

이 문서는 Google Play Console > App content > Sign-in details / App access에
입력할 심사자 접근 정보를 정리한 것입니다. Verbal은 메시지, 음성 STT,
캘린더, 신고/차단, 계정 설정 기능 접근 전에 전화번호 로그인이 필요합니다.

## 심사용 테스트 계정

- 전화번호: `+16505550101`
- SMS 인증 코드: `123456`
- 프로필 설정이 뜰 경우 표시 이름: `Play Reviewer`
- 프로필 설정이 뜰 경우 사용자 ID: `play_reviewer_001`

이 번호는 Firebase Authentication 테스트 전화번호입니다. 실제 SMS는
발송되지 않으며 Play 심사, 내부 테스트, smoke test 용도로만 사용합니다.

## Play Console 입력용 문구

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

## 심사자 확인 경로

1. Verbal을 열고 필수 약관/개인정보/커뮤니티 가이드라인 동의를 완료합니다.
2. 테스트 전화번호와 인증 코드로 로그인합니다.
3. 홈 화면과 메시지 목록이 열리는지 확인합니다.
4. 기존 1:1 대화방을 열거나 새 대화방을 생성합니다.
5. 텍스트 메시지를 발송합니다.
6. 마이크 권한을 허용하고 짧은 음성 메시지를 녹음해 발송합니다.
7. 음성 메시지 버블, transcript 텍스트, 재생 기능을 확인합니다.
8. 캘린더 화면을 열어 월간 캘린더 렌더링을 확인합니다.
9. 가능한 경우 직접 또는 음성으로 일정을 추가합니다.
10. 햄버거 메뉴에서 개인정보/보안, 데이터/저장 공간, 고객지원,
    약관/정책, 계정 삭제 진입 경로를 확인합니다.

## 접근 관련 참고

- 마이크 권한은 음성 메시지와 음성 캘린더 기능에서만 필요합니다.
- 알림 권한은 푸시와 캘린더 알림에만 필요합니다.
- 위치 권한은 사용자가 명시적으로 위치 공유를 실행할 때만 필요합니다.
- STT가 일시적으로 실패하더라도 메시지 발송 자체는 막지 않고 실패 상태를
  표시해야 합니다.
- Firebase 테스트 전화번호는 일반 사용자나 마케팅 이미지에 사용하지 않습니다.

## 관련 공개 URL

- 웹사이트: `https://verbal.chat`
- 개인정보 처리방침: `https://verbal.chat/privacy`
- 이용약관: `https://verbal.chat/terms`
- 커뮤니티 가이드라인: `https://verbal.chat/community-guidelines`
- 계정 삭제: `https://verbal.chat/account/delete`
- 데이터 삭제: `https://verbal.chat/data-deletion`
- 고객지원 이메일: `support@verbal.chat`
