# Play App content 입력 워크시트

원문: `docs/PLAY_APP_CONTENT_WORKSHEET.md`

상태 기준일: 2026-06-18

이 문서는 Google Play Console > Policy and programs > App content 입력용
워크시트입니다. 운영용 정리 문서이며 법률 자문은 아닙니다. 최종 답변은
실제로 제출하는 빌드와 일치해야 합니다.

자동 생성된 입력용 답변 패키지:
`artifacts/play-console/verbal-app-content-answers-latest.md`

복사 버튼이 있는 HTML 시트:
`artifacts/play-console/verbal-app-content-copy-sheet-latest.html`

이 답변 패키지에는 Play Console의 한국어/영어 섹션명, 입력값/출처, 섹션 저장 후
`npm run record:launch-evidence`로 기록할 evidence flag가 표로 포함됩니다.

2026-06-18 기준 Google 공식 문서 확인 내용:

- App content에는 개인정보 처리방침, 광고 여부, 로그인/접근 정보, 대상
  연령과 콘텐츠, 민감 권한, 콘텐츠 등급, Data Safety, 뉴스/COVID-19
  선언 등이 포함됩니다.
- Data Safety는 앱과 제3자 SDK/처리업체가 수집/처리하는 데이터를 함께
  반영해야 합니다.
- 앱 안에서 계정 생성이 가능하면 앱 내부 계정 삭제 경로와 웹 계정/데이터
  삭제 요청 링크가 필요합니다.

## 1. 개인정보 처리방침

- Console 답변: 개인정보 처리방침 URL 입력.
- URL: `https://verbal.chat/privacy`
- 내부 원문: `docs/PRIVACY_POLICY.md`
- 앱 내부 경로: 회원가입 동의 화면 및 약관/정책 메뉴.

## 2. App Access / Sign-in details

- Console 답변: 전화번호 로그인 후 주요 기능 접근 가능.
- 사용 문서: `docs/PLAY_REVIEWER_ACCESS.md`
- 테스트 전화번호: `+16505550101`
- 인증 코드: `123456`
- 결제/구독 필요 여부: 아니오
- 외부 멤버십/초대 필요 여부: 아니오

Play Console Sign-in details 입력란에는
`docs/PLAY_REVIEWER_ACCESS.md`의 입력용 문구를 붙여 넣습니다.

## 3. 광고

- 현재 제출 빌드 기준 권장 답변: 실제 광고 SDK 또는 운영 광고 지면이
  제출 AAB에 활성화되어 있지 않다면 `No` 선택.
- 현재 앱 참고: 제품 기획에는 네이티브 광고 영역이 있지만, Play Console
  광고 선언은 제출 빌드 기준으로 판단해야 합니다. 실제 광고 SDK, 배너,
  네이티브 광고, 전면 광고, 스폰서드 피드, 하우스 광고가 활성화되면
  `Yes`로 변경해야 합니다.

## 4. Data Safety

- 사용 문서: `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- 개인정보 처리방침: `https://verbal.chat/privacy`
- 계정 삭제 URL: `https://verbal.chat/account/delete`
- 데이터 삭제 안내 URL: `https://verbal.chat/data-deletion`
- 제3자 처리 고지:
  - Firebase / Google Cloud: 인증, 데이터베이스, 저장소, Functions,
    Analytics, Crashlytics, 푸시 인프라.
  - Deepgram: 음성 STT 처리.
- form에서 검토할 데이터 범주:
  - 전화번호 및 사용자/계정 식별자.
  - 프로필 텍스트, 표시 이름, 사용자 ID, 친구/연락처 메타데이터.
  - 메시지, 음성 녹음, 음성 transcript, 첨부 파일.
  - 캘린더 일정 및 알림.
  - 사용자가 선택적으로 공유하는 위치.
  - 디바이스 ID, 푸시 토큰, 진단 정보, 앱 상호작용.

## 5. 데이터 삭제

- 앱 내 계정 생성 지원: 예.
- 앱 내부 계정 삭제 경로: 햄버거 메뉴 > 계정/설정 영역 > 계정 삭제.
- 웹 계정 삭제 경로: `https://verbal.chat/account/delete`
- 데이터 삭제 안내: `https://verbal.chat/data-deletion`
- 고객지원 이메일: `support@verbal.chat`
- 내부 원문: `docs/DATA_DELETION_POLICY.md`

