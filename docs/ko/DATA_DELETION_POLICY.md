# 데이터 삭제 정책

원문: `docs/DATA_DELETION_POLICY.md`

## 사용자 안내 정책

- 사용자는 `메뉴 -> 계정 관리 -> 계정 삭제`에서 계정 삭제를 요청할 수
  있습니다.
- 계정 삭제 시 사용자 아이디 선점, 푸시 토큰, 프로필 표시 정보, 활성 대화방
  멤버십을 삭제 또는 비활성화합니다.
- 이미 상대방에게 전송된 메시지는 대화 맥락 유지를 위해 보존하되, 발신자는
  삭제된 계정으로 표시하고 계정 프로필은 익명화합니다.
- 음성파일은 방의 보존기간 정책을 따릅니다. 만료 후 음성파일은 삭제되고
  transcript 텍스트만 남습니다.
- 사용자는 계정 삭제 전 자신이 보낸 개별 메시지를 삭제할 수 있습니다. 개별
  삭제 메시지는 별도 흔적 없이 제거됩니다.

## 구현 방식

- 모바일 앱: `메뉴 -> 계정 관리 -> 계정 삭제`.
- 웹 삭제 요청 페이지: `https://verbal.chat/account/delete`.
- 데이터 삭제 정책 페이지: `https://verbal.chat/data-deletion`.
- Firebase callable: `deleteMyAccount`.
- 데이터 내보내기 callable: `exportMyData`.
- Firestore 정리 후 Firebase Admin SDK로 Auth 사용자를 삭제합니다.
- `handles/{handle}` 문서를 삭제해 정책상 허용 시 아이디 재사용이 가능하게
  합니다.
- `users/{uid}/fcmTokens/*`를 삭제합니다.
- 활성 `rooms/{roomId}.participantIds`에서 사용자를 제거합니다.
- `rooms/{roomId}/members/{uid}`에는 `leftAt`, `accountDeleted`를 기록합니다.
- 사용자가 작성한 메시지에는 `senderDeleted: true`를 기록합니다.

## 운영 확인

- Firebase Hosting을 배포한 뒤 Google Play Console에 URL을 입력하기 전에
  `/account/delete`와 `/data-deletion`이 HTTPS로 열리는지 확인합니다.
- 삭제된 Firebase Auth 계정으로 다시 로그인할 수 없는지 확인합니다.
- 삭제된 아이디가 기존 UID를 더 이상 가리키지 않는지 확인합니다.
- 대화방 활성 멤버 목록에 삭제 사용자가 남지 않는지 확인합니다.
- 기존 수신자는 대화 이력을 볼 수 있지만 활성 계정 정보는 보지 않는지
  확인합니다.
