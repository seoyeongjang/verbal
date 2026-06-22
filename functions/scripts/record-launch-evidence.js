const fs = require("node:fs");
const path = require("node:path");
const {
  buildLaunchEvidenceChecks,
} = require("./launch-evidence-utils");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const templatePath = path.join(artifactDir, "launch-manual-evidence.template.json");
const evidencePath = path.join(artifactDir, "launch-manual-evidence.json");
const expectedPackageName = "com.voicebeta.verbal";
const command = process.argv[2] || "help";
const flags = parseFlags(process.argv.slice(3));
const remainingGateOrder = [
  "playAppCreated",
  "internalTestingUpload",
  "appContentSubmitted",
  "preLaunchReportReviewed",
  "closedTestingCompleted",
  "realDeviceE2e",
  "fcm",
];

main();

function main() {
  if (command === "help" || flags.help) {
    printHelp();
    return;
  }

  if (command === "status") {
    printStatus();
    return;
  }

  if (command === "init") {
    initEvidence({force: Boolean(flags.force)});
    printStatus();
    return;
  }

  const evidence = loadEvidenceForUpdate();
  const androidRelease = readLatestAndroidRelease();

  if (command === "play-app-created") {
    evidence.playConsole.appCreated = {
      ...evidence.playConsole.appCreated,
      done: true,
      appName: "Verbal",
      packageName: expectedPackageName,
      createdAt: normalizeTimestamp(requiredFlag("created-at")),
      consoleUrl: requireHttpsUrl(requiredFlag("console-url")),
      notes: optionalString("notes"),
    };
  } else if (command === "internal-testing-upload") {
    assertAndroidRelease(androidRelease);
    evidence.playConsole.internalTestingUpload = {
      ...evidence.playConsole.internalTestingUpload,
      done: true,
      track: "internal",
      packageName: expectedPackageName,
      versionCode: String(androidRelease.android.versionCode),
      aabSha256: String(androidRelease.release.sha256 || "").toLowerCase(),
      uploadedAt: normalizeTimestamp(requiredFlag("uploaded-at")),
      releaseName:
        optionalString("release-name") ||
        `Verbal ${String(androidRelease.android.versionName || "").trim()}`,
      testerGroupOrEmails: requiredFlag("tester-group"),
      notes: optionalString("notes"),
    };
  } else if (command === "prelaunch-reviewed") {
    requireAllFlags([
      "confirm-stability",
      "confirm-performance",
      "confirm-accessibility",
      "confirm-screenshots",
      "confirm-no-blocking-issues",
    ]);
    evidence.playConsole.preLaunchReportReviewed = {
      ...evidence.playConsole.preLaunchReportReviewed,
      done: true,
      reviewedAt: normalizeTimestamp(requiredFlag("reviewed-at")),
      reportUrl: requireHttpsUrl(requiredFlag("report-url")),
      completedSections: {
        stability: true,
        performance: true,
        accessibility: true,
        screenshots: true,
      },
      noBlockingIssues: true,
      notes: optionalString("notes"),
    };
  } else if (command === "closed-testing-completed") {
    if (flags["not-required"] === true) {
      evidence.playConsole.closedTestingCompleted = {
        ...evidence.playConsole.closedTestingCompleted,
        done: true,
        requiredByPlayConsole: false,
        notRequiredReason: requiredFlag("reason"),
        productionAccessReady: true,
        notes: optionalString("notes"),
      };
    } else {
      requireAllFlags([
        "confirm-feedback-reviewed",
        "confirm-production-access-ready",
      ]);
      const testerCount = requiredPositiveInteger("tester-count");
      const continuousDays = requiredPositiveInteger("continuous-days");
      if (testerCount < 12) {
        fail("Closed testing evidence requires at least 12 testers unless --not-required is used.");
      }
      if (continuousDays < 14) {
        fail("Closed testing evidence requires at least 14 continuous days unless --not-required is used.");
      }
      evidence.playConsole.closedTestingCompleted = {
        ...evidence.playConsole.closedTestingCompleted,
        done: true,
        requiredByPlayConsole: true,
        startedAt: normalizeTimestamp(requiredFlag("started-at")),
        endedAt: normalizeTimestamp(requiredFlag("ended-at")),
        testerCount,
        continuousDays,
        feedbackReviewed: true,
        productionAccessReady: true,
        notRequiredReason: "",
        notes: optionalString("notes"),
      };
    }
  } else if (command === "app-content-submitted") {
    requireAllFlags([
      "confirm-privacy-policy",
      "confirm-app-access",
      "confirm-ads",
      "confirm-data-safety",
      "confirm-account-deletion",
      "confirm-data-deletion",
      "confirm-content-rating",
      "confirm-target-audience",
      "confirm-sensitive-permissions",
      "confirm-ugc",
      "confirm-government-app",
      "confirm-financial-features",
      "confirm-health",
      "confirm-app-category-contact",
      "confirm-store-listing",
    ]);
    requireAppContentSubmissionPrerequisites();
    evidence.playConsole.appContentSubmitted = {
      ...evidence.playConsole.appContentSubmitted,
      done: true,
      submittedAt: normalizeTimestamp(requiredFlag("submitted-at")),
      privacyPolicyUrl: "https://verbal.chat/privacy",
      accountDeletionUrl: "https://verbal.chat/account/delete",
      dataDeletionUrl: "https://verbal.chat/data-deletion",
      completedSections: {
        privacyPolicy: true,
        appAccess: true,
        ads: true,
        dataSafety: true,
        accountDeletion: true,
        dataDeletion: true,
        contentRating: true,
        targetAudience: true,
        sensitivePermissions: true,
        ugc: true,
        governmentApp: true,
        financialFeatures: true,
        health: true,
        appCategoryContact: true,
        storeListing: true,
      },
      notes: optionalString("notes"),
    };
  } else if (command === "real-device-e2e") {
    const artifact = requireExistingArtifact(requiredFlag("artifact"));
    requireRealDeviceE2eArtifact(artifact);
    evidence.realDevice.e2e = {
      ...evidence.realDevice.e2e,
      done: true,
      testedAt: normalizeTimestamp(requiredFlag("tested-at")),
      tester: requiredFlag("tester"),
      artifact,
      deviceModel: optionalString("device-model"),
      notes: optionalString("notes"),
    };
  } else if (command === "fcm") {
    requireAllFlags(["foreground", "background", "terminated", "lock-screen"]);
    const artifact = requireExistingArtifact(requiredFlag("artifact"));
    requireFcmArtifact(artifact);
    evidence.realDevice.fcm = {
      ...evidence.realDevice.fcm,
      done: true,
      testedAt: normalizeTimestamp(requiredFlag("tested-at")),
      tester: requiredFlag("tester"),
      artifact,
      devices: collectValues("device"),
      states: {
        foreground: true,
        background: true,
        terminated: true,
        lockScreen: true,
      },
      notes: optionalString("notes"),
    };
  } else {
    fail(`Unknown command: ${command}`);
  }

  writeJson(evidencePath, evidence);
  printStatus();
}

