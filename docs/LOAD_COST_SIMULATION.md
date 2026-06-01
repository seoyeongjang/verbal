# Load and Cost Simulation

Korean translation: `docs/ko/LOAD_COST_SIMULATION.md`

## Current Policy

- Normal text usage: unlimited.
- Normal voice count: unlimited.
- Voice duration: no fixed product-level cap.
- Abuse controls apply only to sensitive actions such as invite creation,
  invite joining, reporting, and blocking.

## Variables to Track

- MAU and DAU.
- Voice messages per DAU.
- Average voice seconds.
- STT success and retry rate.
- STT cache hit rate.
- Audio retention period.
- Audio replay rate.
- Attachment count and average size.
- Firestore reads/writes per active session.

## Formula

Monthly STT minutes:

`DAU * voice_messages_per_DAU * average_voice_seconds * 30 / 60`

Monthly active audio storage:

`DAU * voice_messages_per_DAU * average_audio_size_MB * retention_days`

## Required Before Launch

- Re-run estimates using beta telemetry before opening public traffic.
- Set Firebase/GCP budgets and Deepgram usage alerts.
- Monitor anomaly spikes separately from normal user usage.
