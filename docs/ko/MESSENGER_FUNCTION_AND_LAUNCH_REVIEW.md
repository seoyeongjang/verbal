# 메신저 기능 및 런칭 준비 재검토

원문: `docs/MESSENGER_FUNCTION_AND_LAUNCH_REVIEW.md`

작성 기준일: 2026-06-05

이 문서는 현재 Verbal의 메신저 기능을 인스타그램 DM, 카카오톡, 텔레그램과
비교한 뒤, 추가해야 할 기능 목록과 정식 런칭 전 남은 준비 단계를 정리합니다.

## 확인한 근거

- 현재 Verbal 구현 현황: `docs/LAUNCH_CHECKLIST.md`
- 메신저 벤치마크와 데이터 모델 방향: `docs/MESSENGER_STRUCTURE.md`
- 스토어/정책 체크리스트: `docs/RELEASE_STORE_CHECKLIST.md`
- 현재 앱/백엔드 소스 검색: `apps/mobile/lib`, `functions/src`,
  Firebase rules, 기존 문서
- 외부 경쟁사/스토어 정책 조사 기준일: 2026-06-05

## 경쟁사 시사점

| 서비스 | 주요 메신저 기능 신호 | Verbal에 주는 의미 |
| --- | --- | --- |
| 인스타그램 DM | 메시지 수정, 채팅 고정, 읽음 표시 제어, 스티커/GIF/사진/영상/음성 답장, 채팅 테마, 번역, 음악 스티커, 예약 메시지, 메시지 고정, 그룹 QR 초대 | 현재 DM형 UI는 유지하되 읽음 표시 프라이버시와 더 풍부한 답장/미디어 액션을 단계적으로 보강합니다. |
| 카카오톡 | 채팅방 폴더, 메시지 수정/삭제, 안읽음 폴더, 안읽은 대화 AI 요약, VoiceTalk 통화 녹음/텍스트 변환/요약/검색, 오픈채팅, 프로필/피드 공개 범위, 그룹 참여 설정, 신고/안전 정책 | 한국 사용자에게는 채팅 정리, 안전한 그룹 초대, 신고/차단, AI 요약이 기본 기대값입니다. 음성/통화 transcript는 Verbal과 잘 맞는 장기 차별화입니다. |
| 텔레그램 | 폴더, 보관함, 대형 그룹, 채널, 세부 관리자 권한, 고정 메시지, 예약 메시지/리마인더, 반응, 번역, QR, 저장한 메시지 태그, 1회 재생 음성/영상, 녹음 일시정지/재개, 상세 읽음 시간 | 파워 유저용 정리 기능, 저장한 메시지, 고급 음성 컨트롤, 프라이버시/읽음 제어, 채널/커뮤니티는 안전 기반이 검증된 뒤 추가합니다. |

## 현재 Verbal의 강점

- 음성 우선 메신저의 핵심은 이미 갖춰져 있습니다: 녹음, STT, transcript
  표시, 자동 전송, STT 재시도/수동 복구, Deepgram 백엔드 경로, 음성파일
  만료 후 transcript 보존.
- 핵심 채팅 액션도 대부분 반영되어 있습니다: 텍스트, 답장, 반응, 수정,
  흔적 없는 삭제, 고정/고정해제, 검색, 읽음 상태, 예약, 번역, 이미지,
  파일, 위치.
- 캘린더는 차별화 기능으로 볼 수 있습니다: 음성 일정 추가, 월간 캘린더,
  일정 상세, 알림, 아침 브리핑, 외부 캘린더 연동, 국가별 공휴일,
  채팅방 일정 제안/투표/확정.
- 그룹과 안전의 기본 골격도 있습니다: 초대 링크, QR, 승인 모드, 역할,
  멤버 제거, 나가기, 차단, 메시지/방 신고, 악용 민감 액션 cooldown.
- 런칭 문서 준비 수준도 MVP 대비 넓습니다: 개인정보 처리방침, 약관,
  데이터 삭제, 고객지원 매크로, moderation runbook, 스토어 체크리스트,
  Data Safety 초안, QA 계획, 비용 모델, 접근성 점검, 배포 상태 문서.

## 추가 기능 리스트

### P0: 공개 런칭 전 필수 또는 강력 권장

