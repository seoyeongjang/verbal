const {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  requireFlag,
  runRecorder,
} = require("./record-launch-shortcut-utils");

const reason = requireFlag("reason");
const notes = optionalFlag("notes");

console.log("Recording Google Play closed testing non-required evidence...");
const args = [
  "closed-testing-completed",
  "--not-required",
  "--reason",
  reason,
];
addOptionalFlag(args, "notes", notes);
runRecorder(args);
refreshLaunchArtifacts();
console.log("Done. Keep public exposure blocked until every launch gate is closed.");
