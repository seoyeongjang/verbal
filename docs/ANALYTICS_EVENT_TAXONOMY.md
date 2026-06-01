# Analytics Event Taxonomy

Korean translation: `docs/ko/ANALYTICS_EVENT_TAXONOMY.md`

## Funnel Events

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

## Cost Events

- `usage_text_incremented`
- `usage_voice_incremented`
- `stt_cache_hit`
- `stt_cache_miss`
- `audio_retention_expired`

## Quality Events

- `stt_manual_recovery_used`
- `stt_retry_used`
- `send_failed`
- `upload_failed`
- `push_token_registered`

## Crashlytics Keys

- `uid_hash`
- `room_type`
- `send_mode`
- `stt_mode`
- `app_backend_mode`
- `platform`

Runtime Firebase Analytics/Crashlytics package wiring still needs to be added
before a release build if crash reporting is required in the first beta.
