# Analytics 이벤트 분류

원문: `docs/ANALYTICS_EVENT_TAXONOMY.md`

## 퍼널 이벤트

- `auth_phone_started`
- `auth_phone_verified`
- `profile_saved`
- `room_created`
- `message_text_sent`
- `message_voice_recorded`
- `message_voice_stt_completed`
- `message_voice_stt_failed`
- `message_voice_sent`
- `attachment_sent`
- `invite_created`
- `invite_joined`
- `report_submitted`
- `account_data_exported`
- `account_deleted`

## 비용 이벤트

- `usage_text_incremented`
- `usage_voice_incremented`
- `stt_cache_hit`
- `stt_cache_miss`
- `audio_retention_expired`

## 품질 이벤트

- `stt_manual_recovery_used`
- `stt_retry_used`
- `send_failed`
- `upload_failed`
- `push_token_registered`

## Crashlytics 키

- `uid_hash`
- `room_type`
- `send_mode`
- `stt_mode`
- `app_backend_mode`
- `platform`

첫 베타에서 crash reporting이 필요하다면 릴리즈 빌드 전 Firebase
Analytics/Crashlytics 런타임 패키지 연결을 추가해야 합니다.
