# Closed Testing 운영 runbook

원문: `docs/CLOSED_TESTING_RUNBOOK.md`

상태 기준일: 2026-06-19

이 문서는 Verbal의 Google Play closed testing과 production access 증거 준비를
위한 runbook입니다. 앱을 게시하지 않습니다.

## Pack 생성

repo root에서 실행합니다.

```powershell
cd .\functions
npm run prepare:closed-testing-pack
```

명령은 아래 파일을 생성합니다.

- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`
- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.json`
- `artifacts/play-console/closed-testing/tester-list-template.csv`

## 사용 시점

Play Console 앱이 생성되고 AAB가 Internal testing에 업로드된 뒤 사용합니다.
Play Console에서 production access testing을 요구하면 일반 사용자 공개 전에
통제된 closed test를 운영하는 데 사용합니다.

Play Console에서 해당 계정/앱이 closed-testing production access 요구사항
대상이 아니라고 표시하면, 테스트 증거를 임의로 만들지 말고 비대상 사유를
기록합니다.

## 운영 규칙

- `npm run verify:preinternal`로 검증된 최신 AAB를 사용합니다.
- Play Console이 production access closed test를 요구하면 최소 12명의 opt-in
  tester를 추가합니다.
- 요구 대상이면 closed test를 최소 14일 연속 유지합니다.
- closed-testing gate를 완료로 기록하기 전에 피드백을 수집합니다.
- production access를 신청하기 전에 blocking issue를 triage합니다.
- 실제 증거가 생기기 전에는 launch gate를 완료로 표시하지 않습니다.

## 증거 기록

closed testing이 필요한 경우:

```powershell
npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>
```

비대상인 경우:

```powershell
npm run record:closed-testing-not-required -- --reason "<reason>"
```

그 다음 실행합니다.

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
```

Play Console, 실기기 E2E, FCM, Pre-launch report, App content/Data Safety
증거가 모두 기록되기 전까지 일반 사용자 공개 gate는 계속 red 상태여야 합니다.
