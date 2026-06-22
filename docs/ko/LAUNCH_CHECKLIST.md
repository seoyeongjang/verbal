# 런칭 체크리스트

원문: `docs/LAUNCH_CHECKLIST.md`

상태 기준일: 2026-06-19

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
- [x] 메시지, 채널 탭. 요청 메시지는 사용자 메뉴로 이동.
- [x] 개인 대화방 내부가 아닌 외부 영역의 네이티브 광고 슬롯.
- [x] 방 목록 스와이프 액션: 고정, 음소거, 삭제/나가기, 방 관리 흐름.
- [x] 통합 채팅 생성: 친구 1명 선택 시 1:1, 2명 이상 선택 시 그룹 생성.
- [x] 등록 친구 초대와 공유 가능한 링크/QR을 포함한 오픈채팅 생성.
- [x] 홈 전체 검색 v1: 방, 메시지 본문, 음성 transcript, 첨부 metadata,
  캘린더 일정 검색.

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
- [x] 텍스트 링크 발신 전 의심 링크/피싱 경고.

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
  1:1 방 생성, 양방향 텍스트, 메시지 수정/삭제, 반응, 고정/해제, 예약 전송,
  파일 첨부, 위치 메시지, 번역, 음성 업로드, Deepgram transcript, 음성 자동
  전송, 즉시 백엔드 전송, 음성 캘린더 일정 생성/수정/삭제, 채팅방 일정 제안
  투표/확정, 오픈채팅 초대 링크 입장/나가기, 신고, 차단, FCM 만료 토큰 정리.
- [x] Google Play 스토어 등록 문구를 `artifacts/store/google-play`에 준비.
- [x] Google Play 제출 패키지 준비.
- [x] Google Play closed testing 운영 pack 준비: tester CSV, 초대 문구,
  피드백 질문, issue template, 증거 기록 명령.
- [x] Play 심사용 전화번호 로그인 접근 안내 준비.
- [x] Play App content 입력 워크시트 준비: app access, 광고, Data Safety,
  계정 삭제, 대상 연령, 콘텐츠 등급, 민감 권한, UGC 선언.
- [x] Google Play Data Safety 초안 준비.
- [x] 실기기 없는 검증 계획 준비.
- [x] Android 릴리즈 artifact/서명 검증기 준비.
- [x] 런칭 게이트 리포트 생성기 준비.
- [x] Play Console과 실기기 증거 기록을 위한 수동 런칭 증거 템플릿 준비.
- [x] Play Console, 실기기 E2E, FCM 증거 필드 누락 여부를 보고하는 수동
  런칭 증거 검증기 준비.
- [x] build, store asset, Android release 검증, launch readiness, Play Console
  pack, closed testing pack, 증거 템플릿, 증거 구조 확인, launch gate, launch
  handoff를 한 번에 실행하는 preinternal release check 준비.
- [x] Play Console, closed testing, 실기기 E2E, FCM, launch evidence 기록
  단계를 `artifacts/launch-handoff-latest.md` 한 파일로 정리하는 launch
  handoff pack 준비.
- [x] AAB, Play Console pack, launch gate, handoff가 같은 릴리즈 후보를
  설명해야 통과하는 launch consistency verifier 준비.
- [x] 엄격한 launch evidence와 `readyForPublicUserExposure`가 통과하기 전에는
  프로덕션/일반 공개가 실패하도록 public release hard gate 준비.
- [x] Android 실기기 QA 증거 수집 스크립트와 가이드 준비.

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
- [x] 최종 검토 후 Firestore rules와 indexes 재배포. 2026-06-18 최신 배포에는
  회원가입 정책 동의 필드가 포함됨.
- [x] Android 에뮬레이터에서 마이크 권한 팝업과 녹음 중 상태 확인.
- [x] 운영 백엔드 E2E 실행: Firebase Auth test phone 2개, 1:1 방 생성,
  양방향 텍스트 전송, 메시지 수정/삭제, 반응, 고정/해제, 예약 전송, 파일 첨부,
  위치 메시지, 번역, 음성 업로드, Deepgram transcript, 자동 음성 전송,
  즉시 백엔드 전송, 채팅방 일정 제안 투표/확정, 오픈채팅 초대 링크 입장/나가기,
  신고, 차단, FCM 만료 토큰 정리.
- [x] Firebase 테스트 전화번호 기준 프로덕션 Firebase backend 전체 E2E 테스트:
  전화번호 인증, 프로필 설정, 아이디
  선점, 방 생성, 텍스트 전송, 음성 업로드, Deepgram transcript, 자동 음성
  전송, 첨부, 위치, 예약 전송, 번역, 초대 링크/QR, 수정, 삭제, 신고,
  차단, 방 나가기. 2026-06-18 확장 실행 통과:
  `artifacts/production-e2e-smoke-20260618150400.json`.
