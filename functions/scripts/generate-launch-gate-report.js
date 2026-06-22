const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {
  evaluateManualEvidence,
} = require("./launch-evidence-utils");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `launch-gate-${runId}.json`);
const mdPath = path.join(artifactDir, `launch-gate-${runId}.md`);
const latestJsonPath = path.join(artifactDir, "launch-gate-latest.json");
const latestMdPath = path.join(artifactDir, "launch-gate-latest.md");
const publicExposureGateOrder = [
  "android_release_verified",
  "launch_readiness_verified",
  "play_console_pack_generated",
  "play_console_app_created",
  "play_internal_testing_uploaded",
  "play_data_safety_submitted",
  "play_prelaunch_report_reviewed",
  "play_closed_testing_completed",
  "android_real_device_e2e_verified",
  "fcm_real_device_delivery_verified",
];

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});

  const launchReadiness = readLatestJson("launch-readiness-*.json");
  const androidRelease = readLatestJson("android-release-verification-*.json");
  const realDeviceQa = readJsonIfExists(
    path.join(artifactDir, "android-real-device-qa-latest.json"),
  );
  const manualEvidencePath = path.join(artifactDir, "launch-manual-evidence.json");
  const manualEvidence = readJsonIfExists(manualEvidencePath);
  const playConsolePack = latestArtifact(
    path.join(artifactDir, "play-console"),
    "verbal-play-console-pack-*.md",
  );
  const adb = getAdbState();
  const realDeviceQaIsReal =
    Boolean(realDeviceQa?.ok && realDeviceQa?.deviceId) &&
    !hasCheck(realDeviceQa, "dry_run_completed");
  const evidence = evaluateManualEvidence({
    evidence: manualEvidence,
    androidRelease: androidRelease?.data,
    repoRoot,
  });
  const realDeviceE2eOk = realDeviceQaIsReal || evidence.realDeviceE2e.ok;
  const fcmOk = evidence.fcm.ok;

  const gates = [
    gate(
      "android_release_verified",
      Boolean(androidRelease?.data?.ok),
      "Play upload AAB package identity, Firebase mapping, build parity, and upload-key fingerprint are verified.",
      androidRelease?.path,
    ),
    gate(
      "launch_readiness_verified",
      Boolean(launchReadiness?.data?.ok),
      "Policy pages, store assets, hosted URLs, telemetry wiring, consent gate, and validation scripts are verified.",
      launchReadiness?.path,
    ),
    gate(
      "play_console_pack_generated",
      Boolean(playConsolePack),
      "Copy/paste package for Play Console inputs exists.",
      playConsolePack,
    ),
    gate(
      "play_console_app_created",
      evidence.playAppCreated.ok,
      "The app record must be created in Google Play Console.",
      evidence.playAppCreated.artifact,
      evidence.playAppCreated.ok ? "pass" : "external_required",
    ),
    gate(
      "play_internal_testing_uploaded",
      evidence.internalTestingUpload.ok,
      "dist/android/app-release.aab must be uploaded to the Internal testing track.",
      evidence.internalTestingUpload.artifact,
      evidence.internalTestingUpload.ok ? "pass" : "external_required",
    ),
    gate(
      "play_data_safety_submitted",
      evidence.appContentSubmitted.ok,
      "Data Safety and App content forms must be entered and saved in Play Console.",
      evidence.appContentSubmitted.artifact,
      evidence.appContentSubmitted.ok ? "pass" : "external_required",
    ),
    gate(
      "play_prelaunch_report_reviewed",
      evidence.preLaunchReportReviewed.ok,
      "Google Play Pre-launch report must be reviewed for stability, performance, accessibility, screenshots, and blocking issues.",
      evidence.preLaunchReportReviewed.artifact,
      evidence.preLaunchReportReviewed.ok ? "pass" : "external_required",
    ),
    gate(
      "play_closed_testing_completed",
      evidence.closedTestingCompleted.ok,
      "Closed testing or Play Console non-required evidence must be recorded before public exposure.",
      evidence.closedTestingCompleted.artifact,
      evidence.closedTestingCompleted.ok ? "pass" : "external_required",
    ),
    gate(
      "android_real_device_e2e_verified",
      realDeviceE2eOk,
      "Real Android device QA must be run with a connected device, not DryRun.",
      realDeviceQaIsReal ? "artifacts/android-real-device-qa-latest.json" : evidence.realDeviceE2e.artifact,
      realDeviceE2eOk ? "pass" : "manual_required",
    ),
    gate(
      "fcm_real_device_delivery_verified",
      fcmOk,
      "Foreground, background, terminated, and lock-screen push delivery need real-device evidence.",
      evidence.fcm.artifact,
      fcmOk ? "pass" : "manual_required",
    ),
  ].sort(compareGatePriority);

  const readyForInternalTestingUpload = gates
    .filter((item) =>
      [
        "android_release_verified",
        "launch_readiness_verified",
        "play_console_pack_generated",
      ].includes(item.name),
    )
    .every((item) => item.ok);
  const readyForPublicUserExposure = gates.every((item) => item.ok);
  const blockers = gates.filter((item) => !item.ok).sort(compareGatePriority);

  const report = {
    ok: readyForInternalTestingUpload,
    generatedAt: new Date().toISOString(),
    readyForInternalTestingUpload,
    readyForPublicUserExposure,
    adb,
    manualEvidence: {
      path: fs.existsSync(manualEvidencePath)
        ? "artifacts/launch-manual-evidence.json"
        : "",
      present: Boolean(manualEvidence),
      checks: evidence,
    },
    gates,
    blockers,
    nextActions: buildNextActions(evidence),
    artifacts: {
      launchReadiness: launchReadiness?.path || "",
      androidRelease: androidRelease?.path || "",
      playConsolePack: playConsolePack || "",
      realDeviceQa: realDeviceQa ? "artifacts/android-real-device-qa-latest.json" : "",
      fcmRealDevice: fs.existsSync(path.join(artifactDir, "fcm-real-device-latest.json"))
        ? "artifacts/fcm-real-device-latest.json"
        : "",
      manualEvidence: fs.existsSync(manualEvidencePath)
        ? "artifacts/launch-manual-evidence.json"
        : "",
    },
  };

  writeJson(jsonPath, report);
  writeJson(latestJsonPath, report);
  const markdown = renderMarkdown(report);
  fs.writeFileSync(mdPath, markdown, "utf8");
  fs.writeFileSync(latestMdPath, markdown, "utf8");

  console.log(
    JSON.stringify(
      {
        ok: report.ok,
        readyForInternalTestingUpload,
        readyForPublicUserExposure,
        blockers: blockers.map((item) => item.name),
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
      },
      null,
      2,
    ),
  );
}

