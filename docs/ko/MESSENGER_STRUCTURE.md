# 메신저 구조 벤치마크

확인일: 2026-05-27

이 문서는 인스타그램 DM, 카카오톡, 텔레그램의 메신저 기능을
Voice Messenger에 적용 가능한 구조로 정리한 것입니다.

목적은 경쟁 서비스를 복제하는 것이 아니라, 음성 중심 한국어
메신저에 필요한 기능 맵, 데이터 모델 방향, 구현 순서를 확정하는
것입니다.

## 경쟁사 기능 맵

### 기본 채팅

인스타그램 DM:

- 1:1 및 그룹 DM
- 메시지 답장
- 스티커, GIF, 사진, 영상, 음성 메시지 답장
- 읽음 표시 제어

카카오톡:

- 1:1 및 그룹 채팅
- 채팅방 폴더
- 보낸 메시지 수정과 삭제

텔레그램:

- 1:1 채팅, 그룹, 대형 그룹, 채널
- 답장, 멘션, 고정 메시지

Voice Messenger 방향:

- 1:1과 그룹 방을 먼저 안정화합니다.
- 넓은 소셜 기능보다 답장, 반응, 수정, 삭제, 읽음 상태를 먼저
  추가합니다.

### 인박스 정리

인스타그램 DM:

- 채팅 고정
- 메시지 요청
- 읽음 표시 켜기/끄기

카카오톡:

- 채팅방 폴더
- 안읽음 폴더

텔레그램:

- 폴더
- 보관
- 폴더 안 채팅 고정

Voice Messenger 방향:

- 고정, 보관, 음소거, 안읽음, 음성 중심 필터를 추가합니다.

### 메시지 액션

인스타그램 DM:

- 제한 시간 내 메시지 수정
- 메시지 고정
- 예약 전송
- 번역
- 음악 및 위치 공유

카카오톡:

- 보낸 메시지 수정과 삭제
- 답장 또는 댓글
- 검색
- 보이스톡 녹음 버블

텔레그램:

- 수정
- 예약
- 반응
- 번역
- 검색
- 비밀 채팅의 자동 삭제

Voice Messenger 방향:

- 수정, 삭제, 답장, 반응, 고정, 검색을 먼저 추가합니다.
- 예약과 번역은 출시 이후 단계로 둡니다.

### 음성 및 통화

인스타그램 DM:

- 음성 메시지
- 음성 답장
- 계정과 앱 환경에 따른 음성/영상 통화

카카오톡:

- 보이스톡과 페이스톡
- 통화 녹음이 채팅 버블로 표시
- AI 요약 출시 흐름

텔레그램:

- 음성 및 영상 통화
- 그룹 통화
- 그룹 보이스챗
- 음성 및 영상 메시지

Voice Messenger 방향:

- 음성 메시지와 변환 텍스트를 제품의 중심으로 둡니다.
- 이후 통화 녹음, 변환 텍스트, 요약 기능으로 확장합니다.

### 미디어 및 파일

인스타그램 DM:

- 사진, 영상, 릴스, 스티커, GIF, 음악 미리듣기, 위치

카카오톡:

- 사진, 영상, 파일, 숏폼 공유, 스티커, 이모티콘

텔레그램:

- 모든 유형의 파일
- 사진, 영상, 스티커, 봇, 미니 앱

Voice Messenger 방향:

- 음성 신뢰성이 안정된 뒤 이미지와 파일 첨부를 추가합니다.
- 숏폼과 소셜 공유는 MVP에서 제외합니다.

### 커뮤니티

인스타그램 DM:

- 그룹 채팅 QR 초대

카카오톡:

- 오픈채팅
- 오픈채팅 커뮤니티
- 보이스룸
- 공개 영역 관리

텔레그램:

- 공개 그룹
- 채널
- 초대 링크
- 봇과 미니 앱

Voice Messenger 방향:

- 초대 링크와 QR을 먼저 추가합니다.
- 오픈룸과 채널은 모더레이션이 준비된 뒤 추가합니다.

### 개인정보 및 안전

인스타그램 DM:

- 메시지 요청
- 읽음 표시 제어
- 신고
- 지원 환경의 사라지는 채팅 및 암호화 채팅

카카오톡:

- 그룹 초대 승인
- 신고 흐름
- 오픈채팅 강화 정책
- 개인정보 우선 정책

텔레그램:

- 비밀 채팅
- 자동 삭제 타이머
- 2단계 보안
- 봇 개인정보 모드

Voice Messenger 방향:

- 오픈 커뮤니티 전에 차단, 신고, 초대 승인을 먼저 추가합니다.
- 비밀 채팅은 별도 후순위 모드로 다룹니다.

## 벤치마크 결론

1. 인스타그램 DM은 가벼운 표현과 소셜 콘텐츠 흐름이 강합니다.
   우리에게 필요한 요소는 빠른 답장, 반응, 고정, 예약, 번역,
   위치, 그룹 QR 초대입니다.
2. 카카오톡은 한국 사용자의 일상 메신저 기대값을 가장 잘 보여줍니다.
   채팅방 폴더, 보낸 메시지 수정/삭제, 안읽음 정리, 그룹 초대 승인,
   보이스톡 녹음 버블을 참고해야 합니다.
3. 텔레그램은 파워유저와 커뮤니티 구조가 강합니다. 폴더/보관,
   강한 검색, 고정 메시지, 역할, 대형 방, 채널, 봇, 비밀 채팅
   구조를 참고해야 합니다.
4. Voice Messenger는 처음부터 전체 소셜 플랫폼이 되면 안 됩니다.
   먼저 고품질 음성-텍스트 메신저가 되고, 그 다음 정리된 채팅,
   이후 커뮤니티로 확장하는 순서가 맞습니다.

## 제품 구조

### 방 유형

`direct`

- 출시 상태: 현재 유지
- 목적: 1:1 비공개 대화
- 규칙: 사람 멤버 2명, 방 제목 필수 아님

`group`

- 출시 상태: 현재 강화
- 목적: 소규모 비공개 방
- 규칙: 초대 승인, 멤버 목록, 관리자 역할, 선택 제목

`open`

- 출시 상태: 이후
- 목적: 카카오톡 오픈채팅형 관심사 방
- 규칙: 검색 가능, 신고 중심, 강화된 모더레이션, 방별 공개 프로필

`channel`

- 출시 상태: 이후
- 목적: 텔레그램형 방송 채널
- 규칙: 관리자가 게시, 팔로워가 읽음, 선택 토론방 연결

`assistant`

- 출시 상태: 이후
- 목적: AI 또는 봇 대화
- 규칙: 봇 멤버, 명시적 도구 권한, 다른 채팅 접근 금지

### 멤버 역할

`owner`

- 적용 범위: 그룹, 오픈, 채널
- 권한: 방 관리, 역할 관리, 초대, 안전 설정, 방 삭제

`admin`

- 적용 범위: 그룹, 오픈, 채널
- 권한: 멤버 초대/내보내기, 메시지 고정, 메시지 관리, 방 정보 수정

`member`

- 적용 범위: 모든 사용자 방
- 권한: 방 권한에 따라 메시지 읽기와 전송

`guest`

- 적용 범위: 오픈 또는 채널 미리보기
- 권한: 가입 전 읽기 또는 미리보기만 가능

`bot`

- 적용 범위: 어시스턴트 및 향후 그룹 방
- 권한: 허용된 메시지만 읽고 제어된 명령으로 응답

### 메시지 유형

`text`

- 출시 상태: 현재 유지
- 구조: 일반 텍스트, 수정/삭제/답장 메타데이터

`voice`

- 출시 상태: 현재 강화
- 구조: 오디오, 길이, 변환 텍스트, STT 상태, 신뢰도, 언어

`image`

- 출시 상태: 다음 단계
- 구조: 저장소 첨부, 썸네일, 크기

`file`

- 출시 상태: 이후
- 구조: 저장소 첨부, 파일명, 용량, MIME 유형

`location`

- 출시 상태: 이후
- 구조: 위도, 경도, 라벨, 실시간 위치 만료 시간

`system`

- 출시 상태: 다음 단계
- 구조: 방 생성, 멤버 입장, 통화 종료, 안전 안내

`call_recording`

- 출시 상태: 이후
- 구조: 녹음 파일, 변환 텍스트, 요약, 통화 참여자

`shared_content`

- 출시 상태: 이후
- 구조: 링크 미리보기, 게시물/릴스/숏폼 자리표시자, 외부 출처

### 메시지 액션

P0:

- 메시지 답장
- 텍스트 수정
- 나에게서 삭제 / 모두에게서 삭제
- 읽음 표시 / 마지막 읽음
- 전송 상태: 전송 중, 전송됨, 전달됨, 읽음, 실패

P1:

- 반응
- 메시지 고정
- 방 안 검색

P2:

- 예약 전송
- 메시지 번역

P3:

- 사라지는 메시지

우선순위 기준:

- P0는 출시 품질의 대화와 STT 정정에 필요합니다.
- P1은 반복 사용성을 높입니다.
- P2는 핵심 루프가 안정된 뒤 유용합니다.
- P3는 개인정보, 보관, 신고 정책 결정이 먼저 필요합니다.

## Firestore 구조

`users/{uid}`

- `displayName`, `handle`, `photoUrl`, `phoneHash`
- `defaultSendMode`
- `privacy.readReceipts`
- `privacy.discoverableByHandle`
- `privacy.allowUnknownInvites`
- `createdAt`, `updatedAt`

`rooms/{roomId}`

- `type`: `direct`, `group`, `open`, `channel`, `assistant`
- `visibility`: `private`, `link`, `public`
- `title`, `photoUrl`, `description`
- `participantIds`: 비공개 방 조회용 비정규화 목록
- `ownerId`
- `capabilities.voice`
- `capabilities.text`
- `capabilities.media`
- `capabilities.calls`
- `capabilities.reactions`
- `capabilities.replies`
- `capabilities.pins`
- `capabilities.search`
- `lastMessage.kind`
- `lastMessage.preview`
- `lastMessage.senderId`
- `lastMessage.createdAt`
- `createdAt`, `updatedAt`

`rooms/{roomId}/members/{uid}`

- `role`: `owner`, `admin`, `member`, `guest`, `bot`
- `nickname`
- `joinedAt`, `lastReadAt`, `lastReadMessageId`
- `unreadCount`
- `notificationMode`: `all`, `mentions`, `muted`
- `pinned`, `archived`, `folderIds`
- `blockedUntil`, `leftAt`

`rooms/{roomId}/messages/{messageId}`

- `senderId`
- `kind`: `text`, `voice`, `image`, `file`, `location`, `system`,
  `call_recording`, `shared_content`
- `text`, `transcript`, `language`
- `sttStatus`, `sttConfidence`
- `audioPath`, `durationMs`
- `attachments[]`
- `replyTo.messageId`
- `replyTo.senderId`
- `replyTo.preview`
- `mentions[]`
- `reactions.{emoji}[]`
- `delivery.state`
- `delivery.deliveredToCount`
- `delivery.readByCount`
- `edit.editedAt`
- `edit.version`
- `edit.previousTextHash`
- `delete.deletedAt`
- `delete.deletedBy`
- `delete.mode`
- `expiresAt`
- `createdAt`, `updatedAt`

첨부 필드:

- `type`
- `storagePath`
- `url`
- `mimeType`
- `name`
- `size`
- `width`
- `height`
- `durationMs`

`rooms/{roomId}/pins/{messageId}`

- `messageId`
- `pinnedBy`
- `createdAt`
- `preview`

`roomInvites/{inviteId}`

- `roomId`
- `createdBy`
- `type`: `handle`, `link`, `qr`
- `status`: `active`, `revoked`, `expired`
- `expiresAt`, `createdAt`

`reports/{reportId}`

- `reporterId`
- `targetType`
- `targetId`
- `roomId`
- `messageId`
- `reason`
- `details`
- `status`
- `createdAt`, `reviewedAt`

`blocks/{uid}/users/{blockedUid}`

- `blockedAt`
- `reason`

`userFolders/{uid}/folders/{folderId}`

- `name`
- `filter`: `all`, `unread`, `voice`, `groups`, `custom`
- `roomIds`
- `sortOrder`
- `createdAt`, `updatedAt`

## Backend API 구조

방:

- `createRoom`
- `updateRoom`
- `joinRoomByInvite`
- `leaveRoom`
- `updateMemberRole`

메시지:

- `sendTextMessage`
- `sendVoiceMessage`
- `editMessage`
- `deleteMessage`
- `markRead`
- `addReaction`
- `removeReaction`
- `pinMessage`
- `unpinMessage`

음성/STT:

- `createTranscriptionDraft`
- `finalizeVoiceMessage`
- `retryTranscription`
- `summarizeCallRecording`

인박스:

- `setRoomPinned`
- `setRoomArchived`
- `setRoomMuted`
- `updateFolder`

안전:

- `reportMessage`
- `reportRoom`
- `blockUser`
- `resolveReport`

알림:

- `registerMessagingToken`
- `sendPrivacySafeNotification`
- `syncBadgeCount`

## UI 구조

### 인박스

