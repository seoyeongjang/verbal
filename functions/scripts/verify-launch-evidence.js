const fs = require("node:fs");
const path = require("node:path");
const {
  buildLaunchEvidenceChecks,
} = require("./launch-evidence-utils");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const outputPath = path.join(artifactDir, `launch-evidence-verification-${runId}.json`);
const latestPath = path.join(artifactDir, "launch-evidence-verification-latest.json");
const allowMissing = process.argv.includes("--allow-missing");

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const evidencePath = path.join(artifactDir, "launch-manual-evidence.json");
  const evidence = readJsonIfExists(evidencePath);
  const androidRelease = readLatestJson("android-release-verification-*.json")?.data;
  const {checks, gates} = buildLaunchEvidenceChecks({
    evidence,
    androidRelease,
    repoRoot,
  });
  const missingEvidence = !evidence;
  const failed = checks.filter((check) => !check.ok);
  const allowIncompleteExternalEvidence = allowMissing && failed.length > 0;
  const ok = allowMissing ? true : failed.length === 0;
  const result = {
    ok,
    skipped: allowMissing && missingEvidence,
    allowIncompleteExternalEvidence,
    checkedAt: new Date().toISOString(),
    evidenceFile: fs.existsSync(evidencePath)
      ? "artifacts/launch-manual-evidence.json"
      : "",
    androidReleaseArtifact: latestArtifact(artifactDir, "android-release-verification-*.json"),
    failedCount: ok ? 0 : failed.length,
    passedCount: ok && allowMissing
      ? 0
      : checks.length - failed.length,
    gates,
    failed: ok ? [] : failed,
    checks,
    nextActions: nextActions(gates, missingEvidence),
    artifact: path.relative(repoRoot, outputPath),
  };
  writeJson(outputPath, result);
  writeJson(latestPath, result);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}

function nextActions(gates, missingEvidence) {
  if (missingEvidence) {
    return [
      "Run npm run prepare:launch-evidence.",
      "Run npm run record:launch-evidence -- init.",
      "Record only completed external evidence with npm run record:launch-evidence -- <command>.",
    ];
  }
  const actions = [];
  if (!gates.playAppCreated.ok) {
    actions.push(
      "After creating the Play Console app record, run npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>.",
    );
  }
  if (!gates.internalTestingUpload.ok) {
    actions.push(
      "After uploading the AAB to Internal testing, run npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>.",
    );
  }
  if (!gates.appContentSubmitted.ok) {
    actions.push(
    "After saving App content and Data Safety forms, run npm run record:app-content-submitted.",
    );
  }
  if (!gates.preLaunchReportReviewed.ok) {
    actions.push(
      "After Google Play Pre-launch report is generated and reviewed, run npm run record:prelaunch-reviewed -- --report-url <https-url>.",
    );
  }
  if (!gates.closedTestingCompleted.ok) {
    actions.push(
      "After closed testing is complete, run npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>, or run npm run record:closed-testing-not-required -- --reason <reason> if Play Console confirms it is not required.",
    );
  }
  if (!gates.realDeviceE2e.ok) {
    actions.push(
      "After real-device QA, run npm run record:real-device-e2e -- --tester <name>.",
    );
  }
  if (!gates.fcm.ok) {
    actions.push(
      "After FCM foreground/background/terminated/lock-screen verification, run npm run record:fcm-real-device -- --tester <name>.",
    );
  }
  return actions;
}

function readLatestJson(pattern) {
  const file = latestArtifact(artifactDir, pattern);
  if (!file) {
    return null;
  }
  return {
    path: file,
    data: readJsonIfExists(path.join(repoRoot, file)),
  };
}

function latestArtifact(dir, pattern) {
  const [prefix, suffix] = pattern.split("*");
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

function readJsonIfExists(filePath) {
  try {
    const text = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
