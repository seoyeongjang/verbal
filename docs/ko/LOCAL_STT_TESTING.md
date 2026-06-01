# 로컬 STT 테스트

Google Play 등록 전, Firebase Functions 배포 전에도 로컬 PC에서 실제 Deepgram 음성-텍스트 변환 경로를 테스트할 수 있는 모드입니다.

## 테스트하는 경로

로컬 STT 경로는 다음과 같습니다.

```text
Flutter 웹 녹음 -> 로컬 Node STT 서버 -> Deepgram Pre-recorded Audio API -> Flutter 전송 전 확인 화면 -> 채팅 메시지
```

이 모드에서 검증하는 항목:

- 로컬 PC 마이크 권한 및 녹음
- Deepgram 기반 한국어 음성 인식 품질
- 확인 후 전송 화면의 transcript 검토
- 즉시 전송의 처리 중 상태에서 완료 상태로 바뀌는 흐름
- 로컬 음성 재생
- 스토어 스크린샷과 내부 테스트 전에 필요한 UI 동작

이 모드는 Firebase Phone Auth, Firebase Storage, Cloud Functions 배포, FCM, 운영 Firestore rules를 검증하지 않습니다.

## 1회 설정

저장소 루트에 로컬 비밀 파일을 만듭니다.

```powershell
Copy-Item .env.example .env.local
notepad .env.local
```

다음 값을 설정합니다.

```text
DEEPGRAM_API_KEY=...
DEEPGRAM_MODEL=nova-3
DEEPGRAM_LANGUAGE=ko-KR
DEEPGRAM_SMART_FORMAT=true
DEEPGRAM_KEYTERMS=
LOCAL_STT_PORT=8787
```

Deepgram 무료 크레딧은 초기 베타 테스트에 적합합니다. 테스트 대상을 늘리기 전에 Deepgram 대시보드에서 사용량을 확인하세요.

특정 한국어 이름, 제품명, 방 이름이 반복해서 틀리면 쉼표로 구분한 keyterm을 추가합니다.

```text
DEEPGRAM_KEYTERMS=민지,보이스메신저,voice_messenger
```

## 실행

저장소 루트에서 실행합니다.

```powershell
.\scripts\run-local-stt-web.ps1
```

브라우저에서 엽니다.

```text
http://127.0.0.1:55173
```

스크립트가 시작하는 항목:

- 로컬 STT 서버: `http://127.0.0.1:8787/transcribe`
- `VOICE_MESSENGER_LOCAL_STT=true`로 실행되는 Flutter 웹 앱

## 테스트 순서

1. `데모로 시작`을 클릭합니다.
2. `민지` 채팅방을 엽니다.
3. 전송 모드는 `확인 후 전송`으로 둡니다.
4. 마이크 버튼을 누릅니다.
5. 브라우저의 마이크 권한을 허용합니다.
6. `민지야 지금 뭐해?` 같은 짧은 한국어 문장을 말합니다.
7. 녹음을 정지합니다.
8. 확인 화면에 인식된 transcript가 표시되는지 확인합니다.
9. 필요하면 텍스트를 수정하고 전송합니다.
10. 보낸 음성 말풍선에 최종 텍스트가 함께 표시되는지 확인합니다.
11. 우측 상단 전송 모드를 `즉시 전송`으로 바꿉니다.
12. 다른 문장을 녹음합니다.
13. 음성 말풍선이 먼저 처리 중 상태로 보인 뒤 transcript로 업데이트되는지 확인합니다.

## 문제 해결

- 확인 화면에 계속 `음성 메시지 초안입니다`가 나오면 일반 데모 모드로 실행 중입니다. `.\scripts\run-local-stt-web.ps1`로 다시 실행합니다.
- `DEEPGRAM_API_KEY is not configured`가 나오면 `.env.local`에 키를 추가합니다.
- 브라우저가 STT 서버에 연결하지 못하면 `dist/logs/local-stt-server.err.log`를 확인합니다.
- 마이크 권한 창이 나오지 않으면 Chrome/Edge 사이트 설정에서 `127.0.0.1`의 마이크 권한을 허용합니다.
- transcript 품질이 낮으면 먼저 짧은 문장으로 테스트하고, 조용한 환경과 소음 환경을 나누어 비교합니다.

## 운영 경로

운영 STT 경로는 다음과 같습니다.

```text
Flutter 모바일 앱 -> Firebase Storage -> createTranscriptionDraft Cloud Function -> Deepgram STT -> Firestore 메시지
```

이 경로는 Firebase Blaze 업그레이드, Storage, Functions 배포, Firebase Functions secret으로 `DEEPGRAM_API_KEY` 설정이 필요합니다.
