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
- `global_search_used`
- `suspicious_link_warning_shown`

## Crashlytics Keys

- `uid_hash`
- `room_type`
- `send_mode`
- `stt_mode`
- `app_backend_mode`
- `platform`

Runtime Firebase Analytics/Crashlytics package wiring is now present in the
Flutter Firebase mode. Release validation still needs dashboard verification for
event ingestion, Crashlytics crash grouping, and non-debug collection settings.
