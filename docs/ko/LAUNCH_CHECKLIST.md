# 런칭 체크리스트

원문: `docs/LAUNCH_CHECKLIST.md`

상태 기준일: 2026-06-04

이 문서는 현재 Verbal MVP의 구현 현황과 공개 런칭 전 남은 작업을
추적합니다. 현재 앱은 로컬 테스트와 제한된 클로즈드 베타를 진행할 수 있는
수준이지만, P0 항목이 끝나기 전에는 공개 런칭 준비가 완료된 상태가 아닙니다.

관련 리뷰: `docs/ko/MESSENGER_FUNCTION_AND_LAUNCH_REVIEW.md`에는
인스타그램 DM, 카카오톡, 텔레그램과 비교한 추가 기능 리스트와 런칭 준비
gap을 정리했습니다.

## 구현 완료된 제품 기능

### 계정과 프로필

- [x] 모바일 앱의 전화번호 인증 플로우.
- [x] 로그인 후 프로필 설정.
- [x] Firestore 기반 사용자 아이디/handle 선점.
- [x] 아이디 정책: 3-30자, 한글, 영어, 일본어, 중국어, 숫자, 언더바 허용.
- [x] 앱 코드, Firebase 백엔드 코드, Firestore rules에 아이디 검증 반영.
- [x] 앱 내 계정 데이터 내보내기.
- [x] 앱 내 계정 삭제 흐름.

### 메신저 홈

- [x] Instagram DM 무드의 홈 레이아웃: 노트, 탭, 방 목록, 카메라 액션.
- [x] 초록색 앱 컬러 시스템과 아바타 그라데이션 무드.
- [x] 메시지, 채널, 요청 탭.
- [x] 개인 대화방 내부가 아닌 외부 영역의 네이티브 광고 슬롯.
- [x] 방 목록 스와이프 액션: 고정, 음소거, 삭제/나가기, 방 관리 흐름.
- [x] 1:1 방과 그룹 방 진입 흐름.

### 채팅과 보이스 메시지

- [x] 텍스트 메시지 전송과 실시간 방 업데이트.
- [x] 음성 녹음 흐름.
- [x] 비용 없는 UX 테스트용 브라우저 무료 STT 모드.
- [x] Firebase Functions 배포 전 실제 품질 확인용 로컬 Deepgram STT 모드.
- [x] Firebase Functions 기반 Deepgram STT 경로 코드 구현.
- [x] 음성 STT 완료 후 확인 시트 없이 자동 전송.
- [x] STT 완료 후 자동 음성 전송 모드.
- [x] STT 실패 시 기본 문구를 임의로 넣지 않도록 처리.
- [x] STT 실패 시 재시도와 직접 transcript 입력 전송 복구.
- [x] 음성 메시지 transcript 확인 시트 제거.
- [x] 앱 레이어의 한글/UTF-8 transcript 표시 문제 수정.
- [x] 메시지 답장.
- [x] 메시지 반응.
- [x] 메시지 고정/고정 해제.
- [x] 메시지 본문, transcript, 번역문 검색.
- [x] 보낸 메시지 수정과 `수정됨(edited)` 표시.
- [x] 보낸 메시지 흔적 없는 삭제.
- [x] 메시지 말풍선 최대 너비를 화면의 80%로 제한하고 짧은 메시지는 내용에
  맞게 자동 축소.
- [x] 음성과 첨부 전송 중 진행 상태 표시.
- [x] 읽음 상태와 읽음 처리.

### 첨부와 편의 기능

- [x] 이미지 첨부.
- [x] 파일 첨부.
- [x] 위치 공유.
- [x] 예약 텍스트 메시지.
- [x] 기본 preset 없는 예약 전송 UI: 사용자가 직접 날짜와 시간을 선택.
- [x] 메시지 번역.
- [x] 방 단위 음성파일 보존기간 설정.
- [x] 기본 음성 보존기간 1일, 만료 후 음성파일 삭제와 transcript 유지 정책.
- [x] 제품 정책상 일일 텍스트 개수 제한 없음.
- [x] 제품 정책상 일일 음성 개수 제한 없음.
- [x] 제품 정책상 고정 음성 길이 제한 없음.

### 그룹, 초대, 안전 기능

