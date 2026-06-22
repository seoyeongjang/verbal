const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const functionsDir = path.join(repoRoot, "functions");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `preinternal-release-check-${runId}.json`);
const latestPath = path.join(artifactDir, "preinternal-release-check-latest.json");

const steps = [
  ["functions_build", "npm", ["run", "build"]],
  ["prepare_play_store_assets", "npm", ["run", "prepare:play-store-assets"]],
  ["verify_android_release", "npm", ["run", "verify:android-release"]],
  ["verify_hosted_policy_urls", "npm", ["run", "verify:hosted-policy-urls"]],
  ["prepare_app_content_answers", "npm", ["run", "prepare:app-content-answers"]],
  ["prepare_app_content_copy_sheet", "npm", ["run", "prepare:app-content-copy-sheet"]],
  ["verify_launch_readiness", "npm", ["run", "verify:launch-readiness"]],
  ["prepare_play_console_pack", "npm", ["run", "prepare:play-console-pack"]],
  ["prepare_closed_testing_pack", "npm", ["run", "prepare:closed-testing-pack"]],
  ["prepare_launch_evidence_template", "npm", ["run", "prepare:launch-evidence"]],
  [
    "verify_launch_evidence_shape",
    "npm",
    ["run", "verify:launch-evidence", "--", "--allow-missing"],
  ],
  ["report_launch_gate", "npm", ["run", "report:launch-gate"]],
  ["prepare_launch_handoff", "npm", ["run", "prepare:launch-handoff"]],
  ["verify_launch_consistency", "npm", ["run", "verify:launch-consistency"]],
  ["generate_launch_status", "npm", ["run", "status:launch"]],
  ["generate_next_external_step_guide", "npm", ["run", "guide:next-launch-step"]],
];

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const results = [];
  let failed = false;

  for (const [name, command, args] of steps) {
    if (failed) {
      results.push({name, skipped: true, ok: false});
      continue;
    }
    const result = runStep(name, command, args);
    results.push(result);
    failed = !result.ok;
  }

  const launchGate = readJsonIfExists(path.join(artifactDir, "launch-gate-latest.json"));
  const latestReadiness = latestArtifact("launch-readiness-*.json");
  const latestPlayPack = latestArtifactIn("play-console", "verbal-play-console-pack-*.md");
  const latestAppContentCopySheet = existingArtifact(
    "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
  );
  const latestClosedTestingPack = latestArtifactIn(
    path.join("play-console", "closed-testing"),
    "verbal-closed-testing-pack-*.md",
  );
  const latestLaunchHandoff = existingArtifact("artifacts/launch-handoff-latest.md");
  const latestLaunchConsistency = existingArtifact("artifacts/launch-consistency-latest.json");
  const latestLaunchStatus = existingArtifact("artifacts/launch-status-latest.md");
  const latestNextStepGuide = existingArtifact("artifacts/next-external-step-latest.md");
  const latestHostedPolicyUrls = existingArtifact("artifacts/hosted-policy-url-verification-latest.md");
  const readyForInternalTestingUpload = Boolean(
    !failed && launchGate?.readyForInternalTestingUpload,
  );
  const readyForPublicUserExposure = Boolean(launchGate?.readyForPublicUserExposure);
  const blockers = Array.isArray(launchGate?.blockers)
    ? launchGate.blockers.map((item) => item.name)
    : [];
  const report = {
    ok: readyForInternalTestingUpload,
    checkedAt: new Date().toISOString(),
    purpose:
      "Verify all local gates required before Google Play Internal testing upload. This does not publish or upload the app.",
    readyForInternalTestingUpload,
    readyForPublicUserExposure,
    publicExposureBlockedAsExpected: !readyForPublicUserExposure,
    steps: results,
    artifacts: {
      launchGate: fs.existsSync(path.join(artifactDir, "launch-gate-latest.json"))
        ? "artifacts/launch-gate-latest.json"
        : "",
      launchReadiness: latestReadiness,
      playConsolePack: latestPlayPack,
      appContentCopySheet: latestAppContentCopySheet,
      closedTestingPack: latestClosedTestingPack,
      launchHandoff: latestLaunchHandoff,
      launchConsistency: latestLaunchConsistency,
      launchStatus: latestLaunchStatus,
      nextExternalStepGuide: latestNextStepGuide,
      hostedPolicyUrls: latestHostedPolicyUrls,
      manualEvidenceTemplate: fs.existsSync(
        path.join(artifactDir, "launch-manual-evidence.template.json"),
      )
        ? "artifacts/launch-manual-evidence.template.json"
        : "",
    },
    remainingExternalBlockers: blockers,
    nextActions: readyForInternalTestingUpload
      ? buildNextActions(blockers)
      : [
          "Fix the failed local step above before Play Console work.",
          "Rerun npm run verify:preinternal.",
        ],
    artifact: path.relative(repoRoot, jsonPath),
  };

  writeJson(jsonPath, report);
  writeJson(latestPath, report);
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = report.ok ? 0 : 1;
}

