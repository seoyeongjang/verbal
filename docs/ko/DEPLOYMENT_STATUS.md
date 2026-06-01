# 배포 상태

원문: `docs/DEPLOYMENT_STATUS.md`

## 완료된 작업

- Google Cloud/Firebase 프로젝트 생성: `voice-messenger-jangs-260522`.
- 로컬 ADC quota project를 `voice-messenger-jangs-260522`로 설정.
- Firebase 프로젝트 활성화.
- Firestore 기본 데이터베이스 생성: `asia-northeast3`.
- Firestore rules와 indexes 배포.
- Firebase Android 앱 등록:
  - Package: `com.voicebeta.voice_messenger`
  - App ID: `1:203811587610:android:713b3d7faece49f920f3a3`
- Firebase iOS 앱 등록:
  - Bundle ID: `com.voicebeta.voiceMessenger`
  - App ID: `1:203811587610:ios:25d3ef7152d835c720f3a3`
- Firebase 앱 설정 파일 다운로드:
  - `apps/mobile/android/app/google-services.json`
  - `apps/mobile/ios/Runner/GoogleService-Info.plist`
- 실제 Firebase 모드용 Flutter `DefaultFirebaseOptions` 추가.
- Android debug SHA-1/SHA-256 인증서 등록.
- Android upload keystore 로컬 생성:
  - `apps/mobile/android/app/upload-keystore.jks`
  - `apps/mobile/android/key.properties`
- Android release bundle 생성:
  - `dist/android/app-release.aab`
  - 2026-05-28 최신 UI/메시징 변경 후 ASCII 빌드 경로에서 재생성.
- Google Play Console 1회 등록비 결제 완료.

## Blaze 업그레이드 후 완료

- `voice-messenger-jangs-260522` 결제 활성화 확인.
- 운영 백엔드에 필요한 API 활성화:
  - Cloud Functions
  - Cloud Build
  - Cloud Billing
  - Artifact Registry
  - Cloud Run
  - Eventarc
  - Pub/Sub
  - Cloud Scheduler
  - Secret Manager
  - Identity Toolkit
- Cloud Storage for Firebase 기본 버킷 생성/확인:
  - `voice-messenger-jangs-260522.firebasestorage.app`
  - 위치: `asia-northeast3`
- Firebase Storage rules 배포.
- `DEEPGRAM_API_KEY`를 Firebase Functions secret으로 설정.
- Identity Toolkit admin API로 Firebase Authentication Phone Number sign-in
  활성화.
- Firebase Auth SMS 없는 테스트 전화번호 설정:
  - 전화번호: `+16505550101`
  - 코드: `123456`
- 사용자 ID 정책 정규식 수정 후 Firestore rules와 indexes 재배포.
- `asia-northeast3`에 Cloud Functions 배포:
  - Deepgram STT
  - 메시지 전송/수정/삭제
  - 초대, 그룹, 신고, 차단, 반응, 고정, 방 상태 관리
  - 예약 전송
  - 음성 보존기간 만료 처리
  - 메시지 생성 기반 푸시 트리거
- 운영 Functions 배포:
  - `getOperationalHealth`
  - `rollupUsageAndCost`
- 푸시 전송 실패 시 만료된 FCM 토큰 자동 정리 추가.
- Functions 이미지용 Artifact Registry 정리 정책 설정.
- 프로젝트 단위 예산 알림 설정:
  - 월 KRW 50,000
  - 현재 지출 50%, 80%, 100% 알림
  - 예측 지출 100% 알림
- 로그 메트릭과 알림 정책 설정:
  - `voice_messenger_function_errors`
  - `voice_messenger_deepgram_errors`
  - `Voice Messenger Function Errors`
  - `Voice Messenger Deepgram Errors`
- 프로덕션 검증 스크립트 추가:
  - `scripts/configure-auth-test-phone.ps1`
  - `scripts/configure-budget-alerts.ps1`
  - `scripts/configure-logging-alerts.ps1`
  - `scripts/verify-production-backend.ps1`