- [x] 아이디 기반 방 생성.
- [x] 초대 링크 생성과 폐기.
- [x] 방 초대 QR 코드 표시.
- [x] 초대 승인 모드.
- [x] 초대 링크/코드로 참여.
- [x] 멤버 역할: 소유자, 관리자, 멤버.
- [x] 멤버 역할 변경.
- [x] 멤버 내보내기.
- [x] 방 나가기.
- [x] 사용자 차단.
- [x] 메시지 신고.
- [x] 방 신고.
- [x] 정상 메시지/음성 사용량 제한 없이 초대 생성, 초대 참여, 신고, 차단 등
  민감 액션 cooldown 적용.

## 구현 완료된 백엔드와 운영 기반

- [x] users, handles, rooms, messages, members, invites, reports, usage events,
  transcription cache용 Firestore 데이터 모델.
- [x] Firestore 보안 규칙.
- [x] Firestore indexes.
- [x] Firebase Storage rules.
- [x] 방 생성, 초대, 메시지 전송/수정/삭제, 예약 전송, Deepgram STT, 번역,
  신고, 푸시 알림, 계정 내보내기/삭제, 음성 만료 처리를 위한 Cloud Functions
  소스.
- [x] Cloud Functions 소스의 음성 보존기간 만료 작업.
- [x] 중복 STT 처리를 줄이기 위한 SHA-256 기반 transcription cache.
- [x] 텍스트, 음성, STT, 비용 모니터링용 usage logging hook.
- [x] 중복 신고 누적과 모더레이션 준비용 신고 필드.
- [x] Android Firebase 앱 등록.
- [x] iOS Firebase 앱 등록.
- [x] Android upload keystore 로컬 생성.
- [x] Android release bundle 이전 생성.
- [x] 로컬/demo 웹 프리뷰 스크립트.
- [x] 무료 브라우저 STT 테스트 스크립트.
- [x] 로컬 Deepgram STT 테스트 스크립트.
- [x] SMS 없는 에뮬레이터/웹 검증용 Firebase Auth 테스트 전화번호 설정.
- [x] Firebase Auth SMS region allowlist에 `KR`, `US` 설정.
- [x] Android 에뮬레이터 회원가입 smoke test 통과: Firebase test phone,
  프로필 설정, 아이디 예약, 운영 모드 홈 로드.
- [x] 운영 백엔드 E2E smoke test 통과: Firebase Auth test phone 2개,
  1:1 방 생성, 양방향 텍스트 전송, 음성 업로드, Deepgram transcript,
  자동 음성 전송, 즉시 백엔드 전송, FCM 만료 토큰 정리.
- [x] Google Play 스토어 등록 문구를 `artifacts/store/google-play`에 준비.
- [x] Google Play 제출 패키지 준비.
- [x] Google Play Data Safety 초안 준비.
- [x] 실기기 없는 검증 계획 준비.

## 부분 구현 / 프로덕션 검증 필요

- [x] 프로덕션 Deepgram STT 백엔드 경로는 자동 음성 전송과 즉시 백엔드
  전송 메시지 기준 서버 E2E로 검증되었습니다.
- [ ] 실제 기기 마이크 입력 기준 녹음 품질과 한국어 transcript 품질 검증이
  필요합니다.
- [ ] Firebase Phone Auth provider와 테스트 전화번호는 활성화되었지만 실제 SMS
  플로우는 운영 기기 검증이 필요합니다.
- [x] Firebase Storage 기본 bucket이 존재하며 Storage rules가 배포되었습니다.
- [x] FCM 서버 경로는 운영 백엔드 E2E에서 만료 토큰 정리까지 검증되었습니다.
- [ ] FCM 실제 수신은 Android 실기기에서 foreground, background, terminated
  상태 검증이 필요합니다.
- [ ] iOS 푸시는 APNs key/certificate와 TestFlight 검증이 필요합니다.
- [x] 최근 UI/메시징 변경 이후 최신 소스로 Android release bundle 재빌드 완료.
- [x] 신고 검토용 모더레이션 runbook 준비.
- [ ] 번역 기능은 제품 흐름에 있으나 프로덕션 품질과 비용 모니터링은 베타에서
  검증해야 합니다.
- [ ] 사용량 무제한 정책은 제품 레벨에 반영되어 있고 Firebase/GCP 예산/로그
  알림과 사용량 롤업은 활성화되었습니다. Deepgram 계정 단위 quota 정책은
  공개 런칭 전 provider 콘솔에서 추가 확인이 필요합니다.
