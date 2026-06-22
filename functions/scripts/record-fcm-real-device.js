const {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  runRecorder,
} = require("./record-launch-shortcut-utils");

const testedAt = optionalFlag("tested-at", "now");
const tester = optionalFlag("tester", process.env.USERNAME || process.env.USER || "Tester");
const artifact = optionalFlag("artifact", "artifacts/fcm-real-device-latest.json");
const device = optionalFlag("device");
const notes = optionalFlag("notes");

console.log("Recording real-device FCM delivery evidence...");
const args = [
  "fcm",
  "--tested-at",
  testedAt,
  "--tester",
  tester,
  "--artifact",
  artifact,
  "--foreground",
  "--background",
  "--terminated",
  "--lock-screen",
];
addOptionalFlag(args, "device", device);
addOptionalFlag(args, "notes", notes);
runRecorder(args);
refreshLaunchArtifacts();
console.log("Done. Keep public exposure blocked until every launch gate is closed.");
