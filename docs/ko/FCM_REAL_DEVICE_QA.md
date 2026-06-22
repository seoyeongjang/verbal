# FCM 실기기 QA

원문: `docs/FCM_REAL_DEVICE_QA.md`

상태 기준일: 2026-06-19

이 문서는 FCM 런칭 게이트에 필요한 Android 실기기 증거를 정의합니다.
백엔드 smoke test는 서버 경로와 만료 token 정리를 이미 검증하지만, 실제
Android 기기에서 앱 상태별 알림 수신을 증명하지는 못합니다.

## 명령

repo root에서 실행합니다.

```powershell
.\scripts\run-fcm-real-device-qa.ps1
```

주요 옵션:

```powershell
# 통과한 실기기 실행 없이 경로와 artifact 생성을 확인합니다.
.\scripts\run-fcm-real-device-qa.ps1 -DryRun

# 특정 adb 기기를 선택합니다.
.\scripts\run-fcm-real-device-qa.ps1 -DeviceId <adb-device-id>
```

FCM QA는 휴대폰이 켜져 있고 잠금 해제된 상태에서 시작해야 합니다.
잠금화면 수신 상태는 스크립트 후반에서 별도로 테스트합니다. 시작 시점부터
Android keyguard/PIN 화면에 머물러 있으면 스크립트는
`device_unlocked_for_fcm_start: false`를 기록하고, 관찰할 수 없는 push
확인을 기다리지 않고 종료합니다.

스크립트는 아래 경로에 증거를 저장합니다.

`artifacts/fcm-real-device/<run-id>/`

최신 machine-readable 요약은 아래 파일에 저장합니다.

`artifacts/fcm-real-device-latest.json`

DryRun은 별도의 준비 점검 요약에 저장합니다.

`artifacts/fcm-real-device-dryrun-latest.json`

DryRun 결과는 런칭 증거용 최신 요약을 덮어쓰지 않습니다.

또한 스크립트는 한국어/영어 병기 `manual-checklist.md`를 생성하므로,
테스터가 이 문서를 계속 오가지 않고 네 가지 알림 상태를 바로 체크할 수 있습니다.

## 필수 상태

테스터는 아래 네 가지 상태를 모두 검증해야 합니다.

1. Foreground: Verbal이 열려 있고 화면에 보이는 상태에서 push 수신.
2. Background: Verbal이 background에 있는 상태에서 push 수신.
3. Terminated: Android force-stop이 아니라 `adb shell am kill`로 앱 process가
   종료된 상태에서 push 수신.
4. Lock screen: 휴대폰이 잠긴 상태에서 push 수신.

스크립트는 각 상태마다 screenshot, logcat, notification dump 증거를 수집하고
테스터의 pass/fail 답변을 기록합니다.

## 런칭 증거 기록

통과한 실행 뒤 아래 명령으로 기록합니다.

```powershell
cd .\functions
npm run record:fcm-real-device -- --tester "Tester name" --device "Galaxy"
```

런칭 증거 검증기는 참조된 JSON artifact가 `ok: true`이고, DryRun이 아니며,
실제 device ID가 있고, 네 가지 상태를 모두 true로 보고할 때만 FCM 증거를
인정합니다.
