const {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  runRecorder,
} = require("./record-launch-shortcut-utils");

const testedAt = optionalFlag("tested-at", "now");
const tester = optionalFlag("tester", process.env.USERNAME || process.env.USER || "Tester");
const artifact = optionalFlag("artifact", "artifacts/android-real-device-qa-latest.json");
const deviceModel = optionalFlag("device-model");
const notes = optionalFlag("notes");

console.log("Recording Android real-device E2E evidence...");
const args = [
  "real-device-e2e",
  "--tested-at",
  testedAt,
  "--tester",
  tester,
  "--artifact",
  artifact,
];
addOptionalFlag(args, "device-model", deviceModel);
addOptionalFlag(args, "notes", notes);
runRecorder(args);
refreshLaunchArtifacts();
console.log("Done. Keep public exposure blocked until every launch gate is closed.");
