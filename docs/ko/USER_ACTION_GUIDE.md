# 사용자 조치 가이드

이 문서는 계정 소유권, 결제 동의, 비밀 키, Apple/Firebase 콘솔 접근이 필요한 남은 작업을 정리합니다.

## 1. Firebase를 Blaze로 업그레이드

프로젝트: `voice-messenger-jangs-260522`

열기:

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/usage/details`

절차:

1. `Modify plan` 또는 `Upgrade`를 클릭합니다.
2. `Blaze`를 선택합니다.
3. 유효한 결제 계정을 연결합니다.
4. 계속 진행하기 전에 예산 알림을 설정합니다.

권장 예산 관리:

- 낮은 초기 월 예산 알림을 만듭니다.
- 50%, 80%, 100% 알림을 추가합니다.
- E2E 테스트 실행 후 Firebase 사용량을 확인합니다.

필요한 이유:

- 새 Firebase Storage 기본 버킷은 Blaze가 필요합니다.
- Cloud Functions v2 배포에는 Cloud Build, Artifact Registry, Cloud Run, Eventarc, Secret Manager 같은 API가 필요합니다.
- 음성 STT 호출은 Deepgram 크레딧을 소모합니다.

## 2. Firebase 전화번호 인증 활성화

열기:

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/authentication/providers`

절차:

1. Authentication이 아직 초기화되지 않았다면 `Get started`를 클릭합니다.
2. `Sign-in method`를 엽니다.
3. `Phone`을 선택합니다.
4. `Phone`을 활성화합니다.
5. 개발용 테스트 전화번호를 추가합니다.

권장 테스트 설정:

- 한국 테스트 번호를 최소 1개 추가합니다.
- QA에는 Firebase 테스트 인증 코드를 사용합니다.
- 개발 중 실제 SMS를 반복 사용하지 않습니다.

Android debug 인증서는 이미 등록되어 있습니다.

- SHA-1: `03:39:23:1A:41:06:49:9B:49:13:4A:16:85:7F:CE:E7:BA:91:5F:47`
- SHA-256: `58:26:BC:1D:D1:BC:EF:D8:DD:64:C5:CE:4C:6A:7D:28:25:60:58:C3:40:46:F4:58:93:20:A8:9B:CA:01:44:9A`

## 3. Firebase Storage 버킷 생성

Blaze가 활성화된 뒤 아래 주소를 엽니다.

`https://console.firebase.google.com/project/voice-messenger-jangs-260522/storage`

절차:

1. `Get started`를 클릭합니다.
2. 위치는 `asia-northeast3`를 선택합니다.
3. 설정을 완료합니다.

또는 `DEEPGRAM_API_KEY`를 설정한 뒤 이 저장소의 재개 스크립트를 실행하면, 기본 버킷이 없을 때 스크립트가 생성을 시도합니다.

## 4. Deepgram API key 준비

MVP 백엔드에 사용할 Deepgram API key를 생성하거나 선택합니다.

배포 전에 PowerShell에서 설정합니다.

```powershell
$env:DEEPGRAM_API_KEY = "..."
```

키를 저장소에 커밋하지 마세요.

배포 스크립트는 이 키를 `DEEPGRAM_API_KEY`라는 Firebase Functions secret으로 저장합니다.

## 5. 백엔드 배포 재개

Blaze, Phone Auth, Storage 설정, Deepgram key 준비가 끝난 뒤 실행합니다.

```powershell
cd "C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger"
$env:DEEPGRAM_API_KEY = "..."
.\scripts\deploy-after-user-actions.ps1
```

스크립트가 수행하는 작업:

- 결제 활성화 여부 확인.
- Functions 관련 API 활성화.
- 기본 Firebase Storage 버킷이 없으면 생성.
- Functions 빌드.
- Storage rules 배포.
- `DEEPGRAM_API_KEY`를 Functions secret으로 설정.
- Cloud Functions 배포.

## 6. 실제 E2E QA 실행

백엔드 배포 후 실행합니다.

```powershell
cd "C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile"
C:\Users\jangs\develop\flutter\bin\flutter.bat run
```

확인 항목:

- Firebase 테스트 번호로 전화번호 로그인.
- 프로필 설정.
- 아이디 등록.
- 대화방 생성.
- 텍스트 메시지 전송.
- 음성 녹음.
- 확인 후 전송 모드의 전사와 전송.
- 즉시 전송 모드의 pending 메시지와 전사 결과 업데이트.
- 음성 재생.
- 두 번째 기기에서 푸시 알림 수신.

## 7. Android 릴리스 업로드

Google Play Console 1회 등록비는 이미 지불되었습니다.

이미 생성된 파일:

`dist/android/app-release.aab`

Play Console 업로드 전 확인:

1. Google Play Console에서 새 앱을 생성합니다.
2. 앱 이름, 기본 언어, 앱/게임 여부, 무료/유료 여부를 입력합니다.
3. 앱 콘텐츠, 데이터 보안, 개인정보 처리방침 URL, 대상 연령, 광고 여부를 입력합니다.
4. 내부 테스트 트랙을 생성합니다.
5. `dist/android/app-release.aab`를 업로드합니다.
6. upload key 파일을 안전하게 보관합니다.
   - `apps/mobile/android/app/upload-keystore.jks`
   - `apps/mobile/android/key.properties`
7. 의도적으로 교체하는 경우가 아니라면 upload key를 삭제하거나 재생성하지 않습니다.

## 8. iOS TestFlight

이 작업은 macOS, Xcode, Apple Developer 계정이 필요합니다.

절차:

1. macOS에서 `apps/mobile/ios/Runner.xcworkspace`를 엽니다.
2. bundle ID `com.voicebeta.voiceMessenger`에 대한 team signing을 설정합니다.
3. Firebase Console에 APNs key/certificate를 추가합니다.
4. Xcode에서 archive를 빌드합니다.
5. App Store Connect에 업로드합니다.
6. TestFlight로 배포합니다.

Firebase iOS 앱은 이미 등록되어 있습니다.

- Bundle ID: `com.voicebeta.voiceMessenger`
- App ID: `1:203811587610:ios:25d3ef7152d835c720f3a3`
