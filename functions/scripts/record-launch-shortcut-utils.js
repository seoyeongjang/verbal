const childProcess = require("node:child_process");
const path = require("node:path");

const scriptDir = __dirname;
const repoRoot = path.resolve(scriptDir, "..", "..");
const functionsDir = path.join(repoRoot, "functions");

function flagValue(name) {
  const key = `--${name}`;
  const index = process.argv.indexOf(key);
  if (index === -1) {
    return "";
  }
  return process.argv[index + 1] || "";
}

function requireFlag(name) {
  const value = flagValue(name).trim();
  if (!value) {
    console.error(`Missing required flag --${name}`);
    process.exit(1);
  }
  return value;
}

function optionalFlag(name, fallback = "") {
  return flagValue(name).trim() || fallback;
}

function addOptionalFlag(args, name, value) {
  if (value) {
    args.push(`--${name}`, value);
  }
}

function runRecorder(recordArgs) {
  runNode([path.join(scriptDir, "record-launch-evidence.js"), ...recordArgs]);
}

function refreshLaunchArtifacts() {
  console.log("Refreshing launch gate artifacts...");
  runNpm(["run", "report:launch-gate"]);
  runNpm(["run", "status:launch"]);
  runNpm(["run", "guide:next-launch-step"]);
  runNpm(["run", "prepare:launch-handoff"]);
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

module.exports = {
  addOptionalFlag,
  optionalFlag,
  refreshLaunchArtifacts,
  requireFlag,
  runRecorder,
};