function initEvidence({force}) {
  fs.mkdirSync(artifactDir, {recursive: true});
  if (fs.existsSync(evidencePath) && !force) {
    fail("artifacts/launch-manual-evidence.json already exists. Use --force to overwrite it.");
  }
  if (!fs.existsSync(templatePath)) {
    fail("Missing artifacts/launch-manual-evidence.template.json. Run npm run prepare:launch-evidence first.");
  }
  fs.copyFileSync(templatePath, evidencePath);
}

function loadEvidenceForUpdate() {
  if (!fs.existsSync(evidencePath)) {
    initEvidence({force: false});
  }
  const evidence = readJson(evidencePath);
  for (const key of ["playConsole", "realDevice"]) {
    if (!evidence[key]) {
      fail(`Invalid evidence file: missing ${key}`);
    }
  }
  return evidence;
}

function printStatus() {
  const evidence = fs.existsSync(evidencePath) ? readJson(evidencePath) : null;
  const androidRelease = readLatestAndroidRelease();
  const {checks, gates} = buildLaunchEvidenceChecks({
    evidence,
    androidRelease,
    repoRoot,
  });
  const failed = checks.filter((check) => !check.ok);
  const remainingGates = Object.entries(gates)
    .filter(([, value]) => !value.ok)
    .sort(([a], [b]) => compareRemainingGate(a, b))
    .map(([name]) => name);
  const result = {
    ok: failed.length === 0,
    evidenceFile: fs.existsSync(evidencePath) ? "artifacts/launch-manual-evidence.json" : "",
    gates,
    remainingGates,
    failedCount: failed.length,
    passedCount: checks.length - failed.length,
    failed: failed.map((check) => check.name),
    nextActions: buildRemainingEvidenceActions(gates),
    nextCommand:
      failed.length === 0
        ? "npm run report:launch-gate"
        : "npm run verify:launch-evidence",
  };
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = 0;
}

