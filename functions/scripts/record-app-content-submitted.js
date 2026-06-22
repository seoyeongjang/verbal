const childProcess = require("node:child_process");
const path = require("node:path");

const scriptDir = __dirname;
const repoRoot = path.resolve(scriptDir, "..", "..");
const functionsDir = path.join(repoRoot, "functions");

const submittedAt = flagValue("submitted-at") || "now";
const notes = flagValue("notes");

const recordArgs = [
  path.join(scriptDir, "record-launch-evidence.js"),
  "app-content-submitted",
  "--submitted-at",
  submittedAt,
  "--confirm-privacy-policy",
  "--confirm-app-access",
  "--confirm-ads",
  "--confirm-data-safety",
  "--confirm-account-deletion",
  "--confirm-data-deletion",
  "--confirm-content-rating",
  "--confirm-target-audience",
  "--confirm-sensitive-permissions",
  "--confirm-ugc",
  "--confirm-government-app",
  "--confirm-financial-features",
  "--confirm-health",
  "--confirm-app-category-contact",
  "--confirm-store-listing",
];

if (notes) {
  recordArgs.push("--notes", notes);
}

main();

function main() {
  console.log("Recording Play Console App content/Data Safety evidence...");
  runNode(recordArgs);

  console.log("Refreshing launch gate artifacts...");
  runNpm(["run", "report:launch-gate"]);
  runNpm(["run", "status:launch"]);
  runNpm(["run", "guide:next-launch-step"]);
  runNpm(["run", "prepare:launch-handoff"]);

  console.log("Done. Run `npm run verify:public-release` after the remaining external evidence is recorded.");
}

function flagValue(name) {
  const key = `--${name}`;
  const index = process.argv.indexOf(key);
  if (index === -1) {
    return "";
  }
  return process.argv[index + 1] || "";
}

function runNode(args) {
  const result = childProcess.spawnSync(process.execPath, args, {
    cwd: functionsDir,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

function runNpm(args) {
  const command = process.env.npm_execpath ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
  const commandArgs = process.env.npm_execpath ? [process.env.npm_execpath, ...args] : args;
  const result = childProcess.spawnSync(command, commandArgs, {
    cwd: functionsDir,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}
