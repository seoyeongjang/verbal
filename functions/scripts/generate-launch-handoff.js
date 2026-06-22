const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `launch-handoff-${runId}.json`);
const mdPath = path.join(artifactDir, `launch-handoff-${runId}.md`);
const latestJsonPath = path.join(artifactDir, "launch-handoff-latest.json");
const latestMdPath = path.join(artifactDir, "launch-handoff-latest.md");

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const handoff = buildHandoff();
  writeJson(jsonPath, handoff);
  writeJson(latestJsonPath, handoff);
  fs.writeFileSync(mdPath, renderMarkdown(handoff), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(handoff), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        readyForInternalTestingUpload: handoff.status.readyForInternalTestingUpload,
        readyForPublicUserExposure: handoff.status.readyForPublicUserExposure,
        blockers: handoff.status.blockers,
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
      },
      null,
      2,
    ),
  );
}

function buildHandoff() {
  const launchGate = readJsonIfExists(path.join(artifactDir, "launch-gate-latest.json")) || {};
  const launchReadiness = readLatestJson("launch-readiness-*.json");
  const androidRelease = readLatestJson("android-release-verification-*.json");
  const playConsolePack = latestArtifactIn("play-console", "verbal-play-console-pack-*.md");
  const closedTestingPack = latestArtifactIn(
    path.join("play-console", "closed-testing"),
    "verbal-closed-testing-pack-*.md",
  );
  const launchEvidence = existingArtifact("artifacts/launch-manual-evidence.json");
  const launchEvidenceStatus = readLaunchEvidenceStatus();
  const blockers = Array.isArray(launchGate.blockers)
    ? launchGate.blockers.map((item) => item.name)
    : [];
  const externalSequence = buildExternalSequence();
  const completedExternalSteps = externalSequence.filter(
    (item) => item.blocker && !blockers.includes(item.blocker),
  );
  const remainingExternalSteps = externalSequence.filter(
    (item) => !item.blocker || blockers.includes(item.blocker),
  );

  return {
    generatedAt: new Date().toISOString(),
    purpose:
      "Single handoff file for the remaining external steps before public user exposure.",
    status: {
      readyForInternalTestingUpload: Boolean(launchGate.readyForInternalTestingUpload),
      readyForPublicUserExposure: Boolean(launchGate.readyForPublicUserExposure),
      blockers,
    },
    artifacts: {
      releaseAab: existingArtifact("dist/android/app-release.aab"),
      androidReleaseVerification: androidRelease.path,
      launchReadiness: launchReadiness.path,
      launchGate: existingArtifact("artifacts/launch-gate-latest.md"),
      playConsolePack,
      appContentCopySheet: existingArtifact(
        "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
      ),
      closedTestingPack,
      launchEvidence,
      storeAssets: existingArtifact("artifacts/store/google-play/assets"),
      accountDeletionUrl: "https://verbal.chat/account/delete",
      privacyPolicyUrl: "https://verbal.chat/privacy",
      dataDeletionUrl: "https://verbal.chat/data-deletion",
    },
    completedExternalSteps,
    remainingExternalSteps,
    currentEvidenceStatus: launchEvidenceStatus,
  };
}

function buildExternalSequence() {
  return [
      {
        blocker: "play_console_app_created",
        step: "Create Google Play Console app record",
        evidenceCommand:
          "npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>",
      },
      {
        blocker: "play_internal_testing_uploaded",
        step: "Upload dist/android/app-release.aab to Internal testing",
        evidenceCommand:
          "npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>",
      },
      {
        blocker: "play_data_safety_submitted",
        step: "Complete App content and Data Safety forms",
        sourceArtifact:
          "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
        evidenceCommand:
          "npm run record:app-content-submitted",
      },
      {
        blocker: "play_prelaunch_report_reviewed",
        step: "Review Google Play Pre-launch report",
        evidenceCommand:
          "npm run record:prelaunch-reviewed -- --report-url <https-url>",
      },
      {
        blocker: "play_closed_testing_completed",
        step: "Complete closed testing / production access readiness if required",
        sourceArtifact:
          "artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md",
        evidenceCommand:
          "npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>",
        alternativeCommand:
          'npm run record:closed-testing-not-required -- --reason "<reason>"',
      },
      {
        blocker: "android_real_device_e2e_verified",
        step: "Run Android real-device E2E",
        prerequisite: ".\\scripts\\run-android-real-device-qa.ps1 -Interactive",
        evidenceCommand:
          'npm run record:real-device-e2e -- --tester "<name>" --device-model "<device>"',
      },
      {
        blocker: "fcm_real_device_delivery_verified",
        step: "Run FCM real-device QA",
        prerequisite: ".\\scripts\\run-fcm-real-device-qa.ps1",
        evidenceCommand:
          'npm run record:fcm-real-device -- --tester "<name>" --device "<device>"',
      },
      {
        step: "Verify final launch evidence and gate",
        evidenceCommand:
          "npm run verify:launch-evidence && npm run report:launch-gate",
      },
    ];
}

