# Verbal 출시 진행 기록 - 2026-06-22

이 문서는 Verbal 앱을 일반 사용자에게 공개 노출하기 전 현재까지 완료된 출시 준비 상태를 기록합니다.

## 완료된 항목

- 앱명과 출시 자료를 Verbal 기준으로 정리했습니다.
- Android release AAB를 Google Play 내부 테스트 트랙에 업로드했습니다.
- 패키지 `com.voicebeta.verbal` 기준으로 Google Play Console 앱을 생성했습니다.
- Google Play App content와 Data Safety 선언을 완료했습니다.
- `https://verbal.chat` 도메인에 정책 페이지를 배포했습니다.
  - 개인정보처리방침: `https://verbal.chat/privacy`
  - 이용약관: `https://verbal.chat/terms`
  - 커뮤니티 가이드라인: `https://verbal.chat/community-guidelines`
  - 계정 삭제: `https://verbal.chat/account/delete`
  - 데이터 삭제: `https://verbal.chat/data-deletion`
- Firebase 테스트 전화번호 계정으로 Play 검토자 접근 정보를 설정했습니다.
- 사전 출시 보고서 설정에 검토자 로그인 정보를 저장했습니다.
- App content/Data Safety 완료 사실을 로컬 출시 증거 파일에 기록했습니다.

## 포함된 제품 및 백엔드 업데이트

- 음성 메시지, STT transcript 처리, pending 음성 메시지 최종화, 음성 파일 보존 정책 흐름.
- 캘린더 일정, 음성 일정 생성, 일정 알림, 아침 브리핑, 외부 캘린더 연동, 공휴일 지원, 채팅방 일정 제안.
- 메시지 수정/삭제, 고정 메시지 동작, 메시지 박스 크기, 재생 버튼, 최신 메시지 스크롤 등 메시징 UX 개선.
- 홈 메뉴와 설정 IA 개선: 내 프로필, 요청 메시지, 고객지원, 약관/정책, 데이터 및 저장공간, 개인정보 및 보안, 언어/테마, 계정 관리.
- 오픈채팅 친구 초대 및 링크 공유 지원.
- Firebase Functions, Firestore rules, Storage rules, 출시 검증 스크립트, Play Console 지원 산출물.
- 플러그인 플랫폼 기획 및 초기 서비스/API 구조.

## 실행한 검증

- `npm run record:app-content-submitted`
  - 결과: App content 게이트 완료로 기록됨.
- `npm run status:launch`
  - 현재 단계: `google_play_internal_testing_uploaded`
  - 다음 단계: `Review Google Play Pre-launch report`
- `npm run verify:launch-evidence`
  - 외부 증거가 남아 있으므로 미완료가 정상입니다.
- `npm run verify:public-release-gate`
  - 공개 노출이 아직 차단되어 있으므로 실패가 정상입니다.

## 남은 공개 노출 차단 항목

1. `play_prelaunch_report_reviewed`
   - Google Play 사전 출시 보고서 생성을 기다립니다.
   - 안정성, 성능, 접근성, 스크린샷 항목을 검토합니다.
   - 검토 후 다음 명령으로 증거를 기록합니다:
     `npm run record:prelaunch-reviewed -- --report-url <https-url>`
2. `play_closed_testing_completed`
   - 닫힌 테스트를 완료하거나 Play Console에서 불필요하다고 확인된 사유를 기록합니다.
3. `android_real_device_e2e_verified`
   - Android 실기기 전체 E2E QA를 실행합니다.
4. `fcm_real_device_delivery_verified`
   - FCM foreground, background, terminated, lock-screen 수신을 검증합니다.

## 현재 판단

현재 Verbal은 내부 테스트 진행 단계까지 준비되었습니다. 일반 사용자 공개 노출은 아직 준비되지 않았으며, 위 4개 외부 게이트를 완료하고 `npm run verify:public-release-gate`가 통과할 때까지 계속 차단해야 합니다.