function buildRemainingEvidenceActions(gates) {
  const actions = [];
  if (!gates.playAppCreated?.ok) {
    actions.push({
      gate: "playAppCreated",
      action: "Create the app record in Google Play Console.",
      command:
        "npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>",
    });
  }
  if (!gates.internalTestingUpload?.ok) {
    actions.push({
      gate: "internalTestingUpload",
      action: "Upload dist/android/app-release.aab to the Internal testing track.",
      command:
        "npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>",
    });
  }
  if (!gates.appContentSubmitted?.ok) {
    actions.push({
      gate: "appContentSubmitted",
      action: "Complete Play Console App content and Data Safety forms.",
      command:
        "npm run record:app-content-submitted",
    });
  }
  if (!gates.preLaunchReportReviewed?.ok) {
    actions.push({
      gate: "preLaunchReportReviewed",
      action: "Review the Google Play Pre-launch report after Play Console generates it.",
      command:
        "npm run record:prelaunch-reviewed -- --report-url <https-url>",
    });
  }
  if (!gates.closedTestingCompleted?.ok) {
    actions.push({
      gate: "closedTestingCompleted",
      action:
        "Complete Play Console closed testing / production access readiness, or record why it is not required.",
      command:
        "npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>",
      alternativeCommand:
        'npm run record:closed-testing-not-required -- --reason "<reason>"',
    });
  }
  if (!gates.realDeviceE2e?.ok) {
    actions.push({
      gate: "realDeviceE2e",
      action: "Run the real Android device E2E QA script and record its artifact.",
      command:
        'npm run record:real-device-e2e -- --tester "<name>" --device-model "<device>"',
      prerequisite: ".\\scripts\\run-android-real-device-qa.ps1 -Interactive",
    });
  }
  if (!gates.fcm?.ok) {
    actions.push({
      gate: "fcm",
      action: "Run real-device FCM QA for foreground/background/terminated/lock-screen states.",
      command:
        'npm run record:fcm-real-device -- --tester "<name>" --device "<device>"',
      prerequisite: ".\\scripts\\run-fcm-real-device-qa.ps1",
    });
  }
  return actions;
}

function compareRemainingGate(a, b) {
  const ai = remainingGateOrder.includes(a)
    ? remainingGateOrder.indexOf(a)
    : Number.MAX_SAFE_INTEGER;
  const bi = remainingGateOrder.includes(b)
    ? remainingGateOrder.indexOf(b)
    : Number.MAX_SAFE_INTEGER;
  return ai - bi;
}

function printHelp() {
  console.log(`Usage:
  npm run record:launch-evidence -- init
  npm run record:launch-evidence -- status
  npm run record:launch-evidence -- play-app-created --created-at now --console-url https://play.google.com/console/...
  npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group "owner@example.com"
  npm run record:app-content-submitted
  npm run record:prelaunch-reviewed -- --report-url https://play.google.com/console/...
  npm run record:closed-testing-completed -- --started-at 2026-06-01 --ended-at 2026-06-15 --tester-count 12 --continuous-days 14
  npm run record:closed-testing-not-required -- --reason "Organization account does not require production access closed test"
  npm run record:real-device-e2e -- --tester "Name" --device-model "Galaxy"
  npm run record:fcm-real-device -- --tester "Name" --device "Galaxy"
`);
}

function parseFlags(values) {
  const result = {};
  for (let i = 0; i < values.length; i += 1) {
    const token = values[i];
    if (!token.startsWith("--")) {
      fail(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const next = values[i + 1];
    const value = next && !next.startsWith("--") ? values[++i] : true;
    if (result[key] === undefined) {
      result[key] = value;
    } else if (Array.isArray(result[key])) {
      result[key].push(value);
    } else {
      result[key] = [result[key], value];
    }
  }
  return result;
}

function requiredFlag(name) {
  const value = flags[name];
  if (typeof value !== "string" || value.trim() === "") {
    fail(`Missing required flag --${name}`);
  }
  return value.trim();
}

function requiredPositiveInteger(name) {
  const value = Number.parseInt(requiredFlag(name), 10);
  if (!Number.isInteger(value) || value <= 0) {
    fail(`Expected a positive integer for --${name}`);
  }
  return value;
}

function optionalString(name) {
  const value = flags[name];
  return typeof value === "string" ? value.trim() : "";
}

function collectValues(name) {
  const value = flags[name];
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim()).filter(Boolean);
  }
  if (typeof value === "string" && value.trim()) {
    return [value.trim()];
  }
  return [];
}

function requireAllFlags(names) {
  for (const name of names) {
    if (flags[name] !== true) {
      fail(`Missing required confirmation flag --${name}`);
    }
  }
}