| 기능 | 필요한 이유 | 현재 상태 |
| --- | --- | --- |
| 실기기 전체 E2E 검증 | Verbal은 전화번호 인증, 마이크, STT, 푸시, Storage, 네이티브 권한에 의존합니다. 에뮬레이터/브라우저 확인만으로는 런칭 근거가 부족합니다. | 남은 런칭 차단 항목. |
| FCM foreground/background/terminated 검증 | 메신저에서 알림이 불안정하면 서비스가 바로 깨져 보입니다. | 백엔드 경로는 있으나 실기기 수신 검증 필요. |
| 음성 보존기간 만료 검증 | 제품 정책상 음성은 삭제되고 transcript는 남아야 합니다. 운영 데이터에서 증명해야 합니다. | Functions 소스는 있으나 운영 동작 검증 필요. |
| 가입 시 약관/개인정보/UGC 정책 동의 | Google Play UGC 정책은 UGC 생성/업로드 전 약관 또는 사용자 정책 동의를 요구합니다. | 정책 문서는 있으나 명시적 동의 gate 확인 또는 추가 필요. |
| 계정 삭제 웹 endpoint | Google Play는 앱 내 삭제와 별개로 삭제 요청용 웹 리소스를 요구합니다. | 앱 내 삭제는 있음. 외부 웹 endpoint 확정 필요. |
| moderation queue와 처리 workflow | 신고/차단 버튼만으로는 부족합니다. 운영자 처리, SLA, 이의제기, audit trail이 필요합니다. | runbook은 있음. 운영 도구/상태 workflow 검증 필요. |
| 안전센터 완성도 | Kakao/Apple/Google 패턴상 신고, 차단, 정책, 연락처, 보호 안내는 찾기 쉬워야 합니다. | 기본 메뉴는 있음. 신고 상태, 이의제기, 안전 안내 보강 필요. |
| 의심 링크/피싱 경고 | 한국 메신저에서 피싱/스팸 리스크가 큽니다. 카카오도 피싱 방지를 주요 안전 지표로 다룹니다. | P0 안전 보강 권장. |
| 읽음 표시 프라이버시 제어 | Instagram과 Telegram 모두 읽음 제어를 제공합니다. 사용자 기대값입니다. | 읽음 상태는 있으나 사용자 제어 기능 확인/보강 필요. |
| 전체 검색 | transcript-first 메신저에서는 채팅, transcript, 저장한 메시지, 파일, 캘린더를 한 번에 찾는 기능이 핵심입니다. | 방 내부 검색은 있음. 전체 검색은 추가 권장. |
| 저장한 메시지 v1 완성 | Telegram처럼 개인 저장함은 transcript, 링크, 파일, 일정 메모와 잘 맞습니다. | 메뉴는 있음. 태그/원본방 링크 포함한 완성 workflow 필요. |

### P1: 베타 경쟁력 강화 기능

| 기능 | 필요한 이유 | 권장 범위 |
| --- | --- | --- |
| 인박스 폴더/보관함/안읽음/음성 필터 | 카카오톡과 텔레그램 모두 대화 정리에 강합니다. | 사용자 지정 폴더, 보관함, 안읽음 필터, 음성 메시지 필터. |
| 음성 녹음 일시정지/재개 | 긴 음성 메시지 작성 시 Telegram식 조작 기대가 생깁니다. | 녹음 잠금, 일시정지, 재개, 폐기, 전송. |
| 재생 속도와 transcript 접기 | 음성 우선 UX에서는 빠른 청취와 화면 정리가 중요합니다. | 1x/1.5x/2x 재생, transcript compact toggle. |
| STT confidence와 수정 이력 | transcript 품질을 사용자가 이해하고 복구할 수 있게 합니다. | 낮은 신뢰 구간 표시, 수정 history 보존. |
| 신고 처리 상태 공개 | 사용자가 신고 후 결과를 알 수 있어야 신뢰가 생깁니다. | `접수`, `검토중`, `조치됨`, `종료`, 이의제기 링크. |
| 그룹 참여 제어 | 카카오톡의 그룹 참여 설정처럼 원치 않는 초대를 줄입니다. | 알 수 없는 초대자/참여자 미리보기, 참여/거절. |
| 방별 알림 세부 설정 | 실제 메신저 사용자는 알림을 매우 세밀하게 관리합니다. | 기간별 음소거, 멘션만, 음성만, 캘린더만. |
| 메시지 북마크/저장한 메시지로 저장 | 고정 메시지의 부담을 줄이고 개인 저장함을 활성화합니다. | 길게 누르기 저장, 태그, 원본방 backlink. |
| 캘린더 공유 고도화 | 채팅방 일정 제안은 Verbal의 차별화입니다. | 후보별 댓글, 제안별 알림, 추후 ICS/export. |
| Crashlytics/Analytics 운영 연동 | 베타를 감으로 운영하지 않으려면 실제 지표가 필요합니다. | 기존 이벤트 taxonomy를 실제 analytics/crash reporting에 연결. |

