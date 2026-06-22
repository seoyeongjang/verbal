const {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  requireFlag,
  runRecorder,
} = require("./record-launch-shortcut-utils");

const reviewedAt = optionalFlag("reviewed-at", "now");
const reportUrl = requireFlag("report-url");
const notes = optionalFlag("notes");

console.log("Recording Google Play Pre-launch report review evidence...");
const args = [
  "prelaunch-reviewed",
  "--reviewed-at",
  reviewedAt,
  "--report-url",
  reportUrl,
  "--confirm-stability",
  "--confirm-performance",
  "--confirm-accessibility",
  "--confirm-screenshots",
  "--confirm-no-blocking-issues",
];
addOptionalFlag(args, "notes", notes);
runRecorder(args);
refreshLaunchArtifacts();
console.log("Done. Keep public exposure blocked until every launch gate is closed.");
