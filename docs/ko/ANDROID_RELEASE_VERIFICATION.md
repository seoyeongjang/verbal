# Android 릴리즈 검증

원문: `docs/ANDROID_RELEASE_VERIFICATION.md`

상태 기준일: 2026-06-19

이 문서는 Google Play Internal testing에 AAB를 업로드하기 전에 통과해야 하는
로컬 Android 릴리즈 gate를 정의합니다.

## 명령

repo root에서 실행합니다.

```powershell
.\scripts\verify-android-release-artifact.ps1
```

스크립트는 아래 파일을 생성합니다.

- `artifacts/android-release-verification-<run-id>.json`
- `artifacts/android-release-verification-latest.json`

## 검증 항목

- Android package name이 `com.voicebeta.verbal`인지.
- Android namespace가 package name과 일치하는지.
- `google-services.json` package name이 Android package와 일치하는지.
- Firebase project/app ID가 존재하는지.
- `pubspec.yaml` version에 version name과 version code가 모두 있는지.
- `dist/android/app-release.aab`가 존재하고 크기가 정상 범위인지.
- `dist/android/app-release.aab`가 Gradle build output AAB와 동일한지.
- release AAB가 앱 소스 파일보다 최신인지.
- `key.properties`와 `upload-keystore.jks`가 존재하는지.
- release build가 debug signing으로 fallback하지 않는지.
- `keytool`이 upload key를 읽고 SHA-1/SHA-256 fingerprint를 생성할 수
  있는지.

## 중요한 이유

Google Play는 package identity, versioning, signing 관계가 올바를 때만
업데이트를 받아들입니다. 이 문제를 로컬에서 먼저 잡으면 Play Console 업로드
또는 심사 사이클을 낭비하지 않을 수 있습니다.

## 후속 조치

upload keystore와 `key.properties`는 안전하게 백업해야 합니다. 비밀번호를
공개 저장소에 커밋하지 마세요. 이미 Play Console에 앱을 업로드했다면 Google
Play App Signing의 upload key rotation 절차 없이 upload key를 교체하면
안 됩니다.
