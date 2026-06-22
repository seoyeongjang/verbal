# 런칭 핸드오프

원문: `docs/LAUNCH_HANDOFF.md`

상태 기준일: 2026-06-19

이 문서는 로컬 preinternal 검증이 통과된 뒤, Verbal을 일반 사용자에게
노출하기 전까지 사용하는 핸드오프 산출물을 설명합니다.

## 목적

런칭 핸드오프는 현재 릴리즈 산출물, readiness 산출물, Play Console 입력
팩, closed testing 팩, 수동 증빙 상태, 외부 증빙 기록 명령을 한 파일로
정리합니다.

이 파일 자체가 Play Console, 실기기, FCM 작업 완료를 증명하지는 않습니다.
다음 작업자가 모든 런칭 문서를 다시 열지 않고 남은 외부 순서를 그대로
이어갈 수 있게 만드는 운영용 안내 파일입니다.

더 짧은 현재 상태 요약은 `artifacts/launch-status-latest.md`를 사용합니다.

## 명령

저장소 루트에서 실행합니다.

```powershell
cd .\functions
npm run prepare:launch-handoff
```

preinternal 릴리즈 체크도 이 명령을 자동으로 실행합니다.

```powershell
cd .\functions
npm run verify:preinternal
```

## 출력

명령 실행 후 아래 파일이 생성됩니다.

- `artifacts/launch-handoff-<run-id>.json`
- `artifacts/launch-handoff-<run-id>.md`
- `artifacts/launch-handoff-latest.json`
- `artifacts/launch-handoff-latest.md`

내부 테스트 업로드 전 릴리즈 검증은 handoff와 consistency 검증 후
`artifacts/launch-status-latest.md`도 생성합니다.

## 포함 내용

- 내부 테스트 업로드 가능 여부.
- 일반 사용자 공개 가능 여부.
- 현재 일반 공개 blocker.
- 릴리즈 AAB 경로.
- Android 릴리즈 검증 경로.
- Launch readiness 리포트 경로.
- Launch gate 리포트 경로.
- Play Console 제출 팩 경로.
- Closed testing 팩 경로.
- 수동 런칭 증빙 경로.
- 스토어 에셋 경로.
- 개인정보 처리방침, 계정 삭제, 데이터 삭제 공개 URL.
- 단계별 외부 증빙 순서:
  - `play-app-created`
  - `internal-testing-upload`
  - `app-content-submitted`
  - `prelaunch-reviewed`
  - `closed-testing-completed`
  - `real-device-e2e`
  - `fcm`

## 사용 방법

1. `artifacts/launch-handoff-latest.md`를 엽니다.
2. 외부 작업 순서를 위에서 아래로 진행합니다.
3. 각 외부 작업을 마칠 때마다 대응되는
   `npm run record:launch-evidence -- ...` 명령을 실행합니다.
4. 다음 명령을 실행합니다.

```powershell
npm run verify:launch-evidence
npm run report:launch-gate
npm run prepare:launch-handoff
```

5. Launch gate가 다음 노출 단계를 허용할 때만 다음 단계로 이동합니다.

`artifacts/launch-gate-latest.json`의 `readyForPublicUserExposure`가 true가
되기 전에는 Verbal을 일반 사용자에게 공개하지 않습니다.
