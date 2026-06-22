const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `launch-status-${runId}.json`);
const mdPath = path.join(artifactDir, `launch-status-${runId}.md`);
const latestJsonPath = path.join(artifactDir, "launch-status-latest.json");
const latestMdPath = path.join(artifactDir, "launch-status-latest.md");

const blockerActions = [
  {
    blocker: "play_console_app_created",
    label: "Create the Google Play Console app record",
    command:
      "npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>",
  },
  {
    blocker: "play_internal_testing_uploaded",
    label: "Upload dist/android/app-release.aab to Internal testing",
    command:
      "npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>",
  },
  {
    blocker: "play_data_safety_submitted",
    label: "Complete App content and Data Safety forms",
    command:
      "npm run record:app-content-submitted",
  },
  {
    blocker: "play_prelaunch_report_reviewed",
    label: "Review Google Play Pre-launch report",
    command:
      "npm run record:prelaunch-reviewed -- --report-url <https-url>",
  },
  {
    blocker: "play_closed_testing_completed",
    label: "Complete closed testing or record that it is not required",
    command:
      "npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>",
    alternativeCommand:
      'npm run record:closed-testing-not-required -- --reason "<reason>"',
  },
  {
    blocker: "android_real_device_e2e_verified",
    label: "Run Android real-device E2E QA",
    prerequisite: ".\\scripts\\run-android-real-device-qa.ps1 -Interactive",
    command:
      'npm run record:real-device-e2e -- --tester "<name>" --device-model "<device>"',
  },
  {
    blocker: "fcm_real_device_delivery_verified",
    label: "Run FCM real-device delivery QA",
    prerequisite: ".\\scripts\\run-fcm-real-device-qa.ps1",
    command:
      'npm run record:fcm-real-device -- --tester "<name>" --device "<device>"',
  },
];

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const status = buildStatus();
  writeJson(jsonPath, status);
  writeJson(latestJsonPath, status);
  fs.writeFileSync(mdPath, renderMarkdown(status), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(status), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        currentStage: status.currentStage,
        nextStep: status.nextStep?.label || "",
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
      },
      null,
      2,
    ),
  );
}

function buildStatus() {
  const launchGate = readJsonIfExists(path.join(artifactDir, "launch-gate-latest.json")) || {};
  const preinternal = readJsonIfExists(
    path.join(artifactDir, "preinternal-release-check-latest.json"),
  ) || {};
  const consistency = readJsonIfExists(
    path.join(artifactDir, "launch-consistency-latest.json"),
  ) || {};
  const evidenceVerification = readJsonIfExists(
    path.join(artifactDir, "launch-evidence-verification-latest.json"),
  ) || {};
  const handoff = readJsonIfExists(path.join(artifactDir, "launch-handoff-latest.json")) || {};
  const blockers = normalizeBlockers(launchGate.blockers);
  const remainingSteps = blockerActions.filter((item) => blockers.includes(item.blocker));
  const nextStep = remainingSteps[0] || null;
  const readyForInternalTestingUpload = Boolean(launchGate.readyForInternalTestingUpload);
  const readyForPublicUserExposure = Boolean(launchGate.readyForPublicUserExposure);
  const currentStage = stage({
    preinternalOk: Boolean(preinternal.ok),
    readyForInternalTestingUpload,
    readyForPublicUserExposure,
    blockers,
  });

  return {
    generatedAt: new Date().toISOString(),
    currentStage,
    readyForInternalTestingUpload,
    readyForPublicUserExposure,
    publicExposureBlockedAsExpected: !readyForPublicUserExposure,
    localChecks: {
      preinternalOk: Boolean(preinternal.ok),
      launchConsistencyOk: Boolean(consistency.ok),
      launchEvidenceStrictOk: Boolean(
        evidenceVerification.ok &&
          evidenceVerification.allowIncompleteExternalEvidence !== true,
      ),
      launchEvidenceAllowIncomplete: Boolean(
        evidenceVerification.allowIncompleteExternalEvidence,
      ),
    },
    release: {
      aab: existingArtifact("dist/android/app-release.aab"),
      playConsolePack: latestArtifactIn("play-console", "verbal-play-console-pack-*.md"),
      appContentCopySheet: existingArtifact(
        "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
      ),
      closedTestingPack: latestArtifactIn(
        path.join("play-console", "closed-testing"),
        "verbal-closed-testing-pack-*.md",
      ),
      launchHandoff: existingArtifact("artifacts/launch-handoff-latest.md"),
      launchGate: existingArtifact("artifacts/launch-gate-latest.md"),
    },
    blockers,
    nextStep,
    remainingSteps,
    handoffGeneratedAt: handoff.generatedAt || "",
  };
}

