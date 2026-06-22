const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const outputDir = path.join(repoRoot, "artifacts", "play-console");
const jsonPath = path.join(outputDir, `verbal-play-console-pack-${runId}.json`);
const mdPath = path.join(outputDir, `verbal-play-console-pack-${runId}.md`);
const latestJsonPath = path.join(outputDir, "verbal-play-console-pack-latest.json");
const latestMdPath = path.join(outputDir, "verbal-play-console-pack-latest.md");

main();

function main() {
  fs.mkdirSync(outputDir, {recursive: true});

  const android = getAndroidIdentity();
  const release = getReleaseArtifact();
  const storeListing = {
    koKR: readListing("ko-KR"),
    enUS: readListing("en-US"),
  };
  assertReadableStoreListing(storeListing);

  const pack = {
    generatedAt: new Date().toISOString(),
    app: {
      name: "Verbal",
      defaultLanguage: "ko-KR",
      type: "App",
      category: "Communication",
      pricing: "Free",
      packageName: android.applicationId,
      firebaseProjectId: "voice-messenger-jangs-260522",
      firebaseAndroidAppId: android.firebaseAppId,
    },
    release,
    policyUrls: {
      website: "https://verbal.chat",
      privacyPolicy: "https://verbal.chat/privacy",
      termsOfService: "https://verbal.chat/terms",
      communityGuidelines: "https://verbal.chat/community-guidelines",
      accountDeletion: "https://verbal.chat/account/delete",
      dataDeletion: "https://verbal.chat/data-deletion",
      firebaseFallbackAccountDeletion:
        "https://voice-messenger-jangs-260522.web.app/account/delete",
    },
    support: {
      email: "support@verbal.chat",
      routedTo: "jangseo37@gmail.com",
      inboundProvider: "Cloudflare Email Routing",
      outboundProvider: "Not configured yet",
    },
    storeListing,
    dataSafetyDraft: {
      source: "docs/GOOGLE_PLAY_DATA_SAFETY.md",
      collectedData:
        "Phone number, user IDs, profile text, messages, voice recordings, transcripts, attachments, user-shared location, device IDs/push tokens, app interactions, diagnostics.",
      thirdPartyProcessing:
        "Firebase/Google Cloud for infrastructure and Deepgram for voice STT processing.",
      deletionMechanism:
        "In-app account deletion plus https://verbal.chat/account/delete and https://verbal.chat/data-deletion.",
      encryptedInTransit: true,
    },
    reviewerAccess: {
      source: "docs/PLAY_REVIEWER_ACCESS.md",
      required: true,
      phoneNumber: "+16505550101",
      smsCode: "123456",
      displayName: "Play Reviewer",
      userId: "play_reviewer_001",
      paymentRequired: false,
      externalMembershipRequired: false,
      copyPasteInstructions:
        "Verbal requires phone sign-in. Use +16505550101 with verification code 123456. If profile setup appears, use display name Play Reviewer and user ID play_reviewer_001. No payment, subscription, invitation, or external membership is required.",
    },
    appContentWorksheet: {
      source: "docs/PLAY_APP_CONTENT_WORKSHEET.md",
      generatedAnswers:
        "artifacts/play-console/verbal-app-content-answers-latest.md",
      copySheet:
        "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
      appAccess: "Phone sign-in required; provide reviewer test credentials.",
      ads:
        "Select No unless a production ad SDK or production ad placement is enabled in the exact submitted AAB.",
      targetAudience:
        "Use adult-oriented target ages for internal testing / early closed beta until youth policy review is complete.",
      contentRating:
        "Communication app with user-generated messaging, voice content, optional location sharing, open-chat/link sharing if enabled, and report/block controls.",
      sensitivePermissions:
        "Microphone, notifications, contacts, location, camera/photos/files only when their related user-facing features are enabled.",
    },
    screenshotsNeeded: [
      "Sign-in and required policy consent",
      "Home message list",
      "Direct chat with voice transcript",
      "Voice message playback",
      "Calendar monthly view",
      "Calendar voice event creation",
      "Invite link or QR",
      "Report/block safety flow",
    ],
    screenshotCandidates: listScreenshotCandidates(),
    generatedStoreAssets: listGeneratedStoreAssets(),
    validationArtifacts: {
      latestLaunchReadiness: latestArtifact("launch-readiness-*.json"),
      latestLaunchGate: latestArtifact("launch-gate-*.json"),
      latestManualLaunchEvidence: existingArtifact("artifacts/launch-manual-evidence.json") ||
        existingArtifact("artifacts/launch-manual-evidence.template.json"),
      latestProductionE2e: latestArtifact("production-e2e-smoke-*.json"),
      latestAudioRetention: latestArtifact("audio-retention-*.json"),
      latestAndroidReleaseVerification: latestArtifact("android-release-verification-*.json"),
    },
    androidReleaseVerification: {
      guide: "docs/ANDROID_RELEASE_VERIFICATION.md",
      script: "scripts/verify-android-release-artifact.ps1",
      latestSummary: "artifacts/android-release-verification-latest.json",
      command:
        "npm run verify:android-release",
    },
    realDeviceQa: {
      guide: "docs/ANDROID_REAL_DEVICE_QA.md",
      script: "scripts/run-android-real-device-qa.ps1",
      latestSummary: "artifacts/android-real-device-qa-latest.json",
      command:
        ".\\scripts\\run-android-real-device-qa.ps1 -Interactive",
    },
    fcmRealDeviceQa: {
      guide: "docs/FCM_REAL_DEVICE_QA.md",
      script: "scripts/run-fcm-real-device-qa.ps1",
      latestSummary: "artifacts/fcm-real-device-latest.json",
      command:
        ".\\scripts\\run-fcm-real-device-qa.ps1",
    },
    manualStepsRemaining: buildManualStepsRemaining(),
  };

  writeJson(jsonPath, pack);
  writeJson(latestJsonPath, pack);
  fs.writeFileSync(mdPath, renderMarkdown(pack), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(pack), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
        aabSha256: release.sha256,
      },
      null,
      2,
    ),
  );
}

