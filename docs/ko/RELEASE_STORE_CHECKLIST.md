# 릴리즈와 스토어 체크리스트

원문: `docs/RELEASE_STORE_CHECKLIST.md`

## 스토어 listing 입력 자료

- 앱 이름: Verbal.
- 카테고리: 커뮤니케이션/소셜.
- 짧은 설명: STT transcript가 자동 생성되는 보이스 우선 메신저.
- 스크린샷: 인증, 홈, 1:1 채팅, transcript 포함 음성 메시지, 캘린더,
  대화 정보, 초대 QR.
- 연락 이메일과 지원 URL.
- 개인정보처리방침 URL.
- 데이터 삭제 URL 또는 앱 내 삭제 안내.

## Google Play Data Safety 초안

- 수집 데이터: 전화번호, 사용자 아이디/handle, 프로필 이름, 메시지, 음성파일,
  transcript, 첨부파일, 사용자가 공유한 대략/정확 위치, 기기 push token, 신고,
  사용량 진단.
- 목적: 인증, 메시징, STT, 안전, 알림, analytics, 악용 방지, 고객지원.
- 공유: 프로덕션 STT 활성화 시 Deepgram이 STT 처리를 위해 음성을 수신합니다.
- 삭제: 앱 내 계정 삭제와 개별 메시지 삭제.
- 암호화: Firebase 전송 구간 암호화, Google Cloud 기반 Firestore/Storage
  저장 시 암호화.

## 권한 안내 문구

- 마이크: 음성 메시지 녹음과 전송.
- 알림: 새 메시지 알림 수신.
- 사진/파일: 보낼 첨부파일 선택.
- 위치: 채팅방에 현재 위치 공유.

## 빌드

- 업로드 전 최신 소스 기준 Android AAB를 다시 빌드합니다.
- 먼저 internal testing 트랙에 업로드합니다.
- 프로덕션 릴리즈 전 베타 QA를 실행합니다.
