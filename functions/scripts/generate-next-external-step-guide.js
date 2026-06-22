const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `next-external-step-${runId}.json`);
const mdPath = path.join(artifactDir, `next-external-step-${runId}.md`);
const latestJsonPath = path.join(artifactDir, "next-external-step-latest.json");
const latestMdPath = path.join(artifactDir, "next-external-step-latest.md");

const priority = [
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
  const guide = buildGuide();
  writeJson(jsonPath, guide);
  writeJson(latestJsonPath, guide);
  fs.writeFileSync(mdPath, renderMarkdown(guide), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(guide), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        currentStage: guide.currentStage,
        nextBlocker: guide.nextBlocker,
        nextTitle: guide.nextAction.title,
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
      },
      null,
      2,
    ),
  );
}

function buildGuide() {
  const launchGate = readJson("artifacts/launch-gate-latest.json") || {};
  const launchStatus = readJson("artifacts/launch-status-latest.json") || {};
  const launchEvidence = readJson("artifacts/launch-manual-evidence.json") || {};
  const blockers = normalizeBlockers(launchGate.blockers);
  const orderedBlockers = orderBlockers(blockers);
  const nextBlocker = orderedBlockers[0] || "";
  const appContentAnswers =
    readJson("artifacts/play-console/verbal-app-content-answers-latest.json") || {};
  const context = {launchEvidence};
  const nextAction = actionFor(nextBlocker, appContentAnswers, context);
  const actionPlan = orderedBlockers.map((blocker) => ({
    blocker,
    ...actionFor(blocker, appContentAnswers, context),
  }));

  return {
    generatedAt: new Date().toISOString(),
    currentStage: launchStatus.currentStage || "unknown",
    readyForInternalTestingUpload: Boolean(launchGate.readyForInternalTestingUpload),
    readyForPublicUserExposure: Boolean(launchGate.readyForPublicUserExposure),
    blockers: orderedBlockers,
    nextBlocker,
    nextAction,
    actionPlan,
    afterDone: {
      rerun: [
        "npm run verify:launch-evidence",
        "npm run report:launch-gate",
        "npm run status:launch",
        "npm run guide:next-launch-step",
      ],
    },
  };
}

function actionFor(blocker, appContentAnswers, context = {}) {
  const playAppUrl = context.launchEvidence?.playConsole?.appCreated?.consoleUrl || "";
  const actions = {
    play_console_app_created: {
      title: "Create Google Play Console app record",
      consolePath: "Google Play Console > All apps > Create app",
      status: "Already completed for the current Verbal app if launch evidence is current.",
      sourceArtifacts: ["artifacts/launch-manual-evidence.json"],
      steps: [
        "Create app name Verbal.",
        "Use package com.voicebeta.verbal when the AAB is uploaded.",
        "Do not roll out to public users from this step.",
      ],
      recordCommand:
        "npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>",
    },
    play_internal_testing_uploaded: {
      title: "Upload AAB to Google Play Internal testing",
      consolePath: "Google Play Console > Test and release > Testing > Internal testing",
      status: "Already completed for the current 1 (1.0.0) AAB if launch evidence is current.",
      sourceArtifacts: [
        "dist/android/app-release.aab",
        "artifacts/play-console/verbal-play-console-pack-latest.md",
      ],
      steps: [
        "Upload dist/android/app-release.aab.",
        "Confirm package com.voicebeta.verbal and version 1 (1.0.0).",
        "Add tester emails or a tester Google Group.",
      ],
      recordCommand:
        "npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>",
    },
    play_data_safety_submitted: buildAppContentAction(appContentAnswers, playAppUrl),
    play_prelaunch_report_reviewed: {
      title: "Review Google Play Pre-launch report",
      consolePath: "Google Play Console > Test and release > Testing > Pre-launch report",
      sourceArtifacts: ["artifacts/launch-handoff-latest.md"],
      steps: [
        "Open the generated Pre-launch report for the uploaded Internal testing build.",
        "Review Stability, Performance, Accessibility, and Screenshots.",
        "Resolve any blocking crash, login, permission, rendering, or policy issue before recording evidence.",
      ],
      recordCommand:
        "npm run record:prelaunch-reviewed -- --report-url <https-url>",
    },
    play_closed_testing_completed: {
      title: "Complete closed testing or record non-required reason",
      consolePath: "Google Play Console > Test and release > Testing > Closed testing",
      sourceArtifacts: [
        "artifacts/play-console/closed-testing/verbal-closed-testing-pack-latest.md",
      ],
      steps: [
        "If Play Console requires production access testing, run closed testing with at least 12 opted-in testers for at least 14 continuous days.",
        "Review tester feedback and triage blocking issues.",
        "If the account/app is not subject to this requirement, record the Play Console non-required reason instead.",
      ],
      recordCommand:
        "npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>",
      alternativeCommand:
        'npm run record:closed-testing-not-required -- --reason "<reason>"',
    },
    android_real_device_e2e_verified: {
      title: "Run Android real-device E2E QA",
      consolePath: "Local PowerShell with a connected Android device",
      sourceArtifacts: ["scripts/run-android-real-device-qa.ps1"],
      steps: [
        "Connect a real Android device by USB with ADB authorized.",
        "Run the interactive QA script.",
        "Confirm sign-in, chat, text, voice STT, playback, calendar, report/block, and account deletion entry point.",
      ],
      prerequisite: ".\\scripts\\run-android-real-device-qa.ps1 -Interactive",
      recordCommand:
        'npm run record:real-device-e2e -- --tester "<name>" --device-model "<device>"',
    },
    fcm_real_device_delivery_verified: {
      title: "Run FCM real-device delivery QA",
      consolePath: "Local PowerShell with a connected Android device",
      sourceArtifacts: ["scripts/run-fcm-real-device-qa.ps1"],
      steps: [
        "Use an installed real-device build with notification permission granted.",
        "Verify foreground, background, terminated, and lock-screen push delivery.",
        "Record only after all four states pass.",
      ],
      prerequisite: ".\\scripts\\run-fcm-real-device-qa.ps1",
      recordCommand:
        'npm run record:fcm-real-device -- --tester "<name>" --device "<device>"',
    },
  };

  return actions[blocker] || {
    title: "No remaining blocker",
    consolePath: "",
    sourceArtifacts: ["artifacts/launch-gate-latest.json"],
    steps: [
      "Launch gate has no known blockers. Confirm readyForPublicUserExposure is true before production rollout.",
    ],
    recordCommand: "",
  };
}

