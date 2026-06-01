# 로컬 테스트

이 프로젝트는 Google Play 등록 전에도 Flutter 앱을 웹 또는 Windows 데스크톱 데모 모드로 테스트할 수 있습니다.

## 웹 데모

실행:

```powershell
.\scripts\run-local-web.ps1
```

브라우저에서 엽니다.

```text
http://127.0.0.1:55173
```

해당 포트가 이미 사용 중이면 다른 포트를 넘깁니다.

```powershell
.\scripts\run-local-web.ps1 -Port 55174
```

이 스크립트는 `VOICE_MESSENGER_DEMO=true`를 강제로 적용합니다. 따라서 Firebase Auth, Firebase Storage, Cloud Functions, Deepgram API key, Google Play 앱 등록 없이 실행됩니다.

고정 데모 transcript가 아니라 실제 음성-텍스트 변환을 테스트하려면 `docs/ko/LOCAL_STT_TESTING.md`를 참고하고 아래 명령을 실행합니다.

```powershell
.\scripts\run-local-stt-web.ps1
```

Deepgram 크레딧을 소모하지 않고 음성-텍스트 변환 UX를 테스트하려면 `docs/ko/FREE_STT_TESTING.md`를 참고하고 아래 명령을 실행합니다.

```powershell
.\scripts\run-free-stt-web.ps1
```

빠른 MVP 확인 항목:

- 데모 로그인
- 방 목록
- 채팅 화면
- 텍스트 메시지 전송
- 마이크 권한 요청
- 음성 녹음
- 확인 후 전송 흐름
- 즉시 전송 처리 중 흐름
- 로컬 음성 재생

## Windows 데스크톱 데모

실행:

```powershell
.\scripts\run-local-windows.ps1
```

이 모드도 데모 모드를 사용합니다. Windows 데스크톱 빌드는 Visual Studio의 Desktop development with C++ 워크로드가 필요할 수 있습니다. 해당 도구가 없으면 웹 데모를 먼저 사용하세요.

Windows에서 Flutter 플러그인은 symlink 지원을 위해 Developer Mode가 필요합니다. 빌드 중 `Building with plugins requires symlink support`가 출력되면 Windows Settings > System > For developers에서 Developer Mode를 켠 뒤 다시 실행합니다.

## 정적 웹 빌드

실행:

```powershell
.\scripts\build-local-web.ps1
```

빌드 결과:

```text
apps/mobile/build/web
```

로컬에서 빌드 결과를 서빙하려면:

```powershell
.\scripts\serve-built-web.ps1
```

브라우저에서 엽니다.

```text
http://127.0.0.1:55173
```

## 범위

로컬 데모 모드는 스토어 등록 전 UI/UX 검증용입니다. 실제 Firebase 백엔드, 실제 전화번호 인증, 실제 Cloud Functions, 실제 Storage 업로드, FCM, Deepgram STT는 검증하지 않습니다. 이 항목들은 남은 Firebase Blaze 및 API key 설정 이후에 검증해야 합니다.
