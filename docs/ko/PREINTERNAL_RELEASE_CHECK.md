# 내부 테스트 업로드 전 릴리즈 검증

원문: `docs/PREINTERNAL_RELEASE_CHECK.md`

상태 기준일: 2026-06-19

이 명령은 Google Play Internal testing 릴리즈를 만들거나 갱신하기 직전에
사용합니다. Play Console에 업로드하거나 게시하지 않습니다. 로컬 검증만
실행하고 증거 artifact를 남깁니다.

## 명령

repo root에서 실행합니다.

```powershell
cd .\functions
npm run verify:preinternal
```

명령은 아래 단계를 순서대로 실행합니다.

1. `npm run build`
2. `npm run prepare:play-store-assets`
3. `npm run verify:android-release`
4. `npm run verify:launch-readiness`
5. `npm run prepare:play-console-pack`
6. `npm run prepare:closed-testing-pack`
7. `npm run prepare:launch-evidence`
8. `npm run verify:launch-evidence -- --allow-missing`
9. `npm run report:launch-gate`
10. `npm run prepare:launch-handoff`
11. `npm run verify:launch-consistency`
12. `npm run status:launch`

여기서는 Internal testing 업로드 전 Play Console과 실기기 증거가 없거나
미완료인 것이 정상이므로 `--allow-missing` 모드를 의도적으로 사용합니다.
엄격한 명령인 `npm run verify:launch-evidence`는 외부 단계가 기록되기 전까지
계속 실패해야 정상입니다.

## 산출물

명령은 아래 파일을 생성합니다.

- `artifacts/preinternal-release-check-<run-id>.json`
- `artifacts/preinternal-release-check-latest.json`
- `artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md`
- `artifacts/play-console/closed-testing/tester-list-template.csv`
- `artifacts/launch-handoff-latest.md`
- `artifacts/launch-handoff-latest.json`
- `artifacts/launch-consistency-latest.json`
- `artifacts/launch-status-latest.md`
- `artifacts/launch-status-latest.json`

Google Play Internal testing 업로드에 필요한 로컬 gate가 모두 통과하고
런칭 게이트가 `readyForInternalTestingUpload: true`이면 통과합니다.

Play Console 증거, Pre-launch report 검토, closed testing / production
access 준비, 실기기 E2E, FCM 증거가 없기 전에는
`readyForPublicUserExposure`가 false로 남는 것이 정상입니다.

## 통과 후 다음 단계

이 명령이 통과하면 다음 순서로 진행합니다.

1. Play Console 앱 레코드를 생성합니다.
2. `dist/android/app-release.aab`를 Internal testing에 업로드합니다.
3. App content와 Data Safety form을 완료합니다.
4. 생성된 Google Play Pre-launch report를 검토합니다.
5. Play Console에서 요구하면 closed testing을 완료하고, 요구하지 않으면
   비대상 사유를 기록합니다.
6. `artifacts/launch-consistency-latest.json`이 통과했는지 확인합니다.
7. `artifacts/launch-handoff-latest.md`를 열고 그 안의 외부 증빙 명령을
   순서대로 따릅니다.
8. `artifacts/launch-status-latest.md`에서 간결한 다음 작업을 확인합니다.
9. 완료된 증거를 `npm run record:launch-evidence -- <command>` 명령으로 기록합니다.
10. `npm run verify:launch-evidence`를 실행합니다.
11. `npm run report:launch-gate`를 실행합니다.
