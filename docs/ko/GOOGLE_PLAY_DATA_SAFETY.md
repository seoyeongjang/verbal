# Google Play Data Safety 초안

원문: `docs/GOOGLE_PLAY_DATA_SAFETY.md`

상태 기준일: 2026-06-18

이 문서는 현재 Verbal MVP 기준의 Play Console Data Safety 초안입니다.
최종 제출 전 운영 빌드, 개인정보처리방침, 실제 활성화된 연동과 일치하는지
반드시 재검토해야 합니다.

## 데이터 수집 요약

앱은 메시징, 인증, 안전, 서비스 운영에 필요한 사용자 제공 데이터와 앱 생성
데이터를 수집합니다.

| 데이터 유형 | 수집 | 공유 | 목적 | 필수 여부 |
|---|---:|---:|---|---:|
| 전화번호 | 예 | 아니오 | 계정 생성, 로그인, 악용 방지 | 필수 |
| 사용자 ID | 예 | 아니오 | 프로필, 아이디, 대화방 멤버십 | 필수 |
| 이름/프로필 텍스트 | 예 | 아니오 | 채팅 내 프로필 표시 | 필수 |
| 텍스트 메시지 | 예 | 아니오 | 메시지 전송과 표시 | 필수 |
| 음성 녹음 | 예 | Deepgram 처리 | STT와 음성 메시지 전송 | 음성 사용 시 필수 |
| 음성 transcript | 예 | 아니오 | 메시지 표시와 검색 | 음성 사용 시 필수 |
| 사진/파일 | 예 | 아니오 | 사용자가 요청한 첨부 전송 | 선택 |
| 위치 | 예 | 아니오 | 사용자가 요청한 위치 공유 | 선택 |
| 캘린더 일정/리마인더 | 예 | 아니오 | 사용자가 요청한 일정 생성과 알림 | 선택 |
| 신고/안전 처리 메타데이터 | 예 | 아니오 | 신고 처리, 악용 방지, 서비스 안전 | 안전 기능에 필수 |
| 연락처 | 아니오 | 아니오 | 현재 MVP에서는 수집하지 않음 | 해당 없음 |
| 기기 또는 기타 ID | 예 | 아니오 | FCM 푸시 토큰, 악용 방지, 앱 운영 | 필수 |
| 앱 상호작용 | 예 | 아니오 | 사용량, 비용, 안정성 모니터링 | 필수 |
| 크래시 로그/진단 | 예 | 아니오 | 안정성 개선과 디버깅 | 선택 |

## 상세 Play Console 입력 매트릭스

Play Console에서 데이터 유형별 수집/공유/목적/필수 여부/삭제 처리를 묻는
경우 아래 표를 기준으로 입력합니다. 최종 답변은 실제 제출 빌드와 일치해야
합니다.

| Category | Data type | Collected | Shared | Required | Purposes | Deletion/retention handling |
|---|---|---:|---:|---:|---|---|
| Personal info | Phone number | Yes | No | Yes | App functionality, account management, fraud prevention, security | Deleted or de-identified through account deletion flow |
| Personal info | User IDs | Yes | No | Yes | App functionality, account management, chat membership | Deleted or de-identified through account deletion flow |
| Personal info | Name / profile text | Yes | No | Yes | App functionality, profile display, communication | Deleted or de-identified through account deletion flow |
| Messages | Text messages | Yes | No | Yes | App functionality, user-requested message delivery | User can delete messages; account deletion may anonymize retained conversation records |
| Audio | Voice recordings | Yes | Yes, service-provider processing by Deepgram | No | App functionality, speech-to-text, voice message delivery | Audio expires by retention policy; transcript may remain for chat history and search |
| Messages | Voice transcripts | Yes | No | Yes for voice messaging | App functionality, accessibility, message display, search | User can delete messages; account deletion may anonymize retained conversation records |
| Photos and videos / Files and docs | Photos, media, and files | Yes | No | No | App functionality, user-requested attachment delivery | User can delete sent messages or request account/data deletion |
| Location | Approximate/precise location when shared | Yes | No | No | App functionality, user-requested location sharing | User can delete sent messages or request account/data deletion |
| Calendar | Calendar events and reminders inside Verbal | Yes | No | No | App functionality, user-requested schedule creation and reminders | User can update/delete calendar events or request account/data deletion |
| App activity | Safety reports and moderation metadata | Yes | No | Yes for safety features | Fraud prevention, security, compliance, abuse handling | May be retained as needed for safety, legal, and abuse-prevention obligations |
| Device or other IDs | FCM tokens and device/service identifiers | Yes | No | Yes | App functionality, notifications, security, service operation | Removed or rotated when no longer needed or on account deletion where applicable |
| App activity | App interactions | Yes | No | Yes | Analytics, reliability, cost monitoring, product improvement | Aggregated or deleted according to retention and account deletion policy |
| App info and performance | Crash logs and diagnostics | Yes | No | No | Crash analysis, reliability, debugging | Retained according to Firebase/Crashlytics diagnostic retention settings |
| Contacts | Contacts | No | No | No | Not collected in the current submitted build unless contact sync is enabled | Not applicable |