- Google Play 제출 자료 준비:
  - `docs/GOOGLE_PLAY_SUBMISSION.md`
  - `docs/GOOGLE_PLAY_DATA_SAFETY.md`
  - `docs/DEVICE_FREE_VALIDATION.md`
  - `artifacts/store/google-play/`
- Firestore/Storage allow/deny 보안 규칙 테스트 추가:
  - `functions/scripts/security-rules-test.js`
  - `npm run rules:test`
- 배포 후 검증:
  - `npm run build`
  - `npm run emulators:check`
  - `npm run rules:test`
  - `firebase functions:list`
  - `scripts/verify-production-backend.ps1`
  - `DEEPGRAM_API_KEY` Secret Manager 버전 존재 확인
  - 운영 Firebase Storage 버킷 존재 확인

## 아직 필요한 콘솔/운영 작업

- iOS 푸시가 런칭 범위라면 Firebase Console에 APNs key/certificate 추가.
- Google Play Console 앱 생성, 스토어 등록정보 작성, 내부 테스트 트랙에 AAB 업로드.
- macOS, Xcode, Apple Developer 계정으로 iOS/TestFlight 빌드와 업로드.
- 공개 런칭 전 Deepgram provider 콘솔의 quota/사용량 알림 추가 확인.
- 실제 기기 운영 E2E 검증:
  - 전화번호 인증
  - 프로필 설정
  - 사용자 ID 선점
  - 방 생성
  - 텍스트 전송
  - 음성 업로드
  - Deepgram transcript 생성
  - 확인 후 전송
  - 즉시 전송
  - 첨부/위치/예약 전송
  - 번역
  - 초대 링크/QR
  - 수정/삭제/신고/차단/나가기
  - 음성 보존기간 만료 삭제

## 재배포 명령

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger
.\scripts\deploy-after-user-actions.ps1
```
## 2026-05-28 추가 배포 및 검증

- Firebase Auth SMS region allowlist 설정:
  - `KR`
  - `US` (`+16505550101` 에뮬레이터 테스트 번호용)
- Firestore `rooms` list query rule 수정 및 배포.
- `functions/scripts/security-rules-test.js`에 홈 방 목록 쿼리 테스트 추가.
- Android debug APK 재빌드 및 에뮬레이터 재설치.
- `DecisionHub_API_36`에서 회원가입 smoke test 통과:
  - test phone `+16505550101`
  - code `123456`
  - 프로필 설정 및 아이디 예약
  - 운영 Firebase 모드 홈 화면
  - Firestore permission-denied 없이 방 목록 빈 상태 표시
- smoke test 수정사항 반영 후 `dist/android/app-release.aab` 최신 소스 기준 재빌드.
- Android 에뮬레이터 마이크 흐름 확인:
  - 마이크 권한 팝업 표시
  - 권한 허용 후 녹음 중 상태 표시
  - 녹음 중지 후 확인 후 전송 시트 표시
  - 증거 파일: `artifacts/mic-permission-check.png`,
    `artifacts/mic-recording-active.png`, `artifacts/after-record-stop.png`

## 2026-05-28 운영 백엔드 E2E 검증 추가

- Firebase Auth E2E 테스트 전화번호 설정:
  - 송신자: `+16505550102` / `123456`
  - 수신자: `+16505550103` / `123456`
- 운영 백엔드 E2E smoke script 추가:
  - `functions/scripts/production-e2e-smoke.js`
  - `npm run smoke:prod-e2e`
- 운영 백엔드 E2E 통과:
  - Run ID: `20260528180740`
  - 1:1 방 생성
  - 양방향 텍스트 메시지 전송
  - 음성 draft 업로드
  - Deepgram transcript 생성
  - review-send 음성 메시지
  - 서버가 draft를 메시지 경로로 복사하는 instant-send 음성 메시지
  - FCM 만료 토큰 정리
  - 증거 파일: `artifacts/production-e2e-smoke-20260528180740.json`
- 실제 SMS 수신, 실제 마이크 녹음 품질, 실제 FCM 수신은 Android 실기기에서
  별도 검증이 필요합니다.