function buildNextActions(blockers) {
  const actions = [];
  const blocked = new Set(blockers);
  if (blocked.has("play_console_app_created")) {
    actions.push("Create the Google Play Console app record.");
  }
  if (blocked.has("play_internal_testing_uploaded")) {
    actions.push("Upload dist/android/app-release.aab to Internal testing.");
  }
  if (blocked.has("play_data_safety_submitted")) {
    actions.push("Complete App content and Data Safety forms.");
  }
  if (blocked.has("play_prelaunch_report_reviewed")) {
    actions.push("Review the Google Play Pre-launch report after it is generated.");
  }
  if (blocked.has("play_closed_testing_completed")) {
    actions.push(
      "Use the generated closed testing pack if Play Console requires production access testing.",
    );
  }
  if (blocked.has("android_real_device_e2e_verified")) {
    actions.push("Run Android real-device E2E QA.");
  }
  if (blocked.has("fcm_real_device_delivery_verified")) {
    actions.push("Run FCM foreground/background/terminated/lock-screen QA.");
  }
  actions.push(
    "Use artifacts/launch-handoff-latest.md as the step-by-step external handoff.",
    "Use artifacts/launch-status-latest.md as the concise current next-step dashboard.",
    "Use artifacts/next-external-step-latest.md as the exact next external task guide.",
    "Keep artifacts/launch-consistency-latest.json passing before any Play Console upload.",
    "Record completed evidence with npm run record:launch-evidence -- <command>.",
    "Run npm run verify:launch-evidence and npm run report:launch-gate.",
  );
  return actions;
}

function runStep(name, command, args) {
  const startedAt = new Date();
  const resolved = resolveCommand(command, args);
  const result = childProcess.spawnSync(resolved.command, resolved.args, {
    cwd: functionsDir,
    encoding: "utf8",
  });
  return {
    name,
    ok: result.status === 0,
    exitCode: result.status,
    startedAt: startedAt.toISOString(),
    durationMs: Date.now() - startedAt.getTime(),
    error: result.error ? String(result.error.message || result.error) : "",
    stdoutTail: tail(result.stdout || ""),
    stderrTail: tail(result.stderr || ""),
  };
}

function resolveCommand(command, args) {
  if (command === "npm" && process.env.npm_execpath) {
    return {
      command: process.execPath,
      args: [process.env.npm_execpath, ...args],
    };
  }
  if (process.platform === "win32" && command === "npm") {
    return {command: "npm.cmd", args};
  }
  return {command, args};
}

function tail(value) {
  const lines = value
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter(Boolean);
  return lines.slice(-20);
}

function latestArtifact(pattern) {
  return latestArtifactIn("", pattern);
}

function latestArtifactIn(subdir, pattern) {
  const [prefix, suffix] = pattern.split("*");
  const dir = path.join(artifactDir, subdir);
  if (!fs.existsSync(dir)) {
    return "";
  }
  const matches = fs
    .readdirSync(dir, {withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => name.startsWith(prefix) && name.endsWith(suffix))
    .filter((name) => !name.includes("-latest."))
    .map((name) => {
      const fullPath = path.join(dir, name);
      return {name, mtimeMs: fs.statSync(fullPath).mtimeMs};
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return matches[0]
    ? path.relative(repoRoot, path.join(dir, matches[0].name)).replace(/\\/g, "/")
    : "";
}

function existingArtifact(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath)) ? relativePath : "";
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
