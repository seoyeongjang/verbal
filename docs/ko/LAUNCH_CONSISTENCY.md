# 런칭 정합성 검증

원문: `docs/LAUNCH_CONSISTENCY.md`

상태 기준일: 2026-06-19

이 문서는 최신 릴리즈 AAB, Android 릴리즈 검증, Google Play Console pack,
launch gate, launch handoff가 모두 같은 릴리즈 후보를 설명하는지 확인하는
정합성 검증을 설명합니다.

## 명령

저장소 루트에서 실행합니다.

```powershell
cd .\functions
npm run verify:launch-consistency
```

preinternal 릴리즈 체크도 launch handoff 생성 후 이 명령을 자동으로
실행합니다.

```powershell
npm run verify:preinternal
```

## 산출물

명령 실행 후 아래 파일이 생성됩니다.

- `artifacts/launch-consistency-<run-id>.json`
- `artifacts/launch-consistency-latest.json`

## 확인 항목

- `dist/android/app-release.aab`의 SHA-256과 크기가 최신 Play Console pack과
  일치하는지 확인합니다.
- 최신 Android 릴리즈 검증의 SHA-256과 크기가 현재 AAB와 일치하는지
  확인합니다.
- Play Console pack의 패키지명과 Firebase App ID가 Android 릴리즈 검증과
  일치하는지 확인합니다.
- Launch handoff의 정책 URL이 Play Console pack의 URL과 일치하는지
  확인합니다.
- Launch handoff가 실제 존재하는 Play Console pack과 closed testing pack을
  가리키는지 확인합니다.
- Launch handoff가 오래된 생성 파일이 아니라 최신 timestamp Play Console
  pack과 closed testing pack을 가리키는지 확인합니다.
- Launch handoff의 readiness/blocker 상태가 `artifacts/launch-gate-latest.json`과
  일치하는지 확인합니다.
- Play Console pack이 공개 `verbal.chat` 정책 URL과 `support@verbal.chat`을
  사용하는지 확인합니다.

## 사용 시점

Play Console 업로드 또는 일반 공개 단계 전 사용합니다. 오래된 생성 파일,
오래된 AAB metadata, 잘못된 handoff 안내를 잡기 위한 검증입니다.

이 명령이 실패하면 계속 진행하지 말고 `npm run verify:preinternal`로 Play
Console pack, launch gate, handoff를 다시 생성한 뒤 확인합니다.