### P2: 안정 베타 이후 확장

| 기능 | 필요한 이유 | 런칭 판단 |
| --- | --- | --- |
| 채널/브로드캐스트 방 | Telegram/Kakao식 성장과 B2B 공식계정의 기반입니다. | moderation과 알림이 안정된 뒤 추가. |
| 오픈/커뮤니티 방 | 성장에는 좋지만 안전 리스크가 큽니다. | 안전센터, 스팸 제어, moderation queue 검증 전에는 제한. |
| 음성통화/통화 녹음 transcript/AI 요약 | Kakao VoiceTalk 방향과 Verbal의 음성 우선 컨셉이 잘 맞습니다. | 기본 음성 메시지가 안정된 뒤 고가치 로드맵. |
| AI 안읽은 대화 요약 | 카카오톡형 편의 기능입니다. | opt-in, 개인정보 고지, 비용 모니터링과 함께 추가. |
| 일반 투표 기능 | 그룹 메신저에서 유용합니다. | 현재 일정 제안 투표 구조를 확장. |
| 스티커/GIF/음악/반응팩 | 10~20대 메신저 mood에 도움됩니다. | 안정성과 안전 이후 추가. |
| 비즈니스 공식계정 | 개인 유저 과금 없이 수익화할 수 있는 경로입니다. | 계정/안전/정책 기반 이후 추가. |
| 커머스/선물/예약 링크 | Kakao식 ecosystem 수익원입니다. | 제휴 정책과 광고/상거래 고지가 필요합니다. |
| 봇/미니앱 | Telegram식 플랫폼 확장입니다. | 권한 경계와 악용 제어 전에는 보류. |
| 사라지는/비밀 채팅방 | 프라이버시 차별화입니다. | 암호화와 retention 정책 설계 전에는 런칭 기능으로 넣지 않습니다. |

## 정식 런칭 사전준비 리스트

### 제품 QA

- Android 실기기에서 운영 Firebase 전체 E2E를 수행합니다:
  전화번호 인증, 프로필, user id 선점, 방 생성, 텍스트, 음성 STT, 첨부,
  위치, 예약, 번역, 초대 QR, 음성 일정 추가, 일정 수정/삭제, 일정 제안,
  메시지 수정/삭제, 신고, 차단, 나가기.
- 실제 한국어 발화 기준으로 STT 지연시간과 transcript 품질을 측정합니다:
  여러 기기, 억양, 주변 소음, 네트워크 상태를 포함합니다.
- 음성 자동 전송이 잘못된 fallback text를 보내지 않는지 확인합니다.
  STT 실패 시에만 재시도/수동 복구가 열려야 합니다.
- 메시지 전송 속도, reconnect, offline/저속 네트워크, 중복 전송 방지를
  검증합니다.
- 접근성 검증을 반복합니다: 글자 크기, 터치 영역, 스크린리더, 대비,
  키보드 포커스.

### 알림과 네이티브 연동

- Android 실기기에서 FCM foreground, background, terminated, 잠금화면,
  token refresh를 검증합니다.
- iOS 런칭이 범위에 포함된다면 APNs를 설정하고 TestFlight 푸시를 검증합니다.
- 마이크, 알림, 사진/파일, 위치 권한의 허용/거부/재시도 flow를 확인합니다.
- Google Calendar와 Apple Calendar 연동 상태를 확인합니다:
  연결됨, 연결 해제, 권한 거부, sync 실패.

### 데이터, 보안, 운영

- 릴리즈 대상 데이터 모델 변경 후 Firestore/Storage rules test를 다시 실행합니다.
- 계정 삭제가 범위 내 사용자 데이터를 삭제 또는 익명화하는지 검증합니다:
  메시지, 음성, transcript, 첨부, 캘린더, 법적으로 삭제 가능한 신고 데이터,
  필요한 경우 제3자 STT provider 삭제 요청.
- 데이터 내보내기 JSON이 계정, 메시지, 저장한 메시지, 캘린더, 주요 metadata를
  포함하는지 확인합니다.
- 음성 보존기간 job이 음성파일은 삭제하고 transcript와 audit metadata는 남기는지
  검증합니다.
- Firebase/GCP 예산, logging alert, Deepgram 사용량 alert, 이상 사용량 alert가
  실제로 켜져 있는지 확인합니다.