## 6. 대상 연령 및 콘텐츠

- 내부 테스트/초기 closed beta 기준 보수적 권장안: 청소년 정책, 운영
  moderation, 법무 검토가 끝나기 전에는 성인 대상 연령만 선택합니다.
- Verbal을 10대 사용자에게 의도적으로 열 경우, teen age group 선택 전에
  청소년/안전 정책 검토를 별도로 완료해야 합니다.
- 이유: Verbal은 사용자 생성 메시지, 음성 녹음, 오픈채팅/링크 공유,
  선택적 위치 공유, 신고/차단 흐름을 포함합니다.

## 7. 콘텐츠 등급

제출 빌드 기준으로 답변합니다.

- 앱 카테고리: Communication / social messaging.
- 사용자 상호작용 및 사용자 생성 콘텐츠: 예.
- 사용자 간 메시징: 예.
- 오픈채팅 또는 초대 링크 기반 방: 빌드에서 활성화되어 있으면 예.
- 위치 공유: 빌드에서 활성화되어 있으면 예, 사용자 직접 실행.
- 구매/도박/뉴스/정부/의료/금융 기능: 제품 범위가 바뀌지 않는 한 아니오.
- Moderation 기능: 신고, 차단, 안전센터, 커뮤니티 가이드라인.

## 8. 민감 권한

Play Console은 AAB 업로드 후 권한을 읽어 평가하므로 업로드 뒤 확인합니다.

- 마이크: 음성 메시지 녹음 및 음성 캘린더 입력.
- 알림: 메시지 푸시 및 캘린더 알림.
- 연락처: 제출 빌드에서 연락처 동기화가 활성화된 경우에만.
- 위치: 사용자가 명시적으로 위치 공유를 실행할 때만.
- 카메라/사진/파일: 사용자가 미디어나 파일을 첨부할 때만.

Play Console이 권한 선언을 요구하면, 사용자에게 보이는 기능, 권한이
선택인지 필수인지, 앱 내 고지 경로를 정확히 설명해야 합니다.

## 9. 뉴스, 정부, COVID-19, 건강, 금융

현재 Verbal 범위:

- 뉴스 앱: 아니오
- 정부 앱: 아니오
- COVID-19 접촉 추적/상태 앱: 아니오
- 건강 앱: 아니오
- 금융 기능: 아니오
- 도박/현금성 게임: 아니오

향후 기능 범위가 바뀌면 답변을 다시 검토합니다.

## 10. 앱 카테고리, 연락처, 스토어 등록정보

- 앱 카테고리: Communication / social messaging.
- 연락처 이메일: `support@verbal.chat`
- 웹사이트: `https://verbal.chat`
- 스토어 등록정보 문구:
  `artifacts/store/google-play/ko-KR/`와
  `artifacts/store/google-play/en-US/`를 사용합니다.
- 앱 아이콘: `artifacts/store/google-play/assets/app-icon-512.png`
- 피처 그래픽:
  `artifacts/store/google-play/assets/feature-graphic-1024x500.png`
- 휴대전화 스크린샷:
  `artifacts/store/google-play/assets/phone-screenshots/`

## 11. UGC 및 안전

- UGC 존재 여부: 예. 사용자가 메시지, 음성, 프로필, 첨부 파일,
  오픈채팅 콘텐츠를 만들 수 있습니다.
- 공개 정책 URL: `https://verbal.chat/community-guidelines`
- 넓은 테스트 전 확인해야 할 안전 기능:
  - 사용자/메시지/채팅 신고.
  - 사용자 차단.
  - 요청 메시지 제어.
  - 안전센터 진입.
  - moderation/support 처리 경로.

## 12. 제출 전 수동 확인

Send for review를 누르기 전에 확인합니다.

- 공개 URL이 HTTPS로 열리는지.
- Data Safety 답변이 `docs/GOOGLE_PLAY_DATA_SAFETY.md`와 일치하는지.
- App access 테스트 계정이 제출 빌드에서 동작하는지.
- AAB package name이 `com.voicebeta.verbal`인지.
- 스토어 설명이 미지원 기능을 과장하지 않는지.
- 실제 광고 SDK 또는 광고 지면이 활성화되어 있으면 Ads를 `Yes`로
  변경했는지.