- [x] 홈, 채팅, 대화 정보, 권한 문구의 주요 메신저 UI 한국어 카피 정리.

## P0 런칭 차단 항목

- [x] Firebase 프로젝트 `voice-messenger-jangs-260522`를 Blaze로 업그레이드.
- [x] Firebase Authentication Phone Number sign-in 활성화.
- [x] Cloud Storage for Firebase 기본 bucket 생성 또는 확인.
- [x] Firebase Storage rules 배포.
- [x] Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc,
  Secret Manager 활성화.
- [x] `DEEPGRAM_API_KEY`를 Firebase Functions secret으로 설정.
- [x] Cloud Functions 배포.
- [x] 최종 검토 후 Firestore rules와 indexes 재배포.
- [x] Android 에뮬레이터에서 마이크 권한 팝업과 녹음 중 상태 확인.
- [x] 운영 백엔드 E2E 실행: Firebase Auth test phone 2개, 1:1 방 생성,
  양방향 텍스트 전송, 음성 업로드, Deepgram transcript, 자동 음성 전송,
  즉시 백엔드 전송, FCM 만료 토큰 정리.
- [ ] 프로덕션 Firebase 전체 E2E 테스트: 전화번호 인증, 프로필 설정, 아이디
  선점, 방 생성, 텍스트 전송, 음성 업로드, Deepgram transcript, 자동 음성
  전송, 첨부, 위치, 예약 전송, 번역, 초대 링크/QR, 수정, 삭제, 신고,
  차단, 방 나가기.
- [ ] 실제 기기에서 STT 지연시간, 실패 처리, 한국어 transcript 품질 검증.
- [ ] transcript는 유지하면서 음성 보존기간 만료 삭제가 동작하는지 검증.
- [ ] 실제 Android 기기에서 FCM 푸시 검증.
- [ ] iOS 런칭이 범위에 포함된다면 APNs 설정과 iOS 푸시 검증.
- [x] 음성 자동 전송과 음성 일정 자동 저장 변경 이후 최신 소스 기준 Android
  release AAB 재빌드.
- [ ] Google Play Console 앱 listing 생성과 internal testing 업로드.
- [ ] Play Console에서 Google Play Data Safety 작성.
- [x] 개인정보처리방침, 이용약관, 계정/데이터 삭제 정책 초안 준비.
- [x] Firebase/GCP 예산, 비용 알림, logging alert, Deepgram 사용량 모니터링
  설정.
- [x] Firestore/Storage 보안 규칙 allow/deny 테스트와 보안 감사.
- [x] 마이크, 알림, 사진, 파일, 위치 권한 안내 문구 초안 검토.
- [x] 소형 Android, 대형 Android, 저사양 기기, 느린 네트워크 환경의 클로즈드
  베타 QA 계획 준비.

## P1 공개 베타 전 보강 항목

- [x] 신고 처리를 위한 내부 모더레이션 운영 문서화.
- [x] 계정 삭제와 데이터 내보내기 흐름 추가.
- [x] 정상 사용자 메시지 개수 제한이 아닌 초대 악용과 스팸 억제 장치 추가.
- [x] STT 재시도와 수동 transcript 복구 상태 개선.
- [x] 방 목록과 채팅 stream 실패에 대한 오프라인/재연결 UI 상태 추가.
- [x] composer 액션 기준 미디어 업로드/전송 진행률, 재시도, 실패 상태 추가.
- [x] 대비, 터치 영역, 스크린리더, 텍스트 확대 접근성 점검 문서화.
- [x] 주요 메신저 버튼, 시트, 메뉴, 오류 문구의 한국어 카피 정리.
- [x] Crashlytics와 Analytics event taxonomy 문서 추가.
- [x] 실제 DAU, 음성 길이, STT 오류율, 재생률을 반영할 부하/비용 시뮬레이션
  모델 준비.
- [x] 로그인, STT 실패, 계정 분실, 신고 처리, 데이터 삭제용 고객지원 매크로
  준비.

## 현재 검증 명령

아래 명령은 MVP 검증 중 사용한 명령이며, 배포 대상 변경 이후 다시 실행해야
합니다.

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\apps\mobile
C:\Users\jangs\develop\flutter\bin\flutter.bat analyze
C:\Users\jangs\develop\flutter\bin\flutter.bat test

cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run test:calendar-parser
npm run build
npm run emulators:check
npm run rules:test
npm run smoke:prod-e2e

cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger
.\scripts\build-free-stt-web.ps1
.\scripts\verify-production-backend.ps1
```

## 런칭 판단

현재 판단: 아직 공개 런칭하면 안 됩니다.

MVP는 로컬 프리뷰, 무료 STT UX 테스트, 로컬 Deepgram STT 테스트, 제한된 Firebase
준비까지는 진행할 수 있습니다. 공개 런칭은 모든 P0 차단 항목을 끝내고 실제
기기에서 프로덕션 E2E 경로를 검증한 뒤 진행해야 합니다.
## 2026-05-28 체크리스트 업데이트

- [x] Firebase Auth SMS region allowlist에 `KR`, `US` 설정.
- [x] Android 에뮬레이터 `DecisionHub_API_36`에서 Firebase test phone 회원가입 smoke test 통과.
- [x] 신규 유저 프로필 설정, 아이디 예약, 운영 Firebase 모드 홈 화면 로딩 확인.
- [x] 홈 방 목록 쿼리 Firestore rules 수정/배포 및 보안규칙 테스트 추가.
- [x] smoke test 수정사항 반영 후 Android release AAB 재빌드.
- [x] 운영 백엔드 E2E에서 방 생성, 양방향 텍스트, 음성 업로드, Deepgram STT,
  자동 음성 전송, 즉시 백엔드 전송, FCM 만료 토큰 정리 통과.
- [ ] 실제 기기에서 실제 SMS, 마이크 녹음, Deepgram STT 품질, FCM foreground/background/terminated 검증 필요.
- [ ] 전체 운영 E2E는 아직 실제 기기 기준으로 남아 있음.

## 2026-05-28 캘린더 기능 업데이트

- [x] 채팅 메시지 composer와 분리된 앱 내부 캘린더 화면 추가.
- [x] 음성 일정 추가 flow 구현: STT, 명시적 한국어 날짜/시간 파싱,
  완전한 명령은 자동 저장, 불완전한 명령은 재시도 안내.
- [x] 직접 일정 추가/수정/hard delete UI 구현. 제목과 상세 내용 모두 수정 가능.
- [x] 일정은 채팅 메시지 컬렉션이 아닌 `users/{uid}/calendarEvents`에 저장.
- [x] Cloud Functions `createCalendarIntentDraft`, `createCalendarEvent`,
  `updateCalendarEvent`, `deleteCalendarEvent` 구현.
- [x] Firestore rules에서 본인 일정 read만 허용하고 client write 차단.
- [x] 런칭 전 전체 E2E 범위에 음성 일정 추가와 일정 수정/삭제 검증 추가.

## 2026-06-04 업데이트

- [x] 제품 브랜드명을 `Verbal`로 확정하고 앱 표시명,
  스토어 문서, 제품 문서, 고객지원 문서, 로컬 스크립트, 데모 asset에 반영했습니다.
- [x] 기존 Firebase project ID, Android package ID, iOS bundle ID, native
  method-channel 이름은 현재 운영 백엔드 연결을 유지하기 위해 변경하지 않았습니다.
- [x] 음성 캘린더 STT가 제목/날짜/시간을 모두 파싱하면 일정 추가 시트 없이
  자동 저장합니다.
- [x] 음성 캘린더 자동 저장 성공 후 완료 음성 안내를 실행합니다.
- [x] 음성 메시지는 STT 완료 후 transcript 확인 시트 없이 자동 전송합니다.
- [x] 제품, QA, 운영, 고객지원, 스토어, 데이터 모델, 런칭 문서를 자동 전송
  기준으로 갱신했습니다.
- [x] 최신 소스로 Android release AAB를 다시 빌드하고
  `dist/android/app-release.aab`에 복사했습니다.
- [ ] 다음: 실기기에서 실제 발화 기준 음성 메시지 STT 자동 전송과 음성 일정
  자동 저장 검증.
- [ ] 다음: 실기기 FCM foreground/background/terminated 푸시 검증.
- [ ] 다음: transcript 보존 상태에서 음성파일 보존기간 만료 삭제 검증.
- [ ] 다음: Google Play internal testing 앱 등록과 Data Safety form 작성.
