const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const outputPath = path.join(artifactDir, "launch-manual-evidence.template.json");

fs.mkdirSync(artifactDir, {recursive: true});
const androidRelease = readLatestAndroidRelease();
const releaseVersionCode = String(androidRelease?.android?.versionCode || "1");
const releaseSha256 = String(androidRelease?.release?.sha256 || "");
const releaseVersionName = String(androidRelease?.android?.versionName || "");

const template = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  instructions:
    "Use npm run record:launch-evidence -- init to copy this template, then record only completed external evidence with npm run record:launch-evidence -- <command>.",
  playConsole: {
    appCreated: {
      done: false,
      appName: "Verbal",
      packageName: "com.voicebeta.verbal",
      createdAt: "",
      consoleUrl: "",
      notes: "",
    },
    internalTestingUpload: {
      done: false,
      track: "internal",
      packageName: "com.voicebeta.verbal",
      versionCode: releaseVersionCode,
      aabSha256: releaseSha256,
      uploadedAt: "",
      releaseName: releaseVersionName ? `Verbal ${releaseVersionName}` : "",
      testerGroupOrEmails: "",
      notes: "",
    },
    preLaunchReportReviewed: {
      done: false,
      reviewedAt: "",
      reportUrl: "",
      completedSections: {
        stability: false,
        performance: false,
        accessibility: false,
        screenshots: false,
      },
      noBlockingIssues: false,
      notes: "",
    },
    closedTestingCompleted: {
      done: false,
      requiredByPlayConsole: true,
      startedAt: "",
      endedAt: "",
      testerCount: 0,
      continuousDays: 0,
      feedbackReviewed: false,
      productionAccessReady: false,
      notRequiredReason: "",
      notes: "",
    },
    appContentSubmitted: {
      done: false,
      submittedAt: "",
      privacyPolicyUrl: "https://verbal.chat/privacy",
      accountDeletionUrl: "https://verbal.chat/account/delete",
      dataDeletionUrl: "https://verbal.chat/data-deletion",
      completedSections: {
        privacyPolicy: false,
        appAccess: false,
        ads: false,
        dataSafety: false,
        accountDeletion: false,
        dataDeletion: false,
        contentRating: false,
        targetAudience: false,
        sensitivePermissions: false,
        ugc: false,
        governmentApp: false,
        financialFeatures: false,
        health: false,
        appCategoryContact: false,
        storeListing: false,
      },
      notes: "",
    },
  },
  realDevice: {
    e2e: {
      done: false,
      testedAt: "",
      tester: "",
      artifact: "artifacts/android-real-device-qa-latest.json",
      deviceModel: "",
      notes: "",
    },
    fcm: {
      done: false,
      testedAt: "",
      tester: "",
      artifact: "artifacts/fcm-real-device-latest.json",
      devices: [],
      states: {
        foreground: false,
        background: false,
        terminated: false,
        lockScreen: false,
      },
      notes: "",
    },
  },
};

fs.writeFileSync(outputPath, `${JSON.stringify(template, null, 2)}\n`, "utf8");
console.log(
  JSON.stringify(
    {
      ok: true,
      template: path.relative(repoRoot, outputPath),
      target: "artifacts/launch-manual-evidence.json",
    },
    null,
    2,
  ),
);

function readLatestAndroidRelease() {
  const artifact = latestArtifact("android-release-verification-*.json");
  if (!artifact) {
    return null;
  }
  try {
    const text = fs.readFileSync(path.join(repoRoot, artifact), "utf8").replace(/^\uFEFF/, "");
    return JSON.parse(text);
  } catch {
    return null;
  }
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
    .map((name) => {
      const fullPath = path.join(artifactDir, name);
      return {name, mtimeMs: fs.statSync(fullPath).mtimeMs};
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return matches[0]
    ? path.relative(repoRoot, path.join(artifactDir, matches[0].name)).replace(/\\/g, "/")
    : "";
}