function gate(name, ok, detail, artifact = "", status = ok ? "pass" : "fail") {
  return {name, ok: Boolean(ok), status, detail, artifact};
}

function compareGatePriority(a, b) {
  const aName = typeof a === "string" ? a : a.name;
  const bName = typeof b === "string" ? b : b.name;
  const ai = publicExposureGateOrder.includes(aName)
    ? publicExposureGateOrder.indexOf(aName)
    : Number.MAX_SAFE_INTEGER;
  const bi = publicExposureGateOrder.includes(bName)
    ? publicExposureGateOrder.indexOf(bName)
    : Number.MAX_SAFE_INTEGER;
  return ai - bi;
}

function buildNextActions(evidence) {
  const actions = [];
  if (!evidence.playAppCreated.ok) {
    actions.push(
      "Create the Google Play Console app record.",
      "Record app creation with npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>.",
    );
  }
  if (!evidence.internalTestingUpload.ok) {
    actions.push(
      "Upload dist/android/app-release.aab to Internal testing.",
      "Record Internal testing upload with npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>.",
    );
  }
  if (!evidence.appContentSubmitted.ok) {
    actions.push(
      "Complete Play Console Data Safety and App content forms using the generated copy sheet.",
      "Record App content submission with npm run record:app-content-submitted.",
    );
  }
  if (!evidence.preLaunchReportReviewed.ok) {
    actions.push(
      "Review Google Play Pre-launch report after it is generated.",
      "Record Pre-launch report review with npm run record:prelaunch-reviewed -- --report-url <https-url>.",
    );
  }
  if (!evidence.closedTestingCompleted.ok) {
    actions.push(
      "Complete closed testing if required by Play Console, or record why it is not required.",
      "Record closed testing with npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>.",
    );
  }
  if (!evidence.realDeviceE2e.ok) {
    actions.push(
      "Run scripts/run-android-real-device-qa.ps1 -Interactive with a connected Android device.",
      "Record real-device E2E with npm run record:real-device-e2e -- --tester <name>.",
    );
  }
  if (!evidence.fcm.ok) {
    actions.push(
      "Run scripts/run-fcm-real-device-qa.ps1 with a connected Android device.",
      "Record FCM verification with npm run record:fcm-real-device -- --tester <name>.",
    );
  }
  return actions;
}