function stage({
  preinternalOk,
  readyForInternalTestingUpload,
  readyForPublicUserExposure,
  blockers,
}) {
  if (readyForPublicUserExposure) {
    return "ready_for_public_user_exposure";
  }
  if (
    readyForInternalTestingUpload &&
    !blockers.includes("play_internal_testing_uploaded")
  ) {
    return "google_play_internal_testing_uploaded";
  }
  if (readyForInternalTestingUpload) {
    return "ready_for_google_play_internal_testing_upload";
  }
  if (preinternalOk) {
    return "local_checks_passed_but_launch_gate_not_ready";
  }
  return "local_checks_need_attention";
}

function renderMarkdown(status) {
  return `# Verbal Launch Status

Generated: ${status.generatedAt}

## Current Stage

- Stage: \`${status.currentStage}\`
- Ready for Google Play Internal testing upload: ${yesNo(status.readyForInternalTestingUpload)}
- Ready for public user exposure: ${yesNo(status.readyForPublicUserExposure)}
- Public exposure blocked as expected: ${yesNo(status.publicExposureBlockedAsExpected)}

## Local Checks

- Preinternal check passed: ${yesNo(status.localChecks.preinternalOk)}
- Launch consistency passed: ${yesNo(status.localChecks.launchConsistencyOk)}
- Strict launch evidence passed: ${yesNo(status.localChecks.launchEvidenceStrictOk)}
- Evidence allow-incomplete mode was used: ${yesNo(status.localChecks.launchEvidenceAllowIncomplete)}

## Release Artifacts

- Release AAB: ${artifactLine(status.release.aab)}
- Play Console pack: ${artifactLine(status.release.playConsolePack)}
- App content copy sheet: ${artifactLine(status.release.appContentCopySheet)}
- Closed testing pack: ${artifactLine(status.release.closedTestingPack)}
- Launch handoff: ${artifactLine(status.release.launchHandoff)}
- Launch gate: ${artifactLine(status.release.launchGate)}

## Next External Step

${status.nextStep ? renderStep(status.nextStep) : "No remaining external step recorded."}

## Remaining Public Exposure Blockers

${status.blockers.length > 0 ? status.blockers.map((item) => `- \`${item}\``).join("\n") : "- None"}

## Remaining Evidence Sequence

${status.remainingSteps.length > 0 ? status.remainingSteps.map((item, index) => renderNumberedStep(index + 1, item)).join("\n\n") : "No remaining evidence sequence."}

After recording any completed evidence, run:

\`\`\`powershell
npm run verify:launch-evidence
npm run report:launch-gate
npm run status:launch
\`\`\`

Do not expose Verbal to general public users until \`readyForPublicUserExposure\`
is true in \`artifacts/launch-gate-latest.json\`.
`;
}

function renderStep(item) {
  const lines = [`${item.label}`];
  if (item.prerequisite) {
    lines.push(`- Prerequisite: \`${item.prerequisite}\``);
  }
  lines.push(`- Record: \`${item.command}\``);
  if (item.alternativeCommand) {
    lines.push(`- Alternative: \`${item.alternativeCommand}\``);
  }
  return lines.join("\n");
}

function renderNumberedStep(index, item) {
  const lines = [`${index}. ${item.label}`];
  if (item.prerequisite) {
    lines.push(`   - Prerequisite: \`${item.prerequisite}\``);
  }
  lines.push(`   - Record: \`${item.command}\``);
  if (item.alternativeCommand) {
    lines.push(`   - Alternative: \`${item.alternativeCommand}\``);
  }
  return lines.join("\n");
}

function normalizeBlockers(blockers) {
  if (!Array.isArray(blockers)) {
    return [];
  }
  return blockers
    .map((item) => (typeof item === "string" ? item : item?.name))
    .filter(Boolean);
}

function artifactLine(value) {
  return value ? `\`${value}\`` : "Not found";
}

function yesNo(value) {
  return value ? "Yes" : "No";
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
