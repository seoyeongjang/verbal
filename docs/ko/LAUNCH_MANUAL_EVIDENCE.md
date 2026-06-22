# 런칭 수동 증거

원문: `docs/LAUNCH_MANUAL_EVIDENCE.md`

상태 기준일: 2026-06-19

일부 런칭 게이트는 Google Play Console 내부 또는 실제 Android 기기에서
진행되므로 로컬 코드만으로 증명할 수 없습니다. 수동 증거 파일은 해당
완료 내역을 구조화해서 기록하기 위한 파일입니다.

## 템플릿 생성

repo root에서 실행합니다.

```powershell
cd .\functions
npm run prepare:launch-evidence
```

명령은 아래 파일을 생성합니다.

- `artifacts/launch-manual-evidence.template.json`

Android release 검증 artifact가 있으면 템플릿은 Internal testing 업로드
증거에 필요한 현재 `versionCode`, `aabSha256`, release name을 자동으로
채웁니다. 그래도 모든 `done` 필드는 `false`로 유지됩니다. 실제 외부
증거가 생긴 뒤에만 `done` 값을 변경합니다.

필요하면 아래 파일로 복사합니다.

- `artifacts/launch-manual-evidence.json`

그 다음 실제 증거가 있는 필드만 수정합니다.

## 명령으로 증거 기록

JSON을 직접 편집하기보다 recorder를 사용하는 것을 권장합니다.

```powershell
cd .\functions
npm run record:launch-evidence -- init
npm run record:launch-evidence -- status
```

`status`는 남아 있는 증거 gate와 각 Play Console 또는 실기기 작업이
실제로 완료된 뒤 실행할 정확한 기록 명령을 출력합니다. 아직 끝나지 않은
작업을 완료로 표시하면 안 되며, 완료된 외부 증거만 기록합니다.

외부 단계가 실제로 끝난 뒤 해당 명령만 실행합니다.

```powershell
npm run record:launch-evidence -- play-app-created --created-at now --console-url https://play.google.com/console/...
npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group "owner@example.com"
npm run record:app-content-submitted
npm run record:prelaunch-reviewed -- --report-url https://play.google.com/console/...
npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14
npm run record:closed-testing-not-required -- --reason "Organization account does not require production access closed test"
npm run record:real-device-e2e -- --tester "Tester name" --device-model "Galaxy"
npm run record:fcm-real-device -- --tester "Tester name" --device "Galaxy"
```

단축 recorder는 내부적으로 엄격한 `record:launch-evidence`를 호출하고,
launch gate/status/next-step/handoff artifact를 다시 생성합니다. 참조한
실기기 또는 FCM artifact 파일이 없거나 DryRun/실패 상태라면 증거 기록을
거부합니다. App content 증거는 최신 App content answer pack이 Data
Safety 빠른 답변, 상세 Play Console 입력 matrix, 한국어 콘솔 라벨, UGC
제어 항목을 포함하고, 최신 hosted policy URL 검증이 통과해야 기록됩니다.

## 증거 규칙

- `playConsole.appCreated.done`은 Play Console 앱 레코드가 실제로 생성된
  뒤에만 true로 바꿉니다.
- `playConsole.internalTestingUpload.done`은 `dist/android/app-release.aab`가
  Internal testing 트랙에 업로드된 뒤에만 true로 바꿉니다.
- `playConsole.preLaunchReportReviewed.done`은 Google Play Pre-launch
  report가 생성되고 stability, performance, accessibility, screenshot,
  blocking issue 결과를 검토한 뒤에만 true로 바꿉니다.
- `playConsole.closedTestingCompleted.done`은 필요한 closed test가 완료됐거나
  Play Console에서 해당 계정/앱이 closed-test production access requirement
  대상이 아님을 확인한 뒤에만 true로 바꿉니다. 신규 개인 개발자 계정 기준
  Google의 현재 요구사항은 production access 신청 전 최소 12명의 opt-in
  tester가 14일 연속 테스트하는 것입니다:
  `https://support.google.com/googleplay/android-developer/answer/14151465`.
- `playConsole.appContentSubmitted.done`은 Privacy Policy, App access, Ads,
  Data Safety, 계정 삭제, 데이터 삭제, Content rating, Target audience,
  Sensitive permissions, UGC, 정부 앱, 금융 기능, 건강, 앱 카테고리/연락처,
  스토어 등록정보 섹션이 Play Console에 저장된 뒤에만 true로 바꿉니다.
- `realDevice.e2e.done`은 DryRun이 아닌 연결된 Android 실기기로 QA를 실행한
  뒤에만 true로 바꿉니다.
- `realDevice.fcm.done`은 foreground, background, terminated, lock-screen
  푸시 수신을 모두 검증한 뒤에만 true로 바꿉니다.

증거 파일을 갱신한 뒤 실행합니다.

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
```

증거 검증기는 부족한 필드를 구체적으로 보고합니다. 런칭 게이트 리포트는
`artifacts/launch-manual-evidence.json`을 읽고, 필요한 증거 필드가 모두
채워진 경우에만 해당 게이트를 닫습니다.