- [ ] 실제 기기에서 STT 지연시간, 실패 처리, 한국어 transcript 품질 검증.
- [x] Android 실기기 QA 스크립트 준비: 기기 정보, 실행 스크린샷,
  UIAutomator dump, logcat, 테스터 체크리스트를
  `artifacts/android-real-device-qa/<run-id>/` 아래에 저장.
- [x] FCM 실기기 QA 스크립트 준비: foreground, background, terminated,
  lock-screen 수신 증거를 `artifacts/fcm-real-device/<run-id>/` 아래에 저장.
- [x] 2026-06-18 에뮬레이터와 운영 `retention_probe_*` 검증으로 transcript는
  유지하면서 음성 보존기간 만료 삭제가 동작하는지 확인.
- [ ] 실제 Android 기기에서 FCM 푸시를 검증하고
  `artifacts/fcm-real-device-latest.json` 기록.
- [ ] iOS 런칭이 범위에 포함된다면 APNs 설정과 iOS 푸시 검증.
- [x] 음성 자동 전송, 음성 일정 자동 저장, 회원가입 정책 동의 변경 이후 최신 소스 기준
  Android release AAB 재빌드.
- [x] Play Console 업로드 전 패키지 식별자, Firebase 패키지 매핑, AAB 최신성/빌드
  결과 동일성, 버전 metadata, upload key 읽기 가능 여부를 확인하는 Android 릴리즈
  artifact 검증 추가.
- [x] Internal testing 업로드 준비 여부와 일반 사용자 공개 노출 준비 여부를 분리하는
  런칭 게이트 리포트 추가.
- [x] Play Console, Data Safety, 실기기 E2E, FCM 증거가 완료된 뒤 런칭
  게이트를 닫을 수 있도록 구조화된 수동 증거 파일 흐름 추가.
- [x] 수동 증거 파일을 채운 뒤 런칭 게이트를 다시 실행하기 전에 독립적으로
  검증할 수 있도록 `npm run verify:launch-evidence` 추가.
- [x] Google Play Internal testing 업로드 전 로컬 gate를 한 번에 확인할 수
  있도록 `npm run verify:preinternal` 추가.
- [x] 외부 Play Console 및 실기기 증빙 작업을 한 파일에서 이어갈 수 있도록
  `npm run prepare:launch-handoff` 추가.
- [x] 업로드 전 오래된 AAB, Play Console pack, launch gate, handoff 산출물을
  잡을 수 있도록 `npm run verify:launch-consistency` 추가.
- [x] 현재 단계, 다음 외부 증빙 작업, 남은 일반 공개 blocker를 간결하게
  보여주는 `npm run status:launch` 대시보드 추가.
- [x] 프로덕션 또는 일반 사용자 공개 직전 hard gate로
  `npm run verify:public-release` 추가.
- [x] Google Play Console 앱 listing 생성과 internal testing 업로드.
  현재 Play Console 앱은 `Verbal` / `com.voicebeta.verbal`이며, 현재
  `1 (1.0.0)` AAB가 Internal testing에 업로드됐고 tester Gmail도 추가됨.
- [ ] Internal testing 업로드 후 Google Play Pre-launch report를 검토하고
  `playConsole.preLaunchReportReviewed` 증거 기록.
- [ ] Google Play closed testing / production access 준비를 완료하거나, Play
  Console 계정이 해당 요구사항 대상이 아닌 이유를 증거로 기록.
- [ ] Play Console에서 Google Play Data Safety 작성.
- [x] 개인정보처리방침, 이용약관, 계정/데이터 삭제 정책 초안 준비.
- [x] 회원가입 시 이용약관, 개인정보 처리방침, 커뮤니티/UGC 운영정책 필수
  동의 gate를 추가하고 동의 버전을 사용자 문서에 저장.
- [x] 계정 삭제와 데이터 삭제 정책용 Firebase Hosting 정적 페이지 준비.
- [x] 정식 런칭 도메인 구매: `verbal.chat`.
- [x] 기본 Firebase Hosting 사이트 배포와 예비 계정/데이터 삭제 HTTPS URL 확인.
- [x] `verbal.chat` 권한 DNS를 Cloudflare로 이전하고 Firebase Hosting 레코드를
  유지했으며, `support@verbal.chat` -> `jangseo37@gmail.com` Cloudflare Email
  Routing을 활성화.
- [x] Play Console 제출 전 `https://verbal.chat/account/delete`와
  `https://verbal.chat/data-deletion` 접속 확인.
- [x] 패키지 식별자, 릴리즈 AAB, 공개 삭제 URL, 스토어 등록 파일, 정책 문서,
  telemetry 연결, 정책 동의, 검증 스크립트를 확인하는 자동 런칭 준비상태 검증기를
  추가하고 실행. 2026-06-19 KST 최신 실행 결과 219개 check 통과, 실패 0개.