function readLatestJson(pattern) {
  const file = latestArtifact(artifactDir, pattern);
  if (!file) {
    return null;
  }
  return {path: file, data: readJsonIfExists(path.join(repoRoot, file))};
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

function hasCheck(report, name) {
  return Array.isArray(report?.checks) &&
    report.checks.some((check) => check.name === name && check.ok);
}

function getAdbState() {
  const adbPath = path.join(
    process.env.LOCALAPPDATA || "",
    "Android",
    "Sdk",
    "platform-tools",
    "adb.exe",
  );
  if (!fs.existsSync(adbPath)) {
    return {available: false, path: adbPath, devices: []};
  }
  try {
    const output = childProcess.execFileSync(adbPath, ["devices", "-l"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    const devices = output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => /\sdevice\s/.test(line))
      .map((line) => line.split(/\s+/)[0]);
    return {available: true, path: adbPath, devices, raw: output.trim()};
  } catch (error) {
    return {
      available: true,
      path: adbPath,
      devices: [],
      error: String(error?.message || error),
    };
  }
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function renderMarkdown(report) {
  return `# Verbal Launch Gate Report

Generated: ${report.generatedAt}

## Decision

- Ready for Google Play Internal testing upload: ${report.readyForInternalTestingUpload ? "Yes" : "No"}
- Ready for public user exposure: ${report.readyForPublicUserExposure ? "Yes" : "No"}
- Connected Android devices: ${report.adb.devices.length > 0 ? report.adb.devices.join(", ") : "None"}
- Manual evidence file: ${report.manualEvidence.present ? report.manualEvidence.path : "Not found"}

## Gates

| Gate | Status | Evidence |
|---|---|---|
${report.gates
  .map((item) => `| ${item.name} | ${item.status} | ${item.artifact || item.detail} |`)
  .join("\n")}

## Remaining Blockers

${report.blockers.map((item) => `- ${item.name}: ${item.detail}`).join("\n")}

## Next Actions

${report.nextActions.length > 0 ? report.nextActions.map((item) => `- ${item}`).join("\n") : "- None"}

## Artifacts

- Launch readiness: ${report.artifacts.launchReadiness || "Not found"}
- Android release verification: ${report.artifacts.androidRelease || "Not found"}
- Play Console pack: ${report.artifacts.playConsolePack || "Not found"}
- Android real-device QA: ${report.artifacts.realDeviceQa || "Not found"}
- FCM real-device QA: ${report.artifacts.fcmRealDevice || "Not found"}
- Manual launch evidence: ${report.artifacts.manualEvidence || "Not found"}
`;
}