function buildAppContentAction(answers, playAppUrl) {
  return {
    title: "Complete Google Play App content and Data Safety forms",
    consolePath: "Google Play Console > Policy and programs > App content",
    sourceArtifacts: [
      "artifacts/play-console/verbal-app-content-answers-latest.md",
      "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
      "docs/PLAY_APP_CONTENT_WORKSHEET.md",
      "docs/GOOGLE_PLAY_DATA_SAFETY.md",
    ],
    steps: [
      playAppUrl
        ? `Open the Verbal app in Google Play Console: ${playAppUrl}`
        : "Open the Verbal app in Google Play Console.",
      "Open Policy and programs > App content.",
      "Open artifacts/play-console/verbal-app-content-copy-sheet-latest.html in a browser for copy buttons, or use artifacts/play-console/verbal-app-content-answers-latest.md as a plain-text fallback.",
      "Fill Privacy Policy, App access, Ads, Data Safety, Account deletion, Data deletion, Content rating, Target audience, Sensitive permissions, UGC, Government App, Financial Features, Health, App category/contact, and Store listing using the table values.",
      "Save every section. Do not submit production/public rollout yet.",
    ],
    consoleSections: answers.consoleSections || [],
    exactValues: {
      sectionBySectionSource:
        "artifacts/play-console/verbal-app-content-answers-latest.md > Section-by-section Console Flow",
      copySheet: "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
      playConsoleAppUrl: playAppUrl || "Open from Google Play Console app list.",
      privacyPolicy: answers.policyUrls?.privacyPolicy || "https://verbal.chat/privacy",
      accountDeletion: answers.policyUrls?.accountDeletion || "https://verbal.chat/account/delete",
      dataDeletion: answers.policyUrls?.dataDeletion || "https://verbal.chat/data-deletion",
      supportEmail: answers.appIdentity?.supportEmail || "support@verbal.chat",
      appAccess: {
        answer: answers.appAccess?.answer || "All or some functionality is restricted",
        testPhoneNumber: answers.appAccess?.testPhoneNumber || "+16505550101",
        testVerificationCode: answers.appAccess?.testVerificationCode || "123456",
        reviewerInstruction: answers.appAccess?.instructions || "",
      },
      ads: answers.ads?.answer || "No",
      dataEncryptedInTransit: answers.dataSafety?.encryptedInTransit ?? true,
      usersCanRequestDeletion: answers.dataSafety?.usersCanRequestDeletion ?? true,
      consoleQuickAnswers: answers.dataSafety?.consoleQuickAnswers || [],
      ugcPolicy:
        answers.userGeneratedContent?.policyUrl ||
        "https://verbal.chat/community-guidelines",
      recommendedTargetAudience:
        answers.targetAudience?.recommendedForInitialRelease ||
        "Adult age groups only for initial testing.",
    },
    recordCommand:
      answers.recordCommand ||
      "npm run record:app-content-submitted",
  };
}

