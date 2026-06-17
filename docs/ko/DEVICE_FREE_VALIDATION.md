# 실기기 없는 검증 계획

원문: `docs/DEVICE_FREE_VALIDATION.md`

상태 기준일: 2026-05-28

이 계획은 Android 실기기를 확보하기 전에 완료할 수 있는 검증 범위를 정리합니다.

## 실기기 없이 완료된 항목

- Firebase Blaze 운영 백엔드 검증.
- Firebase Phone Number sign-in provider 활성화.
- Firebase Auth 테스트 전화번호 설정:
  - 전화번호: `+16505550101`
  - 코드: `123456`
- Firestore와 Storage rules 컴파일.
- Firestore와 Storage allow/deny 테스트 통과.
- Functions build 통과.
- 명시적 한국어 날짜/시간 명령에 대한 캘린더 파서 단위 테스트 통과.
- Flutter analyze와 widget test 통과.
- Flutter widget test에서 앱 내부 캘린더 일정 생성, 수정, hard delete
  demo flow 검증.
- Web demo build 통과.
- Android release AAB build 통과.
- 예산 알림과 로그 알림 정책 존재 확인.
- Android 에뮬레이터 `DecisionHub_API_36` 회원가입 smoke test 통과.
- Android 에뮬레이터에서 마이크 권한 팝업과 녹음 중 상태 확인.
- 운영 백엔드 E2E smoke test 통과: Firebase Auth test phone 2개, 1:1 방
  생성, 양방향 텍스트 전송, 음성 업로드, Deepgram transcript, 자동 음성
  전송, 즉시 백엔드 전송, FCM 만료 토큰 정리.
- 앱 내부 캘린더 데이터 모델과 Firestore rule 동작은 일정이 인증된 사용자
  문서 아래 저장되고 쓰기가 callable Functions로만 수행되므로 실기기 없이도
  검증 가능.

## 권장 에뮬레이터 Smoke Test

아래 Firebase Auth 테스트 번호로 실제 SMS 없이 회원가입 UI를 검증합니다.

1. Android 에뮬레이터 실행:

   ```powershell
   cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile
   C:\Users\jangs\develop\flutter\bin\flutter.bat emulators --launch DecisionHub_API_36
   ```

2. 앱 실행:

   ```powershell
   C:\Users\jangs\develop\flutter\bin\flutter.bat run -d emulator-5554
   ```

3. 테스트 인증 사용:
   - 전화번호: `+16505550101`
   - 코드: `123456`

4. 확인 항목:
   - 로그인 화면 표시.
   - 테스트 전화번호 로그인 성공.
   - 프로필과 사용자 아이디 설정 성공.
   - 방 목록 로드.
   - 데모가 아닌 운영 백엔드 모드 동작.

## 실기기가 필요한 항목

- 테스트 번호가 아닌 실제 번호의 SMS 수신.
- 실기기 기준 실제 마이크 녹음 품질.
- 실제 음성 입력 기반 Deepgram transcript 품질.
- 실제 마이크 입력 기반 음성 일정 추가 품질.
- foreground, background, terminated 상태의 실제 FCM 푸시 수신.
- 실제 네트워크, 배터리, OS 권한 동작.
- Play Internal Testing을 통한 스토어 설치/업데이트 동작.
## 2026-05-28 에뮬레이터 Smoke Test 결과

- 사용 에뮬레이터: `DecisionHub_API_36` (`emulator-5554`)
- 설치 빌드: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
- 테스트 인증번호:
  - 전화번호: `+16505550101`
  - 코드: `123456`
- 생성된 테스트 사용자 아이디: `smoke_0528170251`
- 확인 완료:
  - 전화번호 로그인 화면 표시
  - 실제 SMS 없이 Firebase test phone 인증번호 화면 진입
  - SMS 코드 로그인 성공
  - 신규 유저 프로필 설정 및 아이디 예약 성공
  - 운영 Firebase 모드 홈 화면 진입
  - Firestore 권한 오류 없이 방 목록 빈 상태 표시
  - Android 알림 권한 팝업 표시 및 허용 가능
- 테스트 중 수정/배포한 항목:
  - Firebase Auth SMS region allowlist에 `KR`, `US` 추가
  - 기존 handle이 빈 문자열일 때 프로필 저장이 실패하던 문제 수정
  - 홈 방 목록 쿼리를 허용하도록 Firestore `rooms` list rule 수정
  - 방 목록 쿼리 보안규칙 테스트 추가
- 증거 파일:
  - `artifacts/after-request-code-region-fixed.png`
  - `artifacts/after-login-code.png`
  - `artifacts/after-fixed-profile-submit.png`
  - `artifacts/after-firestore-rules-retry.png`
  - `artifacts/production-e2e-smoke-20260528180740.json`
  - `artifacts/mic-permission-check.png`
  - `artifacts/mic-recording-active.png`
  - `artifacts/after-record-stop.png`
