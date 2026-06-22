# 일반 공개 릴리즈 게이트

원문: `docs/PUBLIC_RELEASE_GATE.md`

상태 기준일: 2026-06-19

이 문서는 Verbal을 Play Store 프로덕션 배포로 일반 사용자에게 노출하기 전에
반드시 통과해야 하는 hard gate를 설명합니다.

## 명령

저장소 루트에서 실행합니다.

```powershell
cd .\functions
npm run verify:public-release
```

동일한 hard gate를 실행하는 별칭도 등록되어 있으므로 아래 명령도 사용할 수 있습니다.

```powershell
npm run verify:public-release-gate
```

## 기대 동작

Play Console과 실기기 증빙이 기록되기 전에는 이 명령이 실패해야 합니다.
이 실패는 의도된 동작이며, 런칭 blocker가 남아 있을 때 실수로 프로덕션
공개를 진행하지 못하게 막기 위한 안전장치입니다.

명령은 아래를 실행합니다.

1. `npm run verify:launch-evidence`
2. `npm run report:launch-gate`

그 다음 `readyForPublicUserExposure`가 true인지, 최신 launch gate에 blocker가
없는지 확인합니다.

## 산출물

명령 실행 후 아래 파일이 생성됩니다.

- `artifacts/public-release-gate-<run-id>.json`
- `artifacts/public-release-gate-latest.json`

## 통과 기준

아래 조건이 모두 true일 때만 통과합니다.

- 엄격한 launch evidence 검증이 통과합니다.
- `artifacts/launch-gate-latest.json`이 존재합니다.
- `readyForPublicUserExposure`가 true입니다.
- Launch gate blocker 목록이 비어 있습니다.

## 사용 시점

이 명령은 프로덕션 또는 일반 사용자 공개 단계 직전에만 사용합니다. Google
Play Internal testing 업로드에는 `npm run verify:preinternal`이 올바른
gate입니다.

이 명령이 실패하면 프로덕션 공개를 진행하지 않습니다.