function requireAppContentSubmissionPrerequisites() {
  const appContentPath = path.join(
    repoRoot,
    "artifacts",
    "play-console",
    "verbal-app-content-answers-latest.md",
  );
  const appContent = safeReadText(appContentPath);
  const requiredAppContentSnippets = [
    "https://verbal.chat/privacy",
    "https://verbal.chat/account/delete",
    "https://verbal.chat/data-deletion",
    "Console quick answers",
    "Does the app collect or share user data?",
    "Does the app share data with third parties?",
      "Detailed Play Console input matrix",
      "UGC present: Yes",
      "Government App",
      "Financial Features",
      "Health",
      "App Category And Contact Details",
      "Store Listing",
      "개인정보처리방침",
      "데이터 보안",
      "정부 앱",
      "금융 기능",
      "건강",
      "앱 카테고리 선택 및 연락처 세부정보 제공",
      "스토어 등록정보 설정",
    ];
  const missingAppContentSnippets = requiredAppContentSnippets.filter(
    (snippet) => !appContent.includes(snippet),
  );
  if (missingAppContentSnippets.length > 0) {
    fail(
      `App content answer pack is stale or incomplete. Run npm run prepare:app-content-answers. Missing: ${missingAppContentSnippets.join(", ")}`,
    );
  }

  const hostedPolicyPath = path.join(artifactDir, "hosted-policy-url-verification-latest.json");
  if (!fs.existsSync(hostedPolicyPath)) {
    fail("Missing hosted policy URL verification. Run npm run verify:hosted-policy-urls first.");
  }
  const hostedPolicy = readJson(hostedPolicyPath);
  if (hostedPolicy.ok !== true) {
    fail("Hosted policy URL verification is not passing. Run npm run verify:hosted-policy-urls first.");
  }
}

function normalizeTimestamp(value) {
  if (value === "now") {
    return new Date().toISOString();
  }
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    fail(`Invalid timestamp: ${value}`);
  }
  return new Date(parsed).toISOString();
}

function requireHttpsUrl(value) {
  if (!/^https:\/\/\S+$/i.test(value)) {
    fail(`Expected an https URL, got: ${value}`);
  }
  return value;
}

function requireExistingArtifact(value) {
  const normalized = value.replace(/\\/g, "/").replace(/^\.?\//, "");
  if (path.isAbsolute(normalized)) {
    fail("Artifact must be a repository-relative path under artifacts/.");
  }
  if (!normalized.startsWith("artifacts/")) {
    fail("Artifact must be under artifacts/.");
  }
  if (!fs.existsSync(path.join(repoRoot, normalized))) {
    fail(`Artifact does not exist: ${normalized}`);
  }
  return normalized;
}

function requireRealDeviceE2eArtifact(artifact) {
  const report = readArtifactJson(artifact);
  if (
    !report ||
    report.ok !== true ||
    !report.deviceId ||
    report.dryRun === true ||
    !hasCheck(report, "manual_e2e_confirmed") ||
    hasCheck(report, "precheck_completed") ||
    hasCheck(report, "dry_run_completed")
  ) {
    fail(`Real-device E2E artifact is not a passing real-device run: ${artifact}`);
  }
}

function requireFcmArtifact(artifact) {
  const report = readArtifactJson(artifact);
  const states = report?.states || {};
  if (
    !report ||
    report.ok !== true ||
    !report.deviceId ||
    report.dryRun === true ||
    states.foreground !== true ||
    states.background !== true ||
    states.terminated !== true ||
    states.lockScreen !== true ||
    hasCheck(report, "dry_run_completed")
  ) {
    fail(`FCM artifact must be a passing real-device FCM run with all states verified: ${artifact}`);
  }
}

function readArtifactJson(artifact) {
  if (!artifact.endsWith(".json")) {
    return null;
  }
  return readJson(path.join(repoRoot, artifact));
}

function hasCheck(report, name) {
  return Array.isArray(report?.checks) &&
    report.checks.some((check) => check.name === name && check.ok);
}

function assertAndroidRelease(androidRelease) {
  if (!androidRelease?.ok || !androidRelease?.android?.versionCode || !androidRelease?.release?.sha256) {
    fail("Missing valid Android release verification. Run npm run verify:android-release first.");
  }
}

function readLatestAndroidRelease() {
  const artifact = latestArtifact("android-release-verification-*.json");
  return artifact ? readJson(path.join(repoRoot, artifact)) : null;
}

function latestArtifact(pattern) {
  const [prefix, suffix] = pattern.split("*");
  if (!fs.existsSync(artifactDir)) {
    return "";
  }
  const matches = fs
    .readdirSync(artifactDir, {withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => name.startsWith(prefix) && name.endsWith(suffix))
    .filter((name) => !name.includes("-latest."))
    .map((name) => ({
      name,
      mtimeMs: fs.statSync(path.join(artifactDir, name)).mtimeMs,
    }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return matches[0]
    ? path.relative(repoRoot, path.join(artifactDir, matches[0].name)).replace(/\\/g, "/")
    : "";
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function safeReadText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  } catch {
    return "";
  }
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