## 보안 관행

- 데이터는 HTTPS/TLS로 전송 중 암호화됩니다.
- Firebase는 Google Cloud 관리 인프라로 운영 데이터를 저장합니다.
- Firestore와 Storage 보안 규칙은 방/메시지 데이터를 인증된 방 참여자로
  제한합니다.
- Cloud Functions가 메시지, 초대, 신고, STT, 보존기간 만료 같은 권한 작업을
  처리합니다.
- 앱 내 계정 삭제와 데이터 내보내기 흐름이 구현되어 있습니다.

## 음성 보존기간

- 기본 음성파일 보존기간: 1일.
- 방 단위 보존 옵션: 1일, 7일, 사용자 지정.
- 만료 후 음성파일은 삭제되고 transcript는 채팅 기록에 유지됩니다.

## 제3자 처리

- Deepgram은 음성파일을 speech-to-text 변환 목적으로 처리합니다.
- Google Firebase/Google Cloud는 인증, 데이터베이스, 스토리지, Functions, 푸시,
  로깅, 모니터링 인프라를 제공합니다.

## Play Console 답변 메모

- 빠른 답변:

| Console 질문 | 답변 |
|---|---|
| 앱이 사용자 데이터를 수집하거나 공유하나요? | 예 |
| 모든 사용자 데이터가 전송 중 암호화되나요? | 예 |
| 사용자가 데이터 삭제를 요청할 수 있나요? | 예 |
| 앱에 계정 삭제 URL이 있나요? | 예: `https://verbal.chat/account/delete` |
| 앱이 광고 목적으로 데이터를 수집하나요? | 현재 업로드된 AAB 기준 아니오 |
| 앱이 제3자와 데이터를 공유하나요? | 서비스 제공자 처리 목적에 한해 예: Deepgram 음성 STT, Google Firebase/Cloud 인프라 |
| 가능한 경우 데이터 수집이 선택 사항인가요? | 음성 녹음, 미디어/파일, 위치, 캘린더, 알림, crash diagnostics, 향후 연락처 동기화는 선택입니다. 계정, 메시징, 안전, 서비스 식별자는 핵심 기능 제공에 필요합니다. |

- 데이터 수집은 공개로 표시합니다.
- 데이터 공유는 신중히 표시합니다.
  - Deepgram은 앱 기능 제공을 위한 음성 처리 서비스 제공자입니다.
  - Google Firebase/Cloud는 인프라 서비스 제공자입니다.
- 사용자 삭제 요청 가능: 예.
- 전송 중 암호화: 예.
- 삭제 메커니즘 제공: 예. 앱 내 계정 삭제와 게시된 데이터 삭제 정책 기준.

## 공개 정책 URL

- 개인정보처리방침: `https://verbal.chat/privacy`
- 이용약관: `https://verbal.chat/terms`
- 커뮤니티 운영정책 / UGC 정책:
  `https://verbal.chat/community-guidelines`
- 계정 삭제: `https://verbal.chat/account/delete`
- 데이터 삭제: `https://verbal.chat/data-deletion`
