# 런칭 게이트 리포트

원문: `docs/LAUNCH_GATE_REPORT.md`

상태 기준일: 2026-06-19

이 리포트는 Play Console 작업 또는 더 넓은 테스터 배포 직전에 사용합니다.
최신 자동 검증 산출물을 모아 아래 두 가지를 분리해서 판단합니다.

- Verbal이 Google Play Internal testing 업로드 준비 상태인지
- Verbal이 일반 사용자 공개 노출 준비 상태인지

## 명령

repo root에서 실행합니다.

```powershell
cd .\functions
npm run prepare:launch-evidence
npm run report:launch-gate
```

명령은 아래 파일을 생성합니다.

- `artifacts/launch-gate-<run-id>.json`
- `artifacts/launch-gate-<run-id>.md`
- `artifacts/launch-gate-latest.json`
- `artifacts/launch-gate-latest.md`

외부 Play Console 또는 실기기 증거가 있으면
`npm run record:launch-evidence -- <command>` 명령으로 기록합니다. 그 다음
`npm run verify:launch-evidence`로 검증한 뒤 리포트를 다시 실행합니다.

## 게이트 판단 기준

내부 테스트 업로드는 아래 로컬 게이트가 통과하면 진행할 수 있습니다.

- 최신 launch readiness artifact 통과
- 최신 Android release verification artifact 통과
- Play Console 입력용 copy/paste pack 존재

일반 사용자 공개 노출은 아래 외부/수동 게이트가 닫히기 전까지 차단 상태로
유지합니다.

- Google Play Console 앱 레코드 생성
- AAB Internal testing 업로드
- Google Play Pre-launch report 검토 및 blocking issue 없음 확인
- closed testing / production access 준비 증거 또는 Play Console 비대상 사유 기록
- Data Safety와 App content form 제출
- DryRun이 아닌 연결된 Android 실기기 기준 E2E 실행
- FCM foreground/background/terminated/lock-screen 수신 검증

## 메모

이 스크립트는 어떤 것도 배포하지 않습니다. 현재 증거와 남은 차단 항목만
요약합니다.
