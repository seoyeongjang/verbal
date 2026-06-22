# Google Play 제출 패키지

원문: `docs/GOOGLE_PLAY_SUBMISSION.md`

상태 기준일: 2026-06-19

이 문서는 실제 Android 기기 없이 미리 준비할 수 있는 Google Play Console
입력값을 정리합니다. 최종 업로드와 심사 제출에는 Play Console 앱 레코드가
필요합니다.

수동 콘솔 입력 체크리스트: `docs/ko/PLAY_CONSOLE_MANUAL_CHECKLIST.md`
심사자 앱 접근 안내: `docs/ko/PLAY_REVIEWER_ACCESS.md`
App content 입력 워크시트: `docs/ko/PLAY_APP_CONTENT_WORKSHEET.md`
Android 릴리즈 검증 가이드: `docs/ko/ANDROID_RELEASE_VERIFICATION.md`
Android 실기기 QA 가이드: `docs/ko/ANDROID_REAL_DEVICE_QA.md`
FCM 실기기 QA 가이드: `docs/ko/FCM_REAL_DEVICE_QA.md`
일반 공개 릴리즈 게이트 가이드: `docs/ko/PUBLIC_RELEASE_GATE.md`
런칭 정합성 검증 가이드: `docs/ko/LAUNCH_CONSISTENCY.md`

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

## 개인정보 및 정책 URL

Play Console에는 로컬 파일이 아니라 공개 HTTPS URL을 입력해야 합니다.

- 개인정보 처리방침: `https://verbal.chat/privacy`
- 이용약관: `https://verbal.chat/terms`
- 커뮤니티/UGC 정책: `https://verbal.chat/community-guidelines`
- 계정 삭제 URL: `https://verbal.chat/account/delete`
- 데이터 삭제 안내: `https://verbal.chat/data-deletion`

기본 Firebase Hosting URL은 fallback으로 유지합니다:
`https://voice-messenger-jangs-260522.web.app/account/delete`

수동 계정 삭제 요청 지원 이메일:
`support@verbal.chat`은 Cloudflare Email Routing을 통해
`jangseo37@gmail.com`으로 전달됩니다.

## 내부 테스트 메모

에뮬레이터 또는 내부 smoke test에는 아래 Firebase Auth 테스트 계정을
사용합니다.

- 전화번호: `+16505550101`
- SMS 코드: `123456`

이 번호는 실제 SMS를 보내지 않는 Firebase Auth 테스트 번호입니다. 공개
고객지원 계정으로 사용하면 안 됩니다.

## 릴리즈 산출물

- 최신 Android App Bundle:
  `dist/android/app-release.aab`

## 자동 준비상태 검증

Play Console 내부 테스트 릴리즈를 생성하거나 갱신하기 전에 아래 명령을
실행합니다.

```powershell
cd .\functions
npm run verify:hosted-policy-urls
npm run verify:preinternal
```

Android 릴리즈 검증기는 AAB를 업로드하기 전에 패키지 식별자, Firebase
패키지 매핑, release AAB 최신성, Gradle build output과의 동일성, 버전
metadata, upload key 읽기 가능 여부를 확인합니다. 결과는
`artifacts/android-release-verification-*.json`와
`artifacts/android-release-verification-latest.json`에 저장됩니다.

런칭 준비상태 검증기는 Android 패키지/Firebase 식별자, 릴리즈 AAB, 공개
Hosting 페이지, 계정/데이터 삭제 URL, 스토어 등록 파일, 정책 문서,
telemetry 연결, 회원가입 정책 동의 gate, 공개 정책 URL 검증, 검증 스크립트
등록 여부를 확인합니다. 2026-06-19 KST 최신 실행 결과 219개 check 통과,
실패 0개입니다. 결과 JSON은 `artifacts/launch-readiness-*.json`에 저장됩니다.

공개 정책 URL 검증기는 Play Console에 입력할 공개 URL을 확인하고
`artifacts/hosted-policy-url-verification-latest.md`를 생성합니다.

Play Console pack 생성기는 콘솔 입력용 JSON과 Markdown을
`artifacts/play-console/verbal-play-console-pack-*.json`,
`artifacts/play-console/verbal-play-console-pack-*.md`에 저장합니다. pack에는
앱 식별자, AAB 크기와 SHA-256, 정책 URL, 지원 연락처, 스토어 설명문,
Data Safety 요약, 심사용 테스트 계정 접근 정보, App content 입력 요약,
스크린샷 체크리스트/후보, 검증 artifact 경로, Android 릴리즈 검증 참조,
실기기 QA 스크립트 참조, 남은 수동 단계가 포함됩니다.
App content answers 파일에는 Play Console의 한국어/영어 섹션명, 입력값/출처,
섹션 저장 후 기록해야 하는 evidence flag가 섹션별 표로 포함됩니다.
Closed testing pack 생성기는 테스터 초대 문구, tester-list CSV 템플릿,
일일 QA task, 피드백 질문, issue template, production access 증거 기록 명령을
`artifacts/play-console/closed-testing` 아래에 저장합니다.
Windows PowerShell에서 한국어가 깨져 보이면 `Get-Content -Encoding UTF8 ...`
로 다시 확인하거나 VS Code에서 생성된 Markdown을 열어 확인합니다.
런칭 준비 검증은 한국어 스토어 문구에 읽을 수 있는 한글이 포함되어 있고
일반적인 mojibake 패턴이 없는지도 함께 확인합니다.