function buildManualStepsRemaining() {
  const evidence = readJsonIfExists(
    path.join(repoRoot, "artifacts", "launch-manual-evidence.json"),
  );
  const playConsole = evidence?.playConsole || {};
  const realDevice = evidence?.realDevice || {};
  const steps = ["Run npm run verify:preinternal immediately before upload."];

  if (!playConsole.appCreated?.done) {
    steps.push(
      "Create Google Play Console app record.",
      "Record app creation with npm run record:launch-evidence -- play-app-created --created-at now --console-url <https-url>.",
    );
  }
  if (!playConsole.internalTestingUpload?.done) {
    steps.push(
      "Upload dist/android/app-release.aab to Internal testing.",
      "Record Internal testing upload with npm run record:launch-evidence -- internal-testing-upload --uploaded-at now --tester-group <email-or-group>.",
      "Add internal tester email or Google Group.",
    );
  }
  if (!playConsole.appContentSubmitted?.done) {
    steps.push(
      "Complete Data Safety, content rating, target audience, ads, and app access declarations.",
      "Record App content submission with npm run record:app-content-submitted.",
    );
  }
  if (!playConsole.preLaunchReportReviewed?.done) {
    steps.push(
      "Review Google Play Pre-launch report after it is generated, then record it with npm run record:prelaunch-reviewed -- --report-url <https-url>.",
    );
  }
  if (!playConsole.closedTestingCompleted?.done) {
    steps.push(
      "Complete closed testing if Play Console requires it, then record it with npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>.",
    );
  }
  if (!realDevice.e2e?.done) {
    steps.push(
      "Run real-device SMS and microphone/STT QA.",
      "Record real-device E2E evidence with npm run record:real-device-e2e.",
    );
  }
  if (!realDevice.fcm?.done) {
    steps.push(
      "Run FCM foreground/background/terminated/lock-screen QA with scripts/run-fcm-real-device-qa.ps1.",
      "Record FCM evidence with npm run record:fcm-real-device.",
    );
  }

  steps.push(
    "Run npm run verify:launch-evidence after recording evidence.",
    "Run npm run report:launch-gate and confirm Internal testing upload is allowed and public exposure remains blocked until all external evidence is complete.",
  );
  return steps;
}

function getAndroidIdentity() {
  const gradle = readText(
    path.join(repoRoot, "apps", "mobile", "android", "app", "build.gradle.kts"),
  );
  const googleServices = JSON.parse(
    readText(
      path.join(repoRoot, "apps", "mobile", "android", "app", "google-services.json"),
    ),
  );
  return {
    applicationId: /applicationId\s*=\s*"([^"]+)"/.exec(gradle)?.[1] || "",
    namespace: /namespace\s*=\s*"([^"]+)"/.exec(gradle)?.[1] || "",
    firebasePackage:
      googleServices.client?.[0]?.client_info?.android_client_info?.package_name || "",
    firebaseAppId: googleServices.client?.[0]?.client_info?.mobilesdk_app_id || "",
  };
}

function getReleaseArtifact() {
  const aabPath = path.join(repoRoot, "dist", "android", "app-release.aab");
  const buffer = fs.readFileSync(aabPath);
  const stat = fs.statSync(aabPath);
  return {
    path: "dist/android/app-release.aab",
    bytes: stat.size,
    sha256: crypto.createHash("sha256").update(buffer).digest("hex"),
    lastModified: stat.mtime.toISOString(),
  };
}

