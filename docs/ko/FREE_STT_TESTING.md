# 무료 STT 테스트

Deepgram 크레딧을 쓰지 않고 음성-텍스트 변환 UX를 테스트할 때 사용하는
모드입니다.

## 동작 방식

현재 무료 경로는 두 런타임을 지원합니다.

```text
Flutter web -> Chrome/Edge Web Speech API -> transcriptOverride -> 메시지 전송
Android app -> Android SpeechRecognizer -> transcriptOverride -> 메시지 전송
```

무료 transcript가 확보되면 앱은 이를 `transcriptOverride`로 전송합니다. 이 경우
`sendInstantVoiceMessage`는 Deepgram을 호출하지 않고 transcript가 완료된 음성
메시지를 생성할 수 있습니다. 무료 recognizer가 실패하거나 빈 결과를 반환하면
음성 메시지는 그대로 전송되고, 기존 서버 STT fallback이 설정되어 있을 때 그
경로가 처리합니다.

이 기능은 유료 클라우드 WebSocket STT 엔진이 아닙니다. Deepgram Streaming STT로
넘어가기 전, 체감 지연을 줄이기 위한 무료 기기/브라우저 기반 실시간형 검증
경로입니다.

## 웹 실행

repo root에서 실행합니다.

```powershell
.\scripts\run-free-stt-web.ps1
```

접속 주소:

```text
http://127.0.0.1:55173
```

## Android 실행

Android 앱은 일반 빌드/실행만 하면 무료 STT가 기본 활성화됩니다. fallback만
테스트하고 싶으면 아래처럼 비활성화할 수 있습니다.

```powershell
flutter run --dart-define=VERBAL_FREE_STT=false
```

## 테스트 순서

1. 앱을 열고 채팅방에 들어갑니다.
2. 마이크 버튼을 누릅니다.
3. 마이크 권한을 허용합니다.
4. 짧은 메시지를 말합니다.
5. 전송 버튼 또는 정지 버튼을 누릅니다.
6. 음성 메시지가 즉시 전송되는지 확인합니다.
7. 무료 STT가 음성을 인식한 경우 확인 시트 없이 transcript가 표시되는지
   확인합니다.
8. 캘린더 화면에서도 `올해 7월 3일 오후 2시에 데모 리뷰 일정 추가해줘`처럼
   말해 테스트합니다.

## 한계

- Android `SpeechRecognizer` 품질은 기기, OS, 언어팩, Google 앱 사용 가능 여부,
  네트워크/오프라인 인식 설정에 따라 달라집니다.
- 브라우저 인식은 Chrome/Edge Web Speech API 지원 여부에 의존합니다.
- 무료 STT는 UX 검증에 적합하지만, 운영 수준의 서버 제어형 저지연 STT는 추후
  Deepgram Streaming STT로 검증해야 합니다.
- 무료 recognizer가 transcript를 반환하지 못하면, backend 설정에 따라 기존 서버
  STT fallback이 Deepgram 사용량을 소모할 수 있습니다.
