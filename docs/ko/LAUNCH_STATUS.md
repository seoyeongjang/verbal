# 런칭 상태 대시보드

원문: `docs/LAUNCH_STATUS.md`

상태 기준일: 2026-06-19

이 문서는 로컬 내부 테스트 업로드 준비와 남은 외부 Play Console / 실기기
작업 사이에서 사용하는 간결한 상태 대시보드를 설명합니다.

## 목적

런칭 상태 대시보드는 아래 질문에 대한 현재 답을 하나로 보여줍니다.

- Verbal을 Google Play Internal testing에 업로드할 수 있는지.
- Verbal이 아직 일반 사용자 공개에서 차단되어 있는지.
- 다음에 완료해야 할 외부 증거 단계가 무엇인지.
- Play Console 입력에 사용할 artifact가 무엇인지.

`artifacts/launch-handoff-latest.md`보다 짧게 설계했습니다. 현재 상태를
빠르게 확인할 때는 status 파일을 사용하고, 전체 외부 순서를 볼 때는
handoff 파일을 사용합니다.

## 명령

repo root에서 실행합니다.

```powershell
cd .\functions
npm run status:launch
```

내부 테스트 업로드 전 릴리즈 검증도 이 명령을 자동으로 실행합니다.

```powershell
cd .\functions
npm run verify:preinternal
```

## 산출물

명령은 아래 파일을 생성합니다.

- `artifacts/launch-status-<run-id>.json`
- `artifacts/launch-status-<run-id>.md`
- `artifacts/launch-status-latest.json`
- `artifacts/launch-status-latest.md`

## 사용 방법

1. `artifacts/launch-status-latest.md`를 엽니다.
2. `Current Stage`를 확인합니다.
3. `Next External Step`을 수행합니다.
4. 외부 단계를 완료한 뒤 표시된
   `npm run record:launch-evidence -- ...` 명령을 실행합니다.
5. 아래 명령을 실행합니다.

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
npm run status:launch
```

`artifacts/launch-gate-latest.json`의 `readyForPublicUserExposure`가 true가
되기 전까지 Verbal을 일반 사용자에게 공개하지 않습니다.
