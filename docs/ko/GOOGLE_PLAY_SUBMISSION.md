# Google Play 제출 패키지

원문: `docs/GOOGLE_PLAY_SUBMISSION.md`

상태 기준일: 2026-05-28

이 문서는 실기기 없이 미리 준비할 수 있는 Google Play Console 입력값을 정리합니다.
최종 업로드와 심사는 Play Console 앱 레코드가 필요합니다.

## 앱 정보

- 앱 이름: Verbal
- 기본 언어: 한국어
- 앱 유형: 앱
- 카테고리: 커뮤니케이션
- 패키지명: `com.voicebeta.verbal`
- Firebase 프로젝트: `voice-messenger-jangs-260522`
- Android Firebase App ID: `1:203811587610:android:60b60d74b332290520f3a3`

## 스토어 등록정보 초안

준비된 파일:

- 한국어 짧은 설명:
  `artifacts/store/google-play/ko-KR/short-description.txt`
- 한국어 전체 설명:
  `artifacts/store/google-play/ko-KR/full-description.txt`
- 한국어 내부 테스트 릴리즈 노트:
  `artifacts/store/google-play/ko-KR/release-notes-internal.txt`
- 영어 짧은 설명:
  `artifacts/store/google-play/en-US/short-description.txt`
- 영어 전체 설명:
  `artifacts/store/google-play/en-US/full-description.txt`
- 영어 내부 테스트 릴리즈 노트:
  `artifacts/store/google-play/en-US/release-notes-internal.txt`

## 개인정보/정책 URL

Play Console에는 로컬 파일이 아니라 공개 웹 URL이 필요합니다. 운영 심사 전 아래
문서를 공개 URL로 게시한 뒤 Play Console에 입력해야 합니다.

- 개인정보처리방침: `docs/PRIVACY_POLICY.md`
- 이용약관: `docs/TERMS_OF_SERVICE.md`
- 계정/데이터 삭제 정책: `docs/DATA_DELETION_POLICY.md`

## 내부 테스트 메모

에뮬레이터 또는 내부 smoke test에는 아래 Firebase Auth 테스트 계정을 사용합니다.

- 전화번호: `+16505550101`
- SMS 코드: `123456`

이 번호는 Firebase Auth 테스트 전화번호로 등록되어 있습니다. 실제 SMS를 발송하지
않으며 공개 고객지원 계정으로 사용하면 안 됩니다.

## 릴리즈 산출물

- 최신 Android App Bundle:
  `dist/android/app-release.aab`

## 내부 테스트 업로드 전

- Google Play Console에서 앱 생성.
- 앱 액세스, 광고, 콘텐츠 등급, 타겟층, 뉴스 앱 여부, COVID-19 관련 선언 작성.
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` 기준으로 Data Safety 작성.
- `dist/android/app-release.aab`를 내부 테스트 트랙에 업로드.
- 내부 테스터 이메일 또는 Google Group 최소 1개 추가.

## 운영 심사 전

- Android 실기기 E2E 테스트 수행.
- 테스트 번호가 아닌 실제 번호로 SMS 로그인 검증.
- 마이크 녹음과 Deepgram transcript 품질 검증.
- foreground, background, terminated 상태의 푸시 알림 검증.
- 음성 보존기간 만료 시 transcript는 유지되고 audio만 삭제되는지 검증.
- 로컬 정책 문서 참조를 공개 URL로 교체.
