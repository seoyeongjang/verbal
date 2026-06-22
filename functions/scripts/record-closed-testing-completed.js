const {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  requireFlag,
  runRecorder,
} = require("./record-launch-shortcut-utils");

const startedAt = requireFlag("started-at");
const endedAt = requireFlag("ended-at");
const testerCount = requireFlag("tester-count");
const continuousDays = requireFlag("continuous-days");
const notes = optionalFlag("notes");

console.log("Recording Google Play closed testing completion evidence...");
const args = [
  "closed-testing-completed",
  "--started-at",
  startedAt,
  "--ended-at",
  endedAt,
  "--tester-count",
  testerCount,
  "--continuous-days",
  continuousDays,
  "--confirm-feedback-reviewed",
  "--confirm-production-access-ready",
];
addOptionalFlag(args, "notes", notes);
runRecorder(args);
refreshLaunchArtifacts();
console.log("Done. Keep public exposure blocked until every launch gate is closed.");