function renderMarkdown(guide) {
  const action = guide.nextAction;
  return `# Verbal Next External Launch Step

Generated: ${guide.generatedAt}

## Current Gate

- Current stage: \`${guide.currentStage}\`
- Ready for Internal testing upload: ${yesNo(guide.readyForInternalTestingUpload)}
- Ready for public user exposure: ${yesNo(guide.readyForPublicUserExposure)}
- Next blocker: ${guide.nextBlocker ? `\`${guide.nextBlocker}\`` : "None"}

## Next Action

${action.title}

- Console/location: ${action.consolePath || "n/a"}
- Source artifacts:
${action.sourceArtifacts.map((item) => `  - \`${item}\``).join("\n")}

## Open Current Workbench

\`\`\`powershell
cd .\\functions
npm run open:next-launch-step
\`\`\`

## Steps

${action.steps.map((item, index) => `${index + 1}. ${item}`).join("\n")}

${renderKoreanConsoleFlow(action.consoleSections)}${
    action.prerequisite
      ? `## Prerequisite\n\n\`\`\`powershell\n${action.prerequisite}\n\`\`\`\n`
      : ""
  }${renderExactValues(action.exactValues)}${renderRemainingPlan(
    guide.actionPlan,
    guide.nextBlocker,
  )}## Record Evidence After Completion

${
  action.recordCommand
    ? `\`\`\`powershell\n${action.recordCommand}\n\`\`\``
    : "No evidence command required."
}

${
  action.alternativeCommand
    ? `Alternative:\n\n\`\`\`powershell\n${action.alternativeCommand}\n\`\`\`\n`
    : ""
}## Recheck After Recording

\`\`\`powershell
${guide.afterDone.rerun.join("\n")}
\`\`\`

Do not expose Verbal to general public users until \`readyForPublicUserExposure\`
is true in \`artifacts/launch-gate-latest.json\`.
`;
}

function renderRemainingPlan(actionPlan, nextBlocker) {
  if (!Array.isArray(actionPlan) || actionPlan.length === 0) {
    return "";
  }
  return `## Remaining Public Exposure Sequence

These are the remaining gates in the order they must be cleared. The first row is the current next blocker.

| Order | Blocker | Action | Evidence command |
|---:|---|---|---|
${actionPlan
  .map((item, index) => {
    const marker = item.blocker === nextBlocker ? "current" : "next";
    const command = item.recordCommand || item.alternativeCommand || "";
    return `| ${index + 1} | \`${item.blocker}\` (${marker}) | ${item.title} | \`${command}\` |`;
  })
  .join("\n")}

`;
}

function renderExactValues(values) {
  if (!values) {
    return "";
  }
  return `## Exact Values

\`\`\`json
${JSON.stringify(values, null, 2)}
\`\`\`

`;
}

function renderKoreanConsoleFlow(sections) {
  if (!Array.isArray(sections) || sections.length === 0) {
    return "";
  }
  return `## Korean Console Flow

Use this table directly against the Korean Google Play Console screen.

| Order | Console section | Korean UI label | What to enter | Exact value/source |
|---:|---|---|---|---|
${sections
  .map(
    (section, index) =>
      `| ${index + 1} | ${section.name} | ${section.koreanName} | ${section.action} | ${section.value} |`,
  )
  .join("\n")}

`;
}

function normalizeBlockers(blockers) {
  if (!Array.isArray(blockers)) {
    return [];
  }
  return blockers
    .map((item) => (typeof item === "string" ? item : item?.name))
    .filter(Boolean);
}

function orderBlockers(blockers) {
  return [...blockers].sort((a, b) => {
    const ai = priority.includes(a) ? priority.indexOf(a) : Number.MAX_SAFE_INTEGER;
    const bi = priority.includes(b) ? priority.indexOf(b) : Number.MAX_SAFE_INTEGER;
    return ai - bi;
  });
}

function readJson(relativePath) {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(repoRoot, relativePath), "utf8").replace(/^\uFEFF/, ""),
    );
  } catch {
    return null;
  }
}

function yesNo(value) {
  return value ? "Yes" : "No";
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
