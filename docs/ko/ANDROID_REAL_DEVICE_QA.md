# Android 실기기 QA

원문: `docs/ANDROID_REAL_DEVICE_QA.md`

상태 기준일: 2026-06-19

이 문서는 Verbal을 일반 사용자에게 노출하기 전 필요한 Android 실기기 QA
gate를 정의합니다. 에뮬레이터와 백엔드 smoke test는 유용하지만 실제 SMS,
마이크 입력, Android 알림 동작, 네이티브 권한 팝업, 기기별 화면 깨짐까지
증명하지는 못합니다.

## 증거 수집 스크립트

수동 E2E를 시작하기 전에 가벼운 precheck로 PC가 휴대폰을 인식하는지,
Verbal이 설치되어 있는지, 버전이 현재 릴리즈와 맞는지, 권한 상태가 어떤지 먼저
확인합니다.

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run verify:android-device-precheck
```

precheck는 `artifacts/android-real-device-precheck-latest.json`을 생성합니다.
이 파일은 준비 상태 확인용 증거이지만, 실제 사용자 workflow를 검증하지 않으므로
실기기 E2E 런칭 gate를 통과시키지는 않습니다.
휴대폰이 잠금, 화면 꺼짐, dozing 상태이면 기기/패키지 정보는 수집하지만
스크린샷과 권한 팝업이 보이지 않을 수 있다는 경고를 남깁니다.

대화형 QA 스크립트를 실행하기 전에는 휴대폰을 깨우고 잠금을 해제해
런처와 Verbal UI가 보이는 상태로 두어야 합니다. Android keyguard/PIN이
활성 상태이면 QA 스크립트는 `device_unlocked_for_qa: false`를 기록하고,
Verbal UI 캡처를 건너뛰며, 검정 화면을 정상 증빙처럼 저장하지 않고 E2E
gate를 계속 열어 둡니다.

repo root에서 아래 스크립트를 실행합니다.

```powershell
.\scripts\run-android-real-device-qa.ps1
```

자주 쓰는 옵션:

```powershell
# 휴대폰 없이 경로와 연결 상태만 확인합니다.
.\scripts\run-android-real-device-qa.ps1 -DryRun

# 특정 adb 기기를 선택합니다.
.\scripts\run-android-real-device-qa.ps1 -DeviceId <adb-device-id>

# 실행 전 debug APK를 빌드하고 설치합니다.
.\scripts\run-android-real-device-qa.ps1 -InstallDebug

# 테스터가 수동 QA를 끝낼 때까지 기다렸다가 최종 증거를 수집합니다.
.\scripts\run-android-real-device-qa.ps1 -Interactive
```

FCM push 수신은 상태별 전용 증거 스크립트로 수집합니다.

```powershell
.\scripts\run-fcm-real-device-qa.ps1
```

스크립트는 아래 경로에 증거 파일을 저장합니다.

`artifacts/android-real-device-qa/<run-id>/`

수집 항목:

- `device.json`: 기기 모델, Android 버전, 화면 크기, 선택된 기기.
- `manual-checklist.md`: 테스터가 바로 사용할 수 있는 한국어/영어 병기
  수동 pass/fail 체크리스트.
- `launch.png`: 실행 화면 스크린샷.
- `window.xml`: Android UIAutomator dump.
- `logcat.txt`: 실행 또는 수동 QA 이후 device log.
- `result.json`: 기계가 읽을 수 있는 실행 결과.
- `artifacts/android-real-device-qa-latest.json`: 최신 실제 실행, 즉 DryRun이
  아닌 실행 요약.
- `artifacts/android-real-device-qa-dryrun-latest.json`: 최신 DryRun 준비 점검
  요약. 런칭 증거와 섞이지 않도록 분리합니다.

런칭 증거 기록기는 interactive 스크립트가 `manual_e2e_confirmed`를 기록한
실기기 E2E artifact만 인정합니다. precheck 또는 dry run으로는 일반 공개 gate를
닫을 수 없습니다.
DryRun 결과는 `artifacts/android-real-device-qa-latest.json`을 덮어쓰지 않습니다.

## 필수 수동 확인 항목

테스터는 생성된 `manual-checklist.md`를 기준으로 pass/fail과 메모를 남깁니다.
생성되는 체크리스트는 한국어 Verbal 빌드를 휴대폰에서 테스트할 때 바로 볼 수
있도록 한국어/영어를 함께 표시합니다.

필수 흐름:

1. Verbal 설치 또는 실행.
2. Firebase 테스트 번호만이 아니라 실제 SMS 전화번호로 로그인.
3. 이용약관, 개인정보 처리방침, 커뮤니티 가이드라인 필수 동의 확인.
4. 프로필 설정과 user ID 예약.
5. 1:1 대화방 생성.
6. 텍스트 메시지 전송, 수정, 삭제.
7. 마이크 권한 허용 후 음성 메시지 전송.
8. 음성 transcript가 깨진 한글 없이 표시되는지 확인.
9. 음성 메시지 재생.
10. 파일과 위치 메시지 전송.
11. 기본 preset 없는 예약 전송.
12. 메시지 번역.
13. 캘린더 일정 생성, 수정, 삭제.
14. 채팅방 일정 제안 생성, 투표, 확정.
15. 오픈채팅 초대 링크 생성, 입장, 나가기.
16. 메시지 신고와 사용자 차단.
17. 계정 삭제 진입점 확인.

FCM foreground, background, terminated, lock-screen 수신은
`scripts/run-fcm-real-device-qa.ps1`로 별도 검증하고 런칭 증거 artifact로
기록합니다.

## 통과 기준

- 채팅, STT, 캘린더, 정책, 메뉴 UI에서 깨진 한글이 보이지 않습니다.
- 전송 버튼을 누른 뒤 음성 메시지 버블이 빠르게 표시됩니다.
- 음성 transcript가 표시되거나 복구 가능한 STT 실패 상태가 명확히 보입니다.
- Firebase Storage의 음성 재생이 동작합니다.
- FCM push 증거는 `scripts/run-fcm-real-device-qa.ps1`로 별도 수집하고 네
  가지 수신 상태가 모두 통과해야 합니다.
- 전송 실패 후 앱 재시작 없이 재시도할 수 있습니다.
- 앱 안에서 계정 삭제와 데이터 삭제 URL에 접근할 수 있습니다.

## 자동 검증과의 관계

실기기 QA 전에 아래 명령이 통과해야 합니다.

```powershell
cd C:\Users\jangs\OneDrive\바탕 화면\vibe_code\voice_messanger\functions
npm run verify:launch-readiness
npm run smoke:prod-e2e
```

위 명령이 통과해도 백엔드 smoke test는 Firebase 테스트 전화번호와 합성 음성을
사용하므로, 실제 기기 QA는 별도로 필요합니다.