런칭 게이트 리포트는 `artifacts/launch-gate-latest.md`를 생성하고,
Internal testing 업로드 판단과 일반 사용자 공개 노출 판단을 분리합니다.
수동 증거 템플릿은 `artifacts/launch-manual-evidence.template.json`을
생성합니다. 실제 Play Console 또는 실기기 증거가 있을 때만
`artifacts/launch-manual-evidence.json`으로 복사해 기록합니다.

스토어 asset 생성기는 `artifacts/store/google-play/assets` 아래에 업로드용
`app-icon-512.png`, `feature-graphic-1024x500.png`, 1080x1920 phone screenshot
5개를 생성합니다.
내부 테스트 업로드 전 릴리즈 검증 명령은 모든 로컬 업로드 gate를 순서대로
실행하고 `artifacts/preinternal-release-check-latest.json`을 생성합니다.
또한 `artifacts/launch-handoff-latest.md`와
`artifacts/launch-handoff-latest.json`을 생성해 남은 Play Console 및
실기기 증빙 명령을 순서대로 정리합니다.
또한 `artifacts/launch-consistency-latest.json`을 검증해 릴리즈 AAB,
Play Console pack, launch gate, handoff가 같은 릴리즈 후보를 설명하는지
확인합니다.
또한 현재 단계, 다음 외부 증빙 작업, 남은 일반 공개 blocker를 간결하게
보여주는 `artifacts/launch-status-latest.md`를 생성합니다.

일반 공개 릴리즈 게이트는 더 엄격하며, Play Console과 실기기 증빙이 모두
기록되기 전까지 실패해야 합니다.

```powershell
cd .\functions
npm run verify:public-release
```

이 명령은 Internal testing 업로드 전이 아니라 프로덕션/일반 공개 직전에만
실행합니다.

## 내부 테스트 업로드 전

- Google Play Console에서 앱을 생성합니다.
  이 단계는 콘솔 레코드만 만드는 것이며 앱이 바로 다운로드 가능해지지는
  않습니다. 첫 릴리즈를 업로드하기 전에 패키지명, 앱 서명키, Firebase
  Android 앱 매핑은 고정합니다. 스토어 문구, 스크린샷, 정책 답변, 앱
  기능은 이후 스토어 수정 또는 더 높은 `versionCode`의 새 AAB 업로드로
  계속 변경할 수 있습니다.
- `npm run verify:preinternal`을 실행해 Internal testing 업로드는 가능한지,
  Play Console과 실기기 증거 전 일반 사용자 공개 노출은 계속 차단되는지
  확인합니다.
- 생성된 Play Console Markdown pack을 입력 워크시트로 사용합니다.
- Play Console에서 closed testing / production access 증거를 요구하면
  `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`를
  사용합니다.
- `artifacts/launch-handoff-latest.md`를 열어 Play Console, closed testing,
  실기기 E2E, FCM 증빙 작업의 단계별 핸드오프로 사용합니다.
- 현재 다음 외부 작업만 빠르게 확인할 때는
  `artifacts/launch-status-latest.md`를 엽니다.
- 생성된 Play Console pack을 사용하기 전
  `artifacts/launch-consistency-latest.json`이 통과했는지 확인합니다.
- Play Console 또는 실기기 작업이 끝나면
  `npm run record:launch-evidence -- ...` 명령으로
  `artifacts/launch-manual-evidence.json`을 업데이트하고
  `npm run verify:launch-evidence`와 `npm run report:launch-gate`를 다시
  실행합니다.
- App access는 `docs/ko/PLAY_REVIEWER_ACCESS.md` 기준으로 입력합니다.
- 광고, 콘텐츠 등급, 대상 연령, 뉴스, COVID-19, 민감 권한, 계정 삭제,
  UGC 선언은 `docs/ko/PLAY_APP_CONTENT_WORKSHEET.md` 기준으로 입력합니다.
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` 기준으로 Data Safety를 작성합니다.
- 배포된 계정 삭제 URL이 HTTPS로 열리는지 확인합니다.
- `dist/android/app-release.aab`를 내부 테스트 트랙에 업로드합니다.
- 내부 테스트 이메일 또는 Google Group을 최소 1개 추가합니다.
- Pre-launch report가 생성되면 stability, performance, accessibility,
  screenshots, blocking issue를 검토하고
  `npm run record:prelaunch-reviewed -- --report-url "https://play.google.com/console/..."`
  명령으로 증거를 기록합니다.
- Play Console에서 production access testing을 요구하면 최소 12명의 opt-in
  tester가 최소 14일 연속 유지되는 closed testing을 완료하거나, 요구사항
  비대상 사유를 기록합니다:
  `npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14`.

## 운영 심사 전

- Android 실기기 E2E 테스트를 수행합니다.
- 실기기 증거는 다음 명령으로 수집합니다:
  `.\scripts\run-android-real-device-qa.ps1 -Interactive`
- 테스트 번호가 아닌 실제 번호로 SMS 로그인을 검증합니다.
- 마이크 녹음과 Deepgram transcript 품질을 검증합니다.
- foreground, background, terminated 상태의 푸시 알림을 검증합니다.
- 상태별 FCM 증거는 다음 명령으로 수집합니다:
  `.\scripts\run-fcm-real-device-qa.ps1`
- 음성 보존기간 만료 후 transcript는 유지되고 audio만 삭제되는지 검증합니다.
- 공개 정책 URL이 정상적으로 열리고 제출 빌드와 일치하는지 확인합니다.
- `npm run verify:public-release`를 실행하고 통과할 때만 일반 공개로
  진행합니다.
