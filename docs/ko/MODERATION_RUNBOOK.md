# 모더레이션 운영 Runbook

원문: `docs/MODERATION_RUNBOOK.md`

## 범위

이 문서는 `reportMessage`, `reportRoom`으로 접수되는 신고 처리를 다룹니다.
신고는 `reports/{reportId}`에 저장되며 신고자와 대상 기준으로 중복 누적됩니다.
정상적인 메시지/음성 사용량은 제한하지 않습니다.

## 신고 필드

- `reporterId`
- `targetType`: `message` 또는 `room`
- `targetId`
- `roomId`
- 메시지 신고의 `messageId`
- `reason`: `spam`, `abuse`, `unsafe`, `other`
- `details`
- `status`: `open`, `reviewing`, `actioned`, `dismissed`
- `count`
- `createdAt`, `updatedAt`

## 검토 흐름

- 클로즈드 베타 중 open 신고를 매일 확인합니다.
- `unsafe`, 반복 `abuse`, 다수 신고자가 있는 방을 우선 처리합니다.
- 판단에 필요한 최소한의 방/메시지 맥락만 확인합니다.
- 운영자가 검토를 시작하면 `reviewing`으로 변경합니다.
- 차단, 경고, 방 제거, 에스컬레이션 후 `actioned`로 변경합니다.
- 정책 위반이 없을 때만 `dismissed`로 변경합니다.

## 조치

- 메시지 문제: 발신자 삭제 요청, 추후 admin tooling으로 제거, 중대한 경우 증거
  보존.
- 방 문제: 초대 링크 폐기, 초대 승인 필수화, 멤버 제거, 방 폐쇄.
- 사용자 문제: 계정 차단, 전화번호 로그인 비활성화, 법무/안전 에스컬레이션.

## 악용 방지

- 초대 생성, 초대 참여, 신고, 차단 액션에는 cooldown을 둡니다.
- 제품 정책상 텍스트 수, 음성 수, 음성 길이는 제한하지 않습니다.
- 공개 런칭 전 provider quota, 예산 알림, 이상 사용량 모니터링으로 비용과 악용
  리스크를 제어해야 합니다.
