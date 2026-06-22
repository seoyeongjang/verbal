# Play Console 수동 체크리스트

원문: `docs/PLAY_CONSOLE_MANUAL_CHECKLIST.md`

상태 기준일: 2026-06-19

이 체크리스트는 자동 준비상태 검증이 통과한 뒤에도 Google Play Console에서
사람이 직접 입력해야 하는 항목을 정리합니다.

이 체크리스트를 사용하기 전에 아래 명령을 실행합니다.

```powershell
cd .\functions
npm run verify:preinternal
```

`artifacts/play-console/verbal-play-console-pack-*.md`의 최신 파일을
복사/붙여넣기 기준 자료로 사용합니다.
App content와 Data Safety 항목을 입력할 때는 복사 버튼이 있는
`artifacts/play-console/verbal-app-content-copy-sheet-latest.html`을 사용합니다.
`artifacts/launch-gate-latest.md`는 현재 릴리즈 게이트 요약으로 사용합니다.
각 증거 업데이트 후 `artifacts/next-external-step-latest.md`를 현재 단일
다음 단계 가이드로 사용합니다.
완료된 Play Console/실기기 증거 기록에는
`artifacts/launch-manual-evidence.template.json`을 템플릿으로 사용합니다.

현재 next-step guide, copy sheet, launch status, Play Console 앱 URL을 함께
열려면 아래 명령을 실행합니다.

```powershell
cd .\functions
npm run open:next-launch-step
```

## 현재 상태

- Google Play 앱 레코드: 완료.
- 패키지명: `com.voicebeta.verbal`.
- 내부 테스트 AAB 업로드: 완료.
- 내부 테스터: Play Console에 추가 완료.
- 현재 단계: `google_play_internal_testing_uploaded`.
- 현재 다음 단계: Google Play App content와 Data Safety form 작성.
- 현재 단일 단계 가이드: `artifacts/next-external-step-latest.md`.
- 복사/붙여넣기 HTML 시트:
  `artifacts/play-console/verbal-app-content-copy-sheet-latest.html`.
- 복사/붙여넣기 답변:
  `artifacts/play-console/verbal-app-content-answers-latest.md`.

## 1. 앱 생성 - 완료

- 앱 이름: `Verbal`
- 기본 언어: 한국어 / `ko-KR`
- 앱 또는 게임: 앱
- 무료 또는 유료: 무료
- AAB 업로드 후 패키지명: `com.voicebeta.verbal`

Play Console에서 앱을 생성해도 곧바로 일반 사용자에게 공개되지 않습니다.
사용자는 릴리즈 트랙을 만들고, 필요한 심사를 통과하고, 내부 테스트 또는
production으로 rollout한 뒤에만 다운로드할 수 있습니다.

앱 생성 또는 첫 릴리즈 업로드 전에 변경이 어려운 항목만 먼저 확정합니다.

| 항목 | 앱 생성 후 변경 | 런칭 기준 |
|---|---|---|
| 패키지명 / `applicationId` | 사실상 불가. 다른 패키지는 다른 앱으로 취급됩니다. | `com.voicebeta.verbal`을 유지합니다. |
| 앱 서명 / upload key | 키 재설정/복구 절차는 가능하지만 운영 부담이 큽니다. | 검증된 release keystore를 사용하고 백업은 비공개로 보관합니다. |
| Firebase Android 앱 매핑 | 가능하지만 새 Firebase Android 앱 설정과 빌드 검증이 필요합니다. | 현재 `google-services.json` 매핑을 유지합니다. |
| 앱 이름, 설명, 스크린샷, 카테고리 | 가능. 스토어 등록정보를 수정하고 필요 시 심사를 받습니다. | 내부 테스트 단계에서는 충분히 좋은 수준이면 됩니다. |
| 앱 기능과 UI | 가능. `versionCode`를 올린 새 AAB를 업로드합니다. | Internal testing과 Closed testing에서 계속 개선합니다. |
| Data Safety와 정책 답변 | 가능하지만 제출 빌드와 일치해야 합니다. | 데이터 수집, 권한, 광고, UGC 동작이 바뀔 때마다 갱신합니다. |

## 2. 스토어 등록정보

- 짧은 설명: 생성된 pack 사용.
- 전체 설명: 생성된 pack 사용.
- 앱 아이콘: `artifacts/store/google-play/assets/app-icon-512.png`
- Feature graphic:
  `artifacts/store/google-play/assets/feature-graphic-1024x500.png`
- Phone screenshots:
  `artifacts/store/google-play/assets/phone-screenshots/*.png`
- 카테고리: Communication
- 연락 이메일: `support@verbal.chat`
- 웹사이트: `https://verbal.chat`
- 개인정보 처리방침: `https://verbal.chat/privacy`

