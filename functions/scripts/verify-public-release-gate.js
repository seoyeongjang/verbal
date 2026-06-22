const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const functionsDir = path.join(repoRoot, "functions");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const outputPath = path.join(artifactDir, `public-release-gate-${runId}.json`);
const latestPath = path.join(artifactDir, "public-release-gate-latest.json");

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});

  const evidenceResult = runNpm("verify:launch-evidence", []);
  const gateResult = runNpm("report:launch-gate", []);
  const gate = readJsonIfExists(path.join(artifactDir, "launch-gate-latest.json"));
  const evidence = readJsonIfExists(
    path.join(artifactDir, "launch-evidence-verification-latest.json"),
  );
  const blockers = Array.isArray(gate?.blockers)
    ? gate.blockers.map((item) => item.name)
    : ["launch_gate_missing"];
  const ok = Boolean(
    evidenceResult.ok &&
      gateResult.ok &&
      evidence?.ok &&
      gate?.readyForPublicUserExposure &&
      blockers.length === 0,
  );
  const result = {
    ok,
    checkedAt: new Date().toISOString(),
    purpose:
      "Hard gate for Google Play production/public user exposure. This command must pass before production rollout.",
    readyForInternalTestingUpload: Boolean(gate?.readyForInternalTestingUpload),
    readyForPublicUserExposure: Boolean(gate?.readyForPublicUserExposure),
    blockers,
    evidenceVerification: {
      ok: Boolean(evidenceResult.ok && evidence?.ok),
      artifact: evidence?.artifact || "artifacts/launch-evidence-verification-latest.json",
      command: "npm run verify:launch-evidence",
      exitCode: evidenceResult.exitCode,
      error: evidenceResult.error,
    },
    launchGate: {
      ok: Boolean(gateResult.ok && gate?.ok),
      artifact: "artifacts/launch-gate-latest.json",
      command: "npm run report:launch-gate",
      exitCode: gateResult.exitCode,
      error: gateResult.error,
    },
    nextActions: ok ? [] : buildNextActions(blockers),
    artifact: path.relative(repoRoot, outputPath),
  };

  writeJson(outputPath, result);
  writeJson(latestPath, result);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = ok ? 0 : 1;
}

function buildNextActions(blockers) {
  if (blockers.length === 0) {
    return [
      "Inspect artifacts/launch-gate-latest.json and artifacts/launch-evidence-verification-latest.json.",
    ];
  }
  const actions = [];
  const priority = [
    "play_console_app_created",
    "play_internal_testing_uploaded",
    "play_data_safety_submitted",
    "play_prelaunch_report_reviewed",
    "play_closed_testing_completed",
    "android_real_device_e2e_verified",
    "fcm_real_device_delivery_verified",
  ];
  const byBlocker = {
    play_console_app_created:
      "Create the Play Console app record, then record play-app-created evidence.",
    play_internal_testing_uploaded:
      "Upload dist/android/app-release.aab to Internal testing, then record internal-testing-upload evidence.",
    play_data_safety_submitted:
      "Complete Play Console App content and Data Safety forms, then record app-content-submitted evidence.",
    play_prelaunch_report_reviewed:
      "Review the Google Play Pre-launch report, then record prelaunch-reviewed evidence.",
    play_closed_testing_completed:
      "Complete closed testing or record the non-required reason, then record closed-testing-completed evidence.",
    android_real_device_e2e_verified:
      "Run scripts/run-android-real-device-qa.ps1 -Interactive on a real device, then record real-device-e2e evidence.",
    fcm_real_device_delivery_verified:
      "Run scripts/run-fcm-real-device-qa.ps1 on a real device, then record fcm evidence.",
  };
  const orderedBlockers = [...blockers].sort((a, b) => {
    const ai = priority.includes(a) ? priority.indexOf(a) : Number.MAX_SAFE_INTEGER;
    const bi = priority.includes(b) ? priority.indexOf(b) : Number.MAX_SAFE_INTEGER;
    return ai - bi;
  });
  for (const blocker of orderedBlockers) {
    actions.push(byBlocker[blocker] || `Resolve launch blocker: ${blocker}.`);
  }
  actions.push("Rerun npm run verify:public-release after all evidence is recorded.");
  return actions;
}

function runNpm(script, args) {
  const resolved = resolveNpmCommand(["run", script, ...args]);
  const result = childProcess.spawnSync(resolved.command, resolved.args, {
    cwd: functionsDir,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    exitCode: result.status,
    error: result.error ? String(result.error.message || result.error) : "",
    stdoutTail: tail(result.stdout || ""),
    stderrTail: tail(result.stderr || ""),
  };
}

function resolveNpmCommand(args) {
  if (process.env.npm_execpath) {
    return {
      command: process.execPath,
      args: [process.env.npm_execpath, ...args],
    };
  }
  if (process.platform === "win32") {
    return {command: "npm.cmd", args};
  }
  return {command: "npm", args};
}

function tail(value) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .slice(-20);
}

function readJsonIfExists(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
  } catch {
    return null;
  }
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