- [x] Play Console, Data Safety, Pre-launch report, closed testing/production
  access, 실기기 E2E, FCM 증거를 JSON 직접 편집 대신 명령으로 기록하는
  launch evidence recorder 추가.
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
- [x] Firebase runtime 모드에 Analytics/Crashlytics 패키지를 연결하고 핵심
  funnel, 음성, 첨부, 신고, 내보내기, push token 이벤트 기록.
- [x] 실제 DAU, 음성 길이, STT 오류율, 재생률을 반영할 부하/비용 시뮬레이션
  모델 준비.
- [x] 로그인, STT 실패, 계정 분실, 신고 처리, 데이터 삭제용 고객지원 매크로
  준비.

## 현재 검증 명령

아래 명령은 MVP 검증 중 사용한 명령이며, 배포 대상 변경 이후 다시 실행해야
합니다.

```powershell
cd .\apps\mobile
C:\Users\jangs\develop\flutter\bin\flutter.bat analyze
C:\Users\jangs\develop\flutter\bin\flutter.bat test

cd ..\..\functions
npm run test:calendar-parser
npm run build
npm run emulators:check
npm run rules:test
npm run smoke:prod-e2e
npm run verify:preinternal
npm run verify:launch-consistency
npm run status:launch
npm run verify:public-release

cd ..
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
- [ ] 실제 기기 기준 전체 운영 E2E는 아직 남아 있음.

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
- [x] transcript 보존 상태의 음성파일 보존기간 만료 삭제 검증은 에뮬레이터와
  운영 probe에서 통과.
- [x] `verbal.chat` 계정/데이터 삭제 URL, 릴리즈 AAB, 정책 문서, 스토어 등록
  파일, telemetry, 회원가입 동의 gate를 확인하는 자동 런칭 준비상태 검증을 추가했고
  2026-06-19 KST 실행 결과 release 검증 hook 포함 0 failures로 통과.
- [x] 2026-06-19 KST Android 릴리즈 검증 통과: 패키지 식별자, Firebase 패키지
  매핑, AAB 최신성/빌드 결과 동일성, 버전 metadata, upload key fingerprint 통과.
- [x] 앱 식별자, AAB metadata, 정책 URL, 지원 연락처, 스토어 설명문,
  Data Safety 요약, 스크린샷 체크리스트/후보, 남은 수동 단계를 모으는 Play
  Console 입력 pack 생성기를 추가.
- [x] 512px 앱 아이콘, 1024x500 feature graphic, 1080x1920 phone screenshot
  5장을 생성하는 Play Store asset 생성기를 추가.
- [x] 프로덕션 E2E smoke 범위를 메시지 수정/삭제, 반응, 고정/해제, 예약
  전송, 파일 첨부, 위치, 번역, 캘린더 제안 투표/확정, 오픈채팅 초대
  입장/나가기, 신고, 차단까지 확장.
- [x] 첨부 업로드가 운영 Storage에서 거부되던 문제를 수정하고 2026-06-18
  Firebase Storage rules를 재배포. 첨부 읽기는 계속 방 멤버로 제한하고,
  업로드는 인증 사용자 본인 UID 경로만 허용.
- [x] Android 실기기 QA helper 추가:
  `scripts/run-android-real-device-qa.ps1`.
- [x] Android 실기기 precheck helper 추가:
  `scripts/run-android-real-device-precheck.ps1`.
- [x] FCM 실기기 QA helper 추가:
  `scripts/run-fcm-real-device-qa.ps1`.
- [x] Android 릴리즈 검증 helper 추가:
  `scripts/verify-android-release-artifact.ps1`.
- [x] 런칭 게이트 리포트 helper 추가:
  `functions/scripts/generate-launch-gate-report.js`.
- [x] 수동 런칭 증거 템플릿 helper 추가:
  `functions/scripts/prepare-launch-evidence-template.js`.
- [x] 수동 런칭 증거 기록 helper 추가:
  `functions/scripts/record-launch-evidence.js`.
- [x] 수동 런칭 증거 검증 helper 추가:
  `functions/scripts/verify-launch-evidence.js`.
- [x] 내부 테스트 업로드 전 릴리즈 검증 helper 추가:
  `functions/scripts/run-preinternal-release-check.js`.
- [x] 런칭 핸드오프 helper 추가:
  `functions/scripts/generate-launch-handoff.js`.
- [x] 런칭 정합성 검증 helper 추가:
  `functions/scripts/verify-launch-consistency.js`.
- [x] 런칭 상태 대시보드 helper 추가:
  `functions/scripts/generate-launch-status.js`.
- [x] 일반 공개 hard gate helper 추가:
  `functions/scripts/verify-public-release-gate.js`.
- [ ] 다음: Google Play App content와 Data Safety form 작성.