- 상단 탭: `전체`, `안읽음`, `음성`, `그룹`
- 고정한 방을 일반 방 위에 배치
- 방 행: 아바타, 제목, 마지막 미리보기, 시간, 안읽음 배지, 음소거 아이콘
- 행 액션: 고정, 보관, 음소거, 삭제 또는 나가기
- 사람, 방, 메시지 변환 텍스트를 함께 찾는 검색 진입점

### 채팅방

- 헤더: 뒤로가기, 방 아바타/제목, 멤버 수/상태, 검색/정보
- 메시지 목록: 묶인 말풍선, 음성 아래 변환 텍스트, 수정/삭제 라벨
- 메시지 롱프레스 메뉴: 답장, 수정, 복사, 고정, 삭제, 신고
- 입력 영역: 텍스트 필드, 음성 녹음 버튼, 첨부 버튼, 전송 버튼
- 음성 검토 시트: 변환 텍스트 수정, STT 재시도, 전송 모드, 전송

### 방 정보

- 멤버와 역할
- 고정 메시지
- 공유 미디어와 파일
- 알림 설정
- 초대 링크와 QR
- 신고, 차단, 나가기

## 구현 로드맵

### Phase 1: 런칭 필수 메신저 기본기

- 메시지 생명주기: 전송 중, 전송됨, 실패. 전달/읽음은 FCM과
  읽음 추적 준비 상태에 따라 적용합니다.
- `replyTo`, `editedAt`, `deletedAt`, 삭제 모드
- 멤버별 인박스 고정, 보관, 음소거 상태
- 안읽음 카운트와 `lastReadAt`
- 멤버, 나가기, 신고, 차단이 있는 방 정보 화면
- 현재 방 안 변환 텍스트 검색

### Phase 2: 음성 중심 차별화

- STT 신뢰도와 언어 메타데이터
- 변환 재시도와 수정 이력
- 더 나은 음성 파형, 재생 속도, 변환 텍스트 접기/펼치기
- 향후 보이스톡형 흐름을 위한 통화 녹음 버블 모델
- 긴 녹음의 음성 변환 요약

### Phase 3: 성장과 커뮤니티

- 초대 링크와 QR 코드
- 그룹 관리자 역할과 권한
- 모더레이션 플래그 뒤에 공개/오픈 방 모델 추가
- 신고, 차단, 키워드 필터, 속도 제한이 준비된 뒤 방 검색/추천 추가

### Phase 4: 파워 기능

- 예약 전송
- 번역
- 만료 시간이 있는 위치 공유
- 파일 첨부
- 별도 개인정보 모드로 비밀/사라지는 방
- 명시적 권한 경계를 가진 봇/어시스턴트 방

## 추천 작업 순서

1. 메시지 답장, 수정, 삭제, 읽음/안읽음 상태 추가
2. 인박스 정리 기능 추가: 고정, 보관, 음소거, 안읽음, 음성 필터
3. 방 정보와 안전 액션 추가: 신고, 차단, 나가기, 초대 승인
4. 변환 텍스트 검색과 음성 메시지 품질 도구 추가
5. 안전 기본기가 잡힌 뒤 초대 링크와 QR 추가
6. 핵심 메신저 루프가 안정된 뒤 미디어, 파일, 위치, 예약, 번역 추가

## 참고 자료

- Meta: Instagram DM updates
  https://about.fb.com/news/2024/03/instagram-dm-updates/
- Meta: Instagram location sharing and nicknames
  https://about.fb.com/news/2024/11/new-ways-to-connect-through-dms/
- Meta: Instagram translation, music, scheduling, pinned messages, group QR
  https://about.fb.com/news/2025/02/new-instagram-dm-features-stay-connected/amp/
- Kakao: KakaoTalk service page
  https://www.kakaocorp.com/page/service/service/KakaoTalk?lang=ENG
- Kakao: if(kakao)25 KakaoTalk AI/features announcement
  https://www.kakaocorp.com/page/detail/11725?lang=ENG
- KakaoTalk Safety: operation policy
  https://talksafety.kakao.com/en/policy?lang=en
- KakaoTalk Safety: group chat participation settings
  https://talksafety.kakao.com/en/toolandguide/unwanted/joinsettings
- Telegram FAQ
  https://telegram.org/faq
- Telegram: folders and archive
  https://telegram.org/blog/folders
- Telegram: edit messages and mentions
  https://telegram.org/blog/edit/
- Telegram: scheduled messages
  https://telegram.org/blog/scheduled-reminders-themes
- Telegram: reactions and translation
  https://telegram.org/blog/Reactions-spoilers-Translations
