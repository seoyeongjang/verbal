# 데이터 모델

## Firestore

`users/{uid}`

- `displayName`: 사용자에게 표시되는 이름.
- `handle`: 초대와 검색에 사용하는 소문자 ID.
- `phoneHash`: 전화번호 검색용 예약 필드.
- `photoUrl`: 선택 프로필 이미지.
- `defaultSendMode`: `confirm` 또는 `instant`.
- `holidayCountryCode`: 캘린더 공휴일 표시 국가. `none`, `KR`, `US`,
  `JP`, `CN` 중 하나입니다.
- `deletedAt`: 계정 삭제 후 기록되는 시각.
- `createdAt`, `updatedAt`.

`users/{uid}/calendarEvents/{eventId}`

- `ownerId`: `{uid}`와 동일한 일정 소유자 ID.
- `title`: 1-120자 일정 제목.
- `startAt`: 일정 시작 시각.
- `endAt`: 일정 종료 시각. 음성 초안의 기본 기간은 60분이며 확인
  시트에서 사용자가 변경할 수 있습니다.
- `timezone`: 기본값 `Asia/Seoul`.
- `source`: `manual` 또는 `voice`.
- `details`: 선택 입력 상세 내용/메모. 최대 2,000자.
- `transcript`: 음성으로 만든 일정의 원본 음성 명령 transcript.
- `status`: 현재는 `active`.
- `createdAt`, `updatedAt`.
- 클라이언트 read는 본인 일정만 허용하고, client create/update/delete는
  금지합니다. 모든 쓰기는 Cloud Functions를 통해 수행합니다.

`users/{uid}/friends/{friendUid}`

- `uid`: 친구 사용자 ID. `{friendUid}`와 같습니다.
- `displayName`: 친구 선택 화면에서 사용할 캐시된 표시 이름.
- `handle`: 캐시된 친구 아이디.
- `defaultSendMode`: 표시 호환성을 위해 보관하는 기본 전송 모드.
- `photoUrl`: 선택 캐시 프로필 이미지.
- `addedAt`, `updatedAt`.
- 클라이언트 read는 본인 친구 목록만 허용하고, client write는 금지합니다.
  친구 추가는 `addFriendByHandle` Cloud Function을 통해 수행합니다.

`handles/{handle}`

- `uid`: 핸들 소유 사용자 ID.
- `updatedAt`.

`rooms/{roomId}`

- `type`: `direct` 또는 `group`.
- `participantIds`: 방을 읽을 수 있는 사용자 ID 목록.
- `title`: 표시용 방 이름.
- `audioRetentionDays`: 방 단위 음성파일 보존일, 기본값 `1`.
- `audioRetentionPreset`: `oneDay`, `sevenDays`, `custom`.
- `lastMessage`: `{ kind, preview, senderId, createdAt }`.
- `createdAt`, `updatedAt`.

`rooms/{roomId}/messages/{messageId}`

- `senderId`.
- `kind`: `text`, `voice`, `image`, `file`, `location`.
- `text`: 최종 표시 텍스트.
- `transcript`: 원본 STT 결과.
- `audioPath`: Firebase Storage 경로.
- `audioHash`: 중복 STT 캐싱에 사용하는 SHA-256 해시.
- `audioExpiresAt`: 음성파일 삭제 예정 시각.
- `audioDeletedAt`: 음성파일 삭제 완료 시각.
- `audioRetentionDays`: 메시지 생성 시 적용된 보존일.
- `audioRetentionStatus`: `active`, `deleted`, `none`.
- `durationMs`.
- `sttStatus`: `none`, `processing`, `completed`, `failed`.
- `sttCacheHit`: transcript가 캐시에서 왔는지 여부.
- `sendMode`: `confirm` 또는 `instant`.
- `senderDeleted`: 발신자 계정은 삭제되었지만 대화 이력은 보존되는 경우 `true`.
- `createdAt`, `updatedAt`, `editedAt`.

`transcriptionDrafts/{draftId}`

- `ownerId`.
- `audioPath`.
- `language`.
- `durationMs`.
- `status`.
- `transcript`.
- `manualTranscript`: STT 실패 후 사용자가 직접 입력한 transcript인지 여부.
- `audioHash`, `audioExpiresAt`, `audioDeletedAt`, `audioRetentionStatus`.
- `errorCode`.
- `createdAt`, `updatedAt`.

`usageDaily/{uid}_{yyyy-mm-dd}`

- `uid`, `date`, `timezone`.
- `textCount`, `voiceCount`, `voiceMs`.
- `limitMode`: 현재 `unlimited`; `textLimit`와 `voiceLimit`는 `null`로 저장.
- `createdAt`, `updatedAt`.