function readListing(locale) {
  const dir = path.join(repoRoot, "artifacts", "store", "google-play", locale);
  return {
    shortDescription: readText(path.join(dir, "short-description.txt")).trim(),
    fullDescription: readText(path.join(dir, "full-description.txt")).trim(),
    internalReleaseNotes: readText(path.join(dir, "release-notes-internal.txt")).trim(),
  };
}

function assertReadableStoreListing(storeListing) {
  for (const [field, value] of Object.entries(storeListing.koKR)) {
    if (hasMojibake(value) || hangulCount(value) < 5) {
      throw new Error(`Korean store listing text is not readable: koKR.${field}`);
    }
  }
  for (const [field, value] of Object.entries(storeListing.enUS)) {
    if (hasMojibake(value) || value.trim().length < 10) {
      throw new Error(`English store listing text is not readable: enUS.${field}`);
    }
  }
}

function hasMojibake(value) {
  return /[\uFFFD]|뚯|꽦|諛|硫|怨|媛|鍮|蹂|濡|묒|쒖|꾩|ㅽ/.test(value);
}

function hangulCount(value) {
  return (value.match(/[가-힣]/g) || []).length;
}

function renderMarkdown(pack) {
  return `# Verbal Google Play Console Pack

Generated: ${pack.generatedAt}

## App

- App name: ${pack.app.name}
- Default language: ${pack.app.defaultLanguage}
- Type: ${pack.app.type}
- Category: ${pack.app.category}
- Pricing: ${pack.app.pricing}
- Package name: \`${pack.app.packageName}\`
- Firebase project: \`${pack.app.firebaseProjectId}\`
- Firebase Android App ID: \`${pack.app.firebaseAndroidAppId}\`

## Release Artifact

- AAB: \`${pack.release.path}\`
- Size: ${pack.release.bytes} bytes
- SHA-256: \`${pack.release.sha256}\`
- Last modified: ${pack.release.lastModified}

## Policy URLs

- Website: ${pack.policyUrls.website}
- Privacy Policy: ${pack.policyUrls.privacyPolicy}
- Terms of Service: ${pack.policyUrls.termsOfService}
- Community Guidelines: ${pack.policyUrls.communityGuidelines}
- Account Deletion: ${pack.policyUrls.accountDeletion}
- Data Deletion: ${pack.policyUrls.dataDeletion}

## Support

- Support email: ${pack.support.email}
- Inbound routing: ${pack.support.inboundProvider} -> ${pack.support.routedTo}
- Outbound sending: ${pack.support.outboundProvider}

## Korean Store Listing

Short description:

\`\`\`text
${pack.storeListing.koKR.shortDescription}
\`\`\`

Full description:

\`\`\`text
${pack.storeListing.koKR.fullDescription}
\`\`\`

Internal release notes:

\`\`\`text
${pack.storeListing.koKR.internalReleaseNotes}
\`\`\`

## English Store Listing

Short description:

\`\`\`text
${pack.storeListing.enUS.shortDescription}
\`\`\`

Full description:

\`\`\`text
${pack.storeListing.enUS.fullDescription}
\`\`\`

Internal release notes:

\`\`\`text
${pack.storeListing.enUS.internalReleaseNotes}
\`\`\`

## Data Safety Summary

- Source: \`${pack.dataSafetyDraft.source}\`
- Collected data: ${pack.dataSafetyDraft.collectedData}
- Third-party processing: ${pack.dataSafetyDraft.thirdPartyProcessing}
- Deletion mechanism: ${pack.dataSafetyDraft.deletionMechanism}
- Encrypted in transit: ${pack.dataSafetyDraft.encryptedInTransit ? "Yes" : "No"}

## Reviewer Access

- Source: \`${pack.reviewerAccess.source}\`
- Sign-in required: ${pack.reviewerAccess.required ? "Yes" : "No"}
- Test phone number: \`${pack.reviewerAccess.phoneNumber}\`
- Verification code: \`${pack.reviewerAccess.smsCode}\`
- Test display name: \`${pack.reviewerAccess.displayName}\`
- Test user ID: \`${pack.reviewerAccess.userId}\`
- Payment required: ${pack.reviewerAccess.paymentRequired ? "Yes" : "No"}
- External membership required: ${pack.reviewerAccess.externalMembershipRequired ? "Yes" : "No"}

Copy/paste summary:

\`\`\`text
${pack.reviewerAccess.copyPasteInstructions}
\`\`\`

## App Content Worksheet

- Source: \`${pack.appContentWorksheet.source}\`
- Generated answers: \`${pack.appContentWorksheet.generatedAnswers}\`
- Copy sheet: \`${pack.appContentWorksheet.copySheet}\`
- App access: ${pack.appContentWorksheet.appAccess}
- Ads: ${pack.appContentWorksheet.ads}
- Target audience: ${pack.appContentWorksheet.targetAudience}
- Content rating: ${pack.appContentWorksheet.contentRating}
- Sensitive permissions: ${pack.appContentWorksheet.sensitivePermissions}

## Screenshots Needed

${pack.screenshotsNeeded.map((item) => `- ${item}`).join("\n")}

## Screenshot Candidates

${pack.screenshotCandidates.length > 0 ? pack.screenshotCandidates.map((item) => `- \`${item}\``).join("\n") : "- No screenshot candidates found under `dist/screenshots`."}