- 백업, 장애 대응, rollback, release versioning 절차를 확정합니다.

### 안전과 정책

- 가입 단계에서 이용약관, 개인정보 처리방침, 사용자/UGC 정책 동의를 추가 또는 검증합니다.
- 메시지, 방, 프로필, 초대, 공개/커뮤니티 콘텐츠에 대한 신고/차단 경로를 확인합니다.
- moderation queue, 운영자 메모, 이의제기 처리, 신고 상태 안내를 구축 또는 검증합니다.
- 광범위한 초대/커뮤니티 기능을 열기 전 의심 링크/피싱 경고를 추가합니다.
- 오픈/커뮤니티 방은 moderation capacity가 증명되기 전까지 feature flag 뒤에 둡니다.

### 스토어와 법무

- Google Play Console 앱 등록을 만들고 최신 AAB를 internal testing에 업로드합니다.
- Google Play Data Safety, content rating, target audience, ads declaration,
  permissions declaration, account deletion web URL을 완료합니다.
- 개인정보 처리방침, 이용약관, 데이터 삭제 정책, 위치기반서비스 약관,
  고객지원 연락처, 한국 런칭용 청소년 보호정책을 최종화합니다.
- 스크린샷/영상 자료를 준비합니다:
  인증, 홈, 채팅, 음성 STT, 캘린더, 일정 제안, 설정, 신고/차단, 계정 삭제.
- iOS도 포함한다면 App Store metadata, TestFlight, APNs, privacy nutrition labels,
  account deletion review notes를 준비합니다.

## 권장 다음 개발 순서

1. 실기기 운영 QA를 끝내고 남은 P0 런칭 차단 항목을 닫습니다.
2. 약관/사용자 정책 명시 동의가 강제되어 있지 않다면 추가합니다.
3. 계정 삭제 웹 endpoint를 만들고 Play Console 및 정책 문서에 연결합니다.
4. 전체 검색을 추가합니다: 방, transcript, 저장한 메시지, 첨부, 캘린더.
5. 저장한 메시지를 태그와 원본방 backlink까지 포함해 완성합니다.
6. 인박스 폴더/보관함/안읽음/음성 필터를 추가합니다.
7. 읽음 표시 프라이버시와 그룹 참여 미리보기/거절 기능을 추가합니다.
8. 안전센터를 고도화합니다: 신고 상태, 이의제기, 피싱 경고, 신고하고 나가기.
9. 고급 음성 컨트롤을 추가합니다: 일시정지/재개, 재생 속도, transcript 접기,
   confidence/수정 이력.
10. 알림, 삭제, 보존기간, moderation, 스토어 정책 gate가 검증된 뒤 closed beta를 시작합니다.

## 참고 자료

- Meta Newsroom, Instagram DM updates:
  https://about.fb.com/news/2024/03/instagram-dm-updates/
- Meta Newsroom, Instagram DM translation, scheduling, pinned content, group QR:
  https://about.fb.com/news/2025/02/new-instagram-dm-features-stay-connected/amp/
- Meta Newsroom, Instagram location sharing and nicknames:
  https://about.fb.com/news/2024/11/new-ways-to-connect-through-dms/
- KakaoTalk service page:
  https://www.kakaocorp.com/page/service/service/KakaoTalk?lang=ENG
- Kakao if(kakao)25 AI and KakaoTalk update:
  https://www.kakaocorp.com/page/detail/11725?lang=ENG
- KakaoTalk Safety Report:
  https://talksafety.kakao.com/en/report/overview?lang=en
- KakaoTalk Operation Policy:
  https://talksafety.kakao.com/en/policy?lang=en
- KakaoTalk group participation settings:
  https://talksafety.kakao.com/en/toolandguide/unwanted/joinsettings
- Telegram FAQ:
  https://telegram.org/faq
- Telegram folders:
  https://telegram.org/blog/folders
- Telegram scheduled messages:
  https://telegram.org/blog/scheduled-reminders-themes
- Telegram reactions and translation:
  https://telegram.org/blog/reactions-spoilers-translations
- Telegram Saved Messages and one-time voice:
  https://telegram.org/blog/new-saved-messages-and-9-more
- Google Play account deletion requirement:
  https://support.google.com/googleplay/android-developer/answer/13327111?hl=en-EN
- Google Play UGC policy:
  https://support.google.com/googleplay/android-developer/answer/9876937?hl=en
- Apple App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
- Apple account deletion guidance:
  https://developer.apple.com/support/offering-account-deletion-in-your-app