function readLaunchEvidenceStatus() {
  const file = path.join(artifactDir, "launch-evidence-verification-latest.json");
  const data = readJsonIfExists(file);
  if (!data) {
    return {
      artifact: "",
      ok: false,
      note: "No launch evidence verification artifact found.",
    };
  }
  return {
    artifact: "artifacts/launch-evidence-verification-latest.json",
    ok: Boolean(data.ok),
    strictOk: Boolean(data.ok && !data.allowIncompleteExternalEvidence),
    failedCount: Number(data.failedCount || 0),
    allowIncompleteExternalEvidence: Boolean(data.allowIncompleteExternalEvidence),
  };
}

function renderMarkdown(handoff) {
  return `# Verbal Launch Handoff

Generated: ${handoff.generatedAt}

${handoff.purpose}

## Status

- Ready for Google Play Internal testing upload: ${handoff.status.readyForInternalTestingUpload ? "Yes" : "No"}
- Ready for public user exposure: ${handoff.status.readyForPublicUserExposure ? "Yes" : "No"}
- Public exposure blockers:
${handoff.status.blockers.length > 0 ? handoff.status.blockers.map((item) => `  - \`${item}\``).join("\n") : "  - None"}

## Required Artifacts

- Release AAB: ${artifactLine(handoff.artifacts.releaseAab)}
- Android release verification: ${artifactLine(handoff.artifacts.androidReleaseVerification)}
- Launch readiness: ${artifactLine(handoff.artifacts.launchReadiness)}
- Launch gate: ${artifactLine(handoff.artifacts.launchGate)}
- Play Console pack: ${artifactLine(handoff.artifacts.playConsolePack)}
- App content copy sheet: ${artifactLine(handoff.artifacts.appContentCopySheet)}
- Closed testing pack: ${artifactLine(handoff.artifacts.closedTestingPack)}
- Manual launch evidence: ${artifactLine(handoff.artifacts.launchEvidence)}
- Store assets: ${artifactLine(handoff.artifacts.storeAssets)}
- Privacy Policy URL: ${handoff.artifacts.privacyPolicyUrl}
- Account Deletion URL: ${handoff.artifacts.accountDeletionUrl}
- Data Deletion URL: ${handoff.artifacts.dataDeletionUrl}

## Completed External Work

${handoff.completedExternalSteps.length > 0 ? handoff.completedExternalSteps.map((item) => `- ${item.step}`).join("\n") : "- None recorded yet"}

## Remaining External Work Sequence

${handoff.remainingExternalSteps.map((item, index) => renderStep(index + 1, item)).join("\n\n")}

## Current Evidence Status

- Artifact: ${artifactLine(handoff.currentEvidenceStatus.artifact)}
- Strict evidence verification passed: ${handoff.currentEvidenceStatus.strictOk ? "Yes" : "No"}
- Preinternal evidence shape passed: ${handoff.currentEvidenceStatus.ok ? "Yes" : "No"}
- Failed count: ${handoff.currentEvidenceStatus.failedCount ?? "n/a"}
- Allow-incomplete preinternal mode was used: ${handoff.currentEvidenceStatus.allowIncompleteExternalEvidence ? "Yes" : "No"}

Do not expose the app to general public users until \`readyForPublicUserExposure\`
is true in \`artifacts/launch-gate-latest.json\`.
`;
}

function renderStep(index, item) {
  const lines = [`${index}. ${item.step}`];
  if (item.sourceArtifact) {
    lines.push(`   - Source: \`${item.sourceArtifact}\``);
  }
  if (item.prerequisite) {
    lines.push(`   - Prerequisite: \`${item.prerequisite}\``);
  }
  lines.push(`   - Record: \`${item.evidenceCommand}\``);
  if (item.alternativeCommand) {
    lines.push(`   - Alternative: \`${item.alternativeCommand}\``);
  }
  return lines.join("\n");
}

function artifactLine(value) {
  return value ? `\`${value}\`` : "Not found";
}

function readLatestJson(pattern) {
  const artifact = latestArtifact(pattern);
  return {
    path: artifact,
    data: artifact ? readJsonIfExists(path.join(repoRoot, artifact)) : null,
  };
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