## Generated Store Assets

${pack.generatedStoreAssets.length > 0 ? pack.generatedStoreAssets.map((item) => `- \`${item}\``).join("\n") : "- Run `npm run prepare:play-store-assets` before using this pack."}

## Validation Artifacts

- Latest launch readiness: ${pack.validationArtifacts.latestLaunchReadiness ? `\`${pack.validationArtifacts.latestLaunchReadiness}\`` : "Not found"}
- Latest launch gate: ${pack.validationArtifacts.latestLaunchGate ? `\`${pack.validationArtifacts.latestLaunchGate}\`` : "Not found"}
- Latest manual launch evidence: ${pack.validationArtifacts.latestManualLaunchEvidence ? `\`${pack.validationArtifacts.latestManualLaunchEvidence}\`` : "Not found"}
- Latest production E2E: ${pack.validationArtifacts.latestProductionE2e ? `\`${pack.validationArtifacts.latestProductionE2e}\`` : "Not found"}
- Latest audio retention: ${pack.validationArtifacts.latestAudioRetention ? `\`${pack.validationArtifacts.latestAudioRetention}\`` : "Not found"}
- Latest Android release verification: ${pack.validationArtifacts.latestAndroidReleaseVerification ? `\`${pack.validationArtifacts.latestAndroidReleaseVerification}\`` : "Not found"}

## Android Release Verification

- Guide: \`${pack.androidReleaseVerification.guide}\`
- Script: \`${pack.androidReleaseVerification.script}\`
- Latest summary target: \`${pack.androidReleaseVerification.latestSummary}\`
- Command: \`${pack.androidReleaseVerification.command}\`

## Real Device QA

- Guide: \`${pack.realDeviceQa.guide}\`
- Script: \`${pack.realDeviceQa.script}\`
- Latest summary target: \`${pack.realDeviceQa.latestSummary}\`
- Interactive command: \`${pack.realDeviceQa.command}\`

## FCM Real Device QA

- Guide: \`${pack.fcmRealDeviceQa.guide}\`
- Script: \`${pack.fcmRealDeviceQa.script}\`
- Latest summary target: \`${pack.fcmRealDeviceQa.latestSummary}\`
- Command: \`${pack.fcmRealDeviceQa.command}\`

## Manual Steps Remaining

${pack.manualStepsRemaining.map((item) => `- ${item}`).join("\n")}
`;
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
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

function listScreenshotCandidates() {
  const dir = path.join(repoRoot, "dist", "screenshots");
  if (!fs.existsSync(dir)) {
    return [];
  }
  return fs
    .readdirSync(dir)
    .filter((file) => /\.(png|jpe?g|webp)$/i.test(file))
    .sort()
    .map((file) => path.posix.join("dist/screenshots", file));
}

function listGeneratedStoreAssets() {
  const dir = path.join(repoRoot, "artifacts", "store", "google-play", "assets");
  if (!fs.existsSync(dir)) {
    return [];
  }
  const files = [];
  walk(dir, files);
  return files
    .filter((file) => /\.(png|jpe?g|webp|json)$/i.test(file))
    .sort()
    .map((file) => path.relative(repoRoot, file).replace(/\\/g, "/"));
}

function latestArtifact(pattern) {
  const [prefix, suffix] = pattern.split("*");
  const dir = path.join(repoRoot, "artifacts");
  if (!fs.existsSync(dir)) {
    return "";
  }
  const matches = fs
    .readdirSync(dir, {withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => name.startsWith(prefix) && name.endsWith(suffix))
    .map((name) => {
      const fullPath = path.join(dir, name);
      return {name, mtimeMs: fs.statSync(fullPath).mtimeMs};
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return matches[0] ? path.posix.join("artifacts", matches[0].name) : "";
}

function existingArtifact(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath)) ? relativePath : "";
}

function walk(dir, files) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, files);
    } else {
      files.push(fullPath);
    }
  }
}