`reports/{reportId}`

- `reporterId`.
- `targetType`: `message` 또는 `room`.
- `targetId`, `roomId`, `messageId`.
- `reason`, `details`.
- `status`: `open`, `reviewing`, `actioned`, `dismissed`.
- `count`: 같은 신고자가 같은 대상을 반복 신고한 횟수.
- `createdAt`, `updatedAt`.

`blocks/{uid}/users/{blockedUid}`

- `blockedAt`.
- `reason`.

`actionCooldowns/{uid}_{action}`

- `uid`, `action`.
- `lastAt`: 민감 액션의 마지막 실행 시각.
- 초대, 신고, 차단 악용 방지에만 사용합니다. 정상 텍스트 수, 음성 수, 음성
  길이는 제한하지 않습니다.

`transcriptionCache/{language}_{audioHash}`

- `audioHash`, `language`, `model`.
- `transcript`.
- `hitCount`, `createdAt`, `lastUsedAt`.

## Storage

- `voice_drafts/{uid}/{draftId}.m4a`: 메시지 STT 또는 캘린더 의도 파싱을
  기다리는 임시 음성파일.
- `voice_messages/{roomId}/{messageId}.m4a`: 전송된 음성 메시지 파일.

## 백엔드 계약

모바일 앱은 음성파일을 Storage에 업로드한 뒤 Cloud Functions를 호출합니다. 메시지 문서는 Cloud Functions만 생성하므로 참가자 권한, transcript 상태, 알림, 사용량 모니터링, 음성 보존기간을 서버에서 중앙 관리합니다.

친구 추가는 `addFriendByHandle`을 통해 `users/{uid}/friends/{friendUid}`에
저장합니다. 채팅방 생성은 계속 participant handle을 사용하지만, 모바일
친구 선택기는 저장된 친구가 있으면 친구 목록을 우선 표시하고 검색/탐색이
필요하면 사용자 디렉터리로 보완합니다.

캘린더 일정은 채팅 메시지와 분리해 `users/{uid}/calendarEvents/{eventId}`에
저장합니다. 음성 일정 명령은 `createCalendarIntentDraft`에서 STT와 파싱을
수행하고, 사용자가 확인/수정한 뒤 `createCalendarEvent`로 저장합니다.
사용자는 제목, 상세 내용, 날짜, 시간, 기간을 수정할 수 있으며 수정과 hard
delete도 Functions를 통해서만 처리합니다.
국가별 공휴일은 사용자 문서의 `holidayCountryCode`를 기준으로 앱에서
표시하는 오버레이이며, 개인 일정 문서에는 저장하지 않습니다.
## 채팅방 일정 제안/투표

`rooms/{roomId}/calendarProposals/{proposalId}`

- `roomId`, `messageId`: 채팅방 일정 제안 카드 메시지와 제안 문서를 연결합니다.
- `createdBy`: 제안 생성 사용자 ID.
- `title`: 1-120자의 일정 제목.
- `details`: 선택 입력 상세 내용, 최대 2,000자.
- `timezone`: 기본값 `Asia/Seoul`.
- `status`: `open`, `finalized`, `cancelled`.
- `candidates`: 후보 시간 1-5개. 채팅 composer에서 새로 만드는 제안은 2개 이상을 요구하고, 캘린더에서 채팅방으로 공유하는 경우 단일 후보를 허용합니다.
- `votes`: `{ uid: [candidateId] }` 형태의 복수 선택 투표 맵.
- `finalCandidateId`: 제안자 또는 방 관리자가 최종 확정한 후보 ID.
- `source`, `transcript`: 수동/음성 초안 여부와 원문 transcript.
- `createdAt`, `updatedAt`.

`rooms/{roomId}/calendarProposals/{proposalId}/votes/{uid}`

- `uid`.
- `candidateIds`: 사용자가 선택한 후보 ID 목록.
- `updatedAt`.
- 클라이언트는 방 참여자일 때만 읽을 수 있고, 직접 create/update/delete는 금지됩니다. 제안 생성, 투표, 확정, 내 일정 추가, 취소는 모두 Cloud Functions를 통해서만 수행합니다.

확정된 일정 제안은 `users/{uid}/calendarEvents/{eventId}`에 `source: chatProposal`로 저장됩니다. 이때 `roomId`, `proposalId`, `messageId`, `candidateId`를 함께 저장해 채팅방 카드와 개인 앱 내부 캘린더 일정을 연결합니다.
