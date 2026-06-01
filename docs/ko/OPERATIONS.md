# 운영

## Firebase 체크리스트

- Firebase 프로젝트를 만들고 `.firebaserc` 기본 프로젝트를 교체합니다.
- Authentication 전화번호 제공자를 활성화합니다.
- Android SHA-1/SHA-256 지문을 전화번호 인증에 추가합니다.
- Firestore, Cloud Storage, Cloud Functions, Cloud Messaging을 활성화합니다.
- 베타 테스트 전 규칙과 인덱스를 배포합니다.
- `DEEPGRAM_API_KEY` Functions secret을 설정합니다.

## Deepgram STT

- 기본 모델: `nova-3`.
- 언어 힌트: `ko-KR`.
- Smart formatting: `DEEPGRAM_SMART_FORMAT=true`일 때 기본 활성화.
- 선택 keyterm prompting: 자주 오인식되는 이름과 제품 용어를 `DEEPGRAM_KEYTERMS`에 쉼표로 구분해 설정합니다.
- 현재 경로는 녹음 후 파일 transcription입니다. 실시간 부분 자막은 추후 Realtime transcription으로 추가합니다.
- STT 호출은 일일 건수로 제한하지 않습니다. 일일 사용량은 비용 모니터링 목적으로만 기록합니다.
- 음성 메시지 길이는 무제한입니다. 0.5초 미만 녹음은 비어 있거나 너무 짧은 입력으로 거절합니다.
- 중복 음성 해시는 `transcriptionCache`로 캐싱합니다.

## 보존기간 및 원가 통제

- 방 기본 음성파일 보존기간은 1일입니다.
- 방 관리자는 1일, 7일, 사용자 지정 1-30일 중 선택할 수 있습니다.
- `expireVoiceAudio`는 매시간 만료된 음성파일을 삭제하고 transcript는 유지합니다.
- Storage rules는 음성 업로드에 고정 용량 제한을 두지 않습니다.
- 베타 확대 전 `usageDaily`, `audioRetentionStatus`, `sttCacheHit`를 확인합니다.

## 베타 모니터링

- 함수 이름별 callable function 오류를 추적합니다.
- draft 생성부터 완료까지 STT 지연시간을 추적합니다.
- `sttStatus = failed` 메시지 문서를 추적합니다.
- 일일 텍스트/음성 사용량과 비용 추세 이상치를 추적합니다.
- STT 캐시 적중률과 평균 음성 길이를 추적합니다.
- 만료 음성파일 삭제 성공률을 추적합니다.
- `onMessageCreated` 로그에서 FCM 실패 수를 확인합니다.
- 비공개 베타 동안 신고 문서를 매일 확인합니다.

## 수동 QA

- Android 실기기 전화번호 인증.
- iOS 실기기 전화번호 인증.
- 조용한 환경의 한국어 음성.
- 소음이 있는 환경의 한국어 음성.
- 3초 미만 짧은 음성.
- 긴 음성 녹음과 재생.
- 확인 후 전송 모드의 transcript 수정.
- 즉시 전송 모드의 처리 중 상태와 transcript 업데이트.
- 보존기간 만료 후 음성파일 삭제 및 transcript 유지.