## 3. 정책 URL

- 이용약관: `https://verbal.chat/terms`
- 커뮤니티 가이드라인 / UGC 정책:
  `https://verbal.chat/community-guidelines`
- 계정 삭제 URL: `https://verbal.chat/account/delete`
- 데이터 삭제 정책: `https://verbal.chat/data-deletion`

## 4. App content 선언

- Data Safety: `docs/GOOGLE_PLAY_DATA_SAFETY.md` 기준으로 작성.
- 광고: 제출 빌드에 실제 광고 SDK 또는 운영 광고 지면이 활성화되어 있지
  않다면 No 선택.
- App access / sign-in details:
  `docs/ko/PLAY_REVIEWER_ACCESS.md` 기준으로 작성하고 Firebase 테스트
  전화번호 `+16505550101` / `123456`을 제공합니다.
- 대상 연령: 정책 검토 후 선택. 청소년을 포함할 경우 별도의 청소년/콘텐츠
  정책 검토가 필요합니다.
- 콘텐츠 등급: 메시징/UGC, 사용자 상호작용, 위치 공유, 신고/차단 안전
  기능 기준으로 답변합니다.
- 뉴스 앱/정부 앱: 제품 범위가 바뀌지 않는 한 No 선택.
- App content 워크시트:
  `docs/ko/PLAY_APP_CONTENT_WORKSHEET.md`를 기준으로 광고, 앱 접근,
  Data Safety, 계정 삭제, 대상 연령, 콘텐츠 등급, 민감 권한, UGC, 특수
  카테고리 선언, 정부 앱, 금융 기능, 건강, 앱 카테고리/연락처, 스토어
  등록정보를 입력합니다.
- App content 저장 후 증거는
  `npm run record:app-content-submitted`
  명령으로 기록합니다.

## 5. 내부 테스트 릴리즈 - 업로드 완료

- 업로드 AAB: `dist/android/app-release.aab`
- 패키지명 확인: `com.voicebeta.verbal`
- 릴리즈 노트: 생성된 pack 사용.
- 내부 테스터를 이메일 또는 Google Group으로 추가.
- 현재 상태: AAB 업로드와 tester Gmail 추가 완료.
- 업로드 후 signing, permissions, SDK version, privacy, policy 경고를
  확인합니다.
- Pre-launch report가 생성되면 더 넓은 테스트 전에 Stability, Performance,
  Accessibility, Screenshots, blocking issue를 검토합니다.
- Pre-launch report 검토 증거는
  `npm run record:prelaunch-reviewed -- --report-url "https://play.google.com/console/..."`
  명령으로 기록합니다.
- Play Console에서 production access testing을 요구하면 production access 신청 전
  최소 12명의 opt-in tester가 최소 14일 연속 유지되는 closed testing을
  진행합니다. 공식 참고:
  `https://support.google.com/googleplay/android-developer/answer/14151465`.
- Closed testing 완료 증거는
  `npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14`
  명령으로 기록합니다.
- Play Console에서 해당 계정/앱이 이 요구사항 대상이 아니라고 확인되면
  `npm run record:closed-testing-not-required -- --reason "..."`
  명령으로 예외 증거를 기록합니다.
- `artifacts/launch-gate-latest.md`에서 Internal testing 업로드가 허용
  상태인지 확인합니다.
- 업로드 증거는
  `npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group "..."`
  명령으로 기록합니다. Recorder는 최신 릴리즈 검증의 AAB SHA-256과
  version code를 자동으로 채우므로, 증거 기록 전에 업로드한 AAB와 값이
  일치하는지 확인합니다.
- 증거를 기록한 뒤 `npm run verify:launch-evidence`를 실행해 필수 필드가
  모두 채워졌는지 확인하고, 그 다음 런칭 게이트 리포트를 다시 실행합니다.

## 6. 더 넓은 테스트 전 필수 검증

- 실제 Android 기기에서 테스트 번호가 아닌 번호로 SMS 로그인.
- 마이크 권한 및 음성 녹음.
- 음성 STT transcript 품질과 지연시간.
- Firebase Storage에서 음성 재생.
- FCM push foreground, background, terminated, lock-screen 상태.
- 계정 삭제 진입 경로.
- 신고/차단 흐름.
- 음성 보존기간 만료 후 transcript 유지와 audio 삭제.

## 7. 수동으로만 가능한 항목

- Play Console 앱 레코드 생성. `Verbal` 기준 완료.
- Data Safety form 제출.
- 내부 테스트 업로드 및 테스터 rollout. 현재 `1 (1.0.0)` AAB 기준 완료.
- Play Console Pre-launch report 검토.
- Closed testing / production access 준비.
- 실기기 E2E 검증.
- iOS 출시 범위가 있다면 APNs/TestFlight 설정.
