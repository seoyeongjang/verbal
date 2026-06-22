const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const outputDir = path.join(repoRoot, "artifacts", "play-console");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(outputDir, `verbal-app-content-answers-${runId}.json`);
const mdPath = path.join(outputDir, `verbal-app-content-answers-${runId}.md`);
const latestJsonPath = path.join(outputDir, "verbal-app-content-answers-latest.json");
const latestMdPath = path.join(outputDir, "verbal-app-content-answers-latest.md");

main();

function main() {
  fs.mkdirSync(outputDir, {recursive: true});
  const answers = buildAnswers();
  writeJson(jsonPath, answers);
  writeJson(latestJsonPath, answers);
  fs.writeFileSync(mdPath, renderMarkdown(answers), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(answers), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
        nextConsoleSection: answers.nextConsoleSection,
      },
      null,
      2,
    ),
  );
}

function buildAnswers() {
  return {
    generatedAt: new Date().toISOString(),
    nextConsoleSection: "Policy and programs > App content",
    appIdentity: {
      appName: "Verbal",
      packageName: "com.voicebeta.verbal",
      releaseTrack: "Internal testing",
      releaseVersion: "1 (1.0.0)",
      supportEmail: "support@verbal.chat",
    },
    policyUrls: {
      privacyPolicy: "https://verbal.chat/privacy",
      termsOfService: "https://verbal.chat/terms",
      communityGuidelines: "https://verbal.chat/community-guidelines",
      accountDeletion: "https://verbal.chat/account/delete",
      dataDeletion: "https://verbal.chat/data-deletion",
      website: "https://verbal.chat",
    },
    appAccess: {
      answer: "All or some functionality is restricted",
      signInRequired: true,
      instructions:
        "Verbal requires phone sign-in. Use +16505550101 with verification code 123456. If profile setup appears, use display name Play Reviewer and user ID play_reviewer_001. No payment, subscription, invitation, or external membership is required.",
      testPhoneNumber: "+16505550101",
      testVerificationCode: "123456",
      testDisplayName: "Play Reviewer",
      testUserId: "play_reviewer_001",
    },
    ads: {
      answer: "No",
      condition:
        "Use No only if the submitted AAB has no production ad SDK and no real ad placement enabled.",
      caveat:
        "If a production ad SDK, native ad, banner, interstitial, rewarded ad, or sponsored placement is enabled in the submitted AAB, change this answer to Yes.",
    },
    contentRating: {
      category: "Communication / Social",
      hasUserGeneratedContent: true,
      hasMessagingBetweenUsers: true,
      hasVoiceContent: true,
      hasOpenChatOrInviteLinks: true,
      hasLocationSharing: true,
      hasPurchases: false,
      hasGambling: false,
      hasNews: false,
      hasGovernment: false,
      hasHealthOrMedical: false,
      hasFinancialFeatures: false,
      safetyControls:
        "Report, block, leave room, safety center, community guidelines, and support handling are provided.",
    },
    targetAudience: {
      recommendedForInitialRelease:
        "Select adult age groups only for internal testing / early closed beta until youth policy, moderation, and legal review are completed.",
      teensCaveat:
        "If Verbal is intentionally opened to teens, complete a separate youth safety review before selecting teen age groups.",
    },
    sensitivePermissions: [
      {
        permission: "Microphone",
        userFacingFeature: "Voice message recording and voice calendar input",
        optional: false,
      },
      {
        permission: "Notifications",
        userFacingFeature: "Message push notifications and calendar reminders",
        optional: true,
      },
      {
        permission: "Location",
        userFacingFeature: "User-initiated location sharing",
        optional: true,
      },
      {
        permission: "Camera / Photos / Files",
        userFacingFeature: "User-initiated image, media, and file attachments",
        optional: true,
      },
      {
        permission: "Contacts",
        userFacingFeature: "Friend/contact discovery only if contact sync is enabled",
        optional: true,
      },
    ],
    dataSafety: {
      encryptedInTransit: true,
      usersCanRequestDeletion: true,
      deletionUrls: {
        accountDeletion: "https://verbal.chat/account/delete",
        dataDeletion: "https://verbal.chat/data-deletion",
      },
      consoleQuickAnswers: [
        quickAnswer("Does the app collect or share user data?", "Yes"),
        quickAnswer("Is all user data encrypted in transit?", "Yes"),
        quickAnswer("Can users request that their data be deleted?", "Yes"),
        quickAnswer("Does the app have an account deletion URL?", "Yes"),
        quickAnswer("Does the app independently verify user identity before deletion?", "Yes, through signed-in app account state or support verification for email requests"),
        quickAnswer("Does the app collect data for advertising?", "No for the current uploaded AAB"),
        quickAnswer("Does the app share data with third parties?", "Yes only for service-provider processing: Deepgram voice STT and Google Firebase/Cloud infrastructure"),
        quickAnswer("Is data collection optional where possible?", "Yes for voice recordings, media/files, location, calendar events, notifications, crash diagnostics, and future contact sync; account, messaging, safety, and service identifiers are required for core functionality"),
      ],
      thirdPartyProcessing: [
        "Firebase / Google Cloud for authentication, Firestore, Storage, Functions, Analytics, Crashlytics, and FCM.",
        "Deepgram for user-requested voice speech-to-text processing.",
      ],
      dataTypes: [
        dataType("Phone number", true, false, "Account creation, login, abuse prevention", true),
        dataType("User IDs", true, false, "Profile, handles, chat membership", true),
        dataType("Name/profile text", true, false, "Profile display in chats", true),
        dataType("Text messages", true, false, "Messaging and user-requested delivery", true),
        dataType(
          "Voice recordings",
          true,
          true,
          "Speech-to-text and voice message delivery through Deepgram processing",
          false,
        ),
        dataType("Voice transcripts", true, false, "Message display and search", true),
        dataType("Photos/files", true, false, "User-requested attachment delivery", false),
        dataType("Location", true, false, "User-requested location sharing", false),
        dataType("Calendar events/reminders", true, false, "User-requested calendar scheduling and reminders", false),
        dataType("Safety reports/moderation metadata", true, false, "Report handling, abuse prevention, and service safety", true),
        dataType("Contacts", false, false, "Not collected unless contact sync is enabled", false),
        dataType("Device or other IDs", true, false, "FCM push tokens and service operation", true),
        dataType("App interactions", true, false, "Usage monitoring, reliability, and cost monitoring", true),
        dataType("Crash logs/diagnostics", true, false, "Reliability and debugging", false),
      ],
      detailMatrix: [
        dataSafetyDetail("Personal info", "Phone number", "Yes", "No", "Yes", "App functionality, account management, fraud prevention, security", "Deleted or de-identified through account deletion flow"),
        dataSafetyDetail("Personal info", "User IDs", "Yes", "No", "Yes", "App functionality, account management, chat membership", "Deleted or de-identified through account deletion flow"),
        dataSafetyDetail("Personal info", "Name / profile text", "Yes", "No", "Yes", "App functionality, profile display, communication", "Deleted or de-identified through account deletion flow"),
        dataSafetyDetail("Messages", "Text messages", "Yes", "No", "Yes", "App functionality, user-requested message delivery", "User can delete messages; account deletion may anonymize retained conversation records"),
        dataSafetyDetail("Audio", "Voice recordings", "Yes", "Yes, service-provider processing by Deepgram", "No", "App functionality, speech-to-text, voice message delivery", "Audio expires by retention policy; transcript may remain for chat history and search"),
        dataSafetyDetail("Messages", "Voice transcripts", "Yes", "No", "Yes for voice messaging", "App functionality, accessibility, message display, search", "User can delete messages; account deletion may anonymize retained conversation records"),
        dataSafetyDetail("Photos and videos / Files and docs", "Photos, media, and files", "Yes", "No", "No", "App functionality, user-requested attachment delivery", "User can delete sent messages or request account/data deletion"),
        dataSafetyDetail("Location", "Approximate/precise location when shared", "Yes", "No", "No", "App functionality, user-requested location sharing", "User can delete sent messages or request account/data deletion"),
        dataSafetyDetail("Calendar", "Calendar events and reminders inside Verbal", "Yes", "No", "No", "App functionality, user-requested schedule creation and reminders", "User can update/delete calendar events or request account/data deletion"),
        dataSafetyDetail("App activity", "Safety reports and moderation metadata", "Yes", "No", "Yes for safety features", "Fraud prevention, security, compliance, abuse handling", "May be retained as needed for safety, legal, and abuse-prevention obligations"),
        dataSafetyDetail("Device or other IDs", "FCM tokens and device/service identifiers", "Yes", "No", "Yes", "App functionality, notifications, security, service operation", "Removed or rotated when no longer needed or on account deletion where applicable"),
        dataSafetyDetail("App activity", "App interactions", "Yes", "No", "Yes", "Analytics, reliability, cost monitoring, product improvement", "Aggregated or deleted according to retention and account deletion policy"),
        dataSafetyDetail("App info and performance", "Crash logs and diagnostics", "Yes", "No", "No", "Crash analysis, reliability, debugging", "Retained according to Firebase/Crashlytics diagnostic retention settings"),
        dataSafetyDetail("Contacts", "Contacts", "No", "No", "No", "Not collected in the current submitted build unless contact sync is enabled", "Not applicable"),
      ],
    },
    userGeneratedContent: {
      present: true,
      policyUrl: "https://verbal.chat/community-guidelines",
      moderationControls: [
        "Report message/user/chat",
        "Block user",
        "Leave room",
        "Request message controls",
        "Safety center and support handling",
      ],
    },
    declarations: {
      news: false,
      government: false,
      covid19: false,
      health: false,
      financial: false,
      gambling: false,
    },
    storeListing: {
      appCategory: "Communication / social messaging",
      contactEmail: "support@verbal.chat",
      website: "https://verbal.chat",
      shortDescriptionSource: "artifacts/store/google-play/ko-KR/short-description.txt",
      fullDescriptionSource: "artifacts/store/google-play/ko-KR/full-description.txt",
      appIconSource: "artifacts/store/google-play/assets/app-icon-512.png",
      featureGraphicSource: "artifacts/store/google-play/assets/feature-graphic-1024x500.png",
      screenshotSource: "artifacts/store/google-play/assets/phone-screenshots",
    },
    consoleSections: [
      consoleSection(
        "Privacy Policy",
        "개인정보처리방침",
        "Provide privacy policy URL",
        "https://verbal.chat/privacy",
        "--confirm-privacy-policy",
      ),
      consoleSection(
        "App Access",
        "앱 액세스",
        "Select restricted access and paste reviewer sign-in instructions",
        "Phone +16505550101 / code 123456 / profile Play Reviewer / play_reviewer_001",
        "--confirm-app-access",
      ),
      consoleSection(
        "Ads",
        "광고",
        "Select No for this uploaded AAB unless a real ad SDK or production ad placement is enabled",
        "No",
        "--confirm-ads",
      ),
      consoleSection(
        "Data Safety",
        "데이터 보안",
        "Enter collected/shared data, security practices, deletion support, Firebase/Deepgram processing",
        "Use the Data Safety table below and docs/GOOGLE_PLAY_DATA_SAFETY.md",
        "--confirm-data-safety",
      ),
      consoleSection(
        "Account Deletion",
        "계정 삭제",
        "Confirm in-app deletion path and public web deletion URL",
        "https://verbal.chat/account/delete",
        "--confirm-account-deletion",
      ),
      consoleSection(
        "Data Deletion",
        "데이터 삭제",
        "Confirm user deletion request support and data deletion explanation URL",
        "https://verbal.chat/data-deletion",
        "--confirm-data-deletion",
      ),
      consoleSection(
        "Content Rating",
        "콘텐츠 등급",
        "Answer as communication/social app with UGC, messaging, voice, open-chat links, and optional location sharing",
        "No purchases, gambling, news, government, health, finance, or COVID-19 scope",
        "--confirm-content-rating",
      ),
      consoleSection(
        "Target Audience",
        "타겟 사용자",
        "Select adult age groups for internal testing / early closed beta until youth policy is reviewed",
        "Adult-oriented initial testing",
        "--confirm-target-audience",
      ),
      consoleSection(
        "Sensitive Permissions",
        "민감한 권한",
        "Explain microphone, notifications, location, camera/photos/files, and contacts only by user-facing features",
        "Microphone is required for voice messaging and voice calendar input; other permissions are optional/user-initiated",
        "--confirm-sensitive-permissions",
      ),
      consoleSection(
        "UGC / User Content",
        "사용자 제작 콘텐츠",
        "Declare UGC and provide report/block/leave room/safety center/community policy controls",
        "https://verbal.chat/community-guidelines",
        "--confirm-ugc",
      ),
      consoleSection(
        "Government App",
        "정부 앱",
        "Select No because Verbal is not built by or for a government entity",
        "No",
        "--confirm-government-app",
      ),
      consoleSection(
        "Financial Features",
        "금융 기능",
        "Select No because Verbal does not provide financial products, transactions, lending, investing, or insurance",
        "No",
        "--confirm-financial-features",
      ),
      consoleSection(
        "Health",
        "건강",
        "Select No because Verbal does not provide health, medical, diagnosis, treatment, or wellness claims",
        "No",
        "--confirm-health",
      ),
      consoleSection(
        "App Category And Contact Details",
        "앱 카테고리 선택 및 연락처 세부정보 제공",
        "Choose communication/social messaging category and enter public support contact details",
        "Category: Communication / social messaging; email: support@verbal.chat; website: https://verbal.chat",
        "--confirm-app-category-contact",
      ),
      consoleSection(
        "Store Listing",
        "스토어 등록정보 설정",
        "Enter store listing text and upload prepared app icon, feature graphic, and phone screenshots",
        "Use artifacts/store/google-play/ko-KR and artifacts/store/google-play/assets",
        "--confirm-store-listing",
      ),
    ],
    recordCommand:
      "npm run record:app-content-submitted",
  };
}

function consoleSection(name, koreanName, action, value, evidenceFlag) {
  return {name, koreanName, action, value, evidenceFlag};
}

function quickAnswer(question, answer) {
  return {question, answer};
}

function dataType(name, collected, shared, purpose, required) {
  return {name, collected, shared, purpose, required};
}

function dataSafetyDetail(category, dataType, collected, shared, required, purposes, deletionHandling) {
  return {category, dataType, collected, shared, required, purposes, deletionHandling};
}

function renderMarkdown(answers) {
  return `# Verbal App Content And Data Safety Answers

Generated: ${answers.generatedAt}

Use this file while filling Google Play Console > ${answers.nextConsoleSection}.
Final answers must match the exact AAB uploaded to the internal testing track.

## App Identity

- App name: ${answers.appIdentity.appName}
- Package name: \`${answers.appIdentity.packageName}\`
- Release track: ${answers.appIdentity.releaseTrack}
- Release version: ${answers.appIdentity.releaseVersion}
- Support email: ${answers.appIdentity.supportEmail}

## Policy URLs

- Privacy Policy: ${answers.policyUrls.privacyPolicy}
- Terms of Service: ${answers.policyUrls.termsOfService}
- Community Guidelines: ${answers.policyUrls.communityGuidelines}
- Account Deletion: ${answers.policyUrls.accountDeletion}
- Data Deletion: ${answers.policyUrls.dataDeletion}
- Website: ${answers.policyUrls.website}

## Section-by-section Console Flow

Use this table in Google Play Console > Policy and programs > App content.
Save every section before recording evidence.

| Console section | Korean UI label | What to enter | Exact value/source | Evidence flag |
|---|---|---|---|---|
${answers.consoleSections
  .map(
    (section) =>
      `| ${section.name} | ${section.koreanName} | ${section.action} | ${section.value} | \`${section.evidenceFlag}\` |`,
  )
  .join("\n")}

Recommended order:

${answers.consoleSections
  .map((section, index) => `${index + 1}. ${section.koreanName} / ${section.name}`)
  .join("\n")}

## App Access

- Answer: ${answers.appAccess.answer}
- Sign-in required: ${answers.appAccess.signInRequired ? "Yes" : "No"}
- Test phone number: \`${answers.appAccess.testPhoneNumber}\`
- Verification code: \`${answers.appAccess.testVerificationCode}\`
- Test display name: \`${answers.appAccess.testDisplayName}\`
- Test user ID: \`${answers.appAccess.testUserId}\`

Paste this reviewer instruction:

\`\`\`text
${answers.appAccess.instructions}
\`\`\`

## Ads

- Answer: ${answers.ads.answer}
- Condition: ${answers.ads.condition}
- Caveat: ${answers.ads.caveat}

## Data Safety

- Data encrypted in transit: ${answers.dataSafety.encryptedInTransit ? "Yes" : "No"}
- Users can request deletion: ${answers.dataSafety.usersCanRequestDeletion ? "Yes" : "No"}
- Account deletion URL: ${answers.dataSafety.deletionUrls.accountDeletion}
- Data deletion URL: ${answers.dataSafety.deletionUrls.dataDeletion}

Console quick answers:

| Console question | Answer |
|---|---|
${answers.dataSafety.consoleQuickAnswers
  .map((item) => `| ${item.question} | ${item.answer} |`)
  .join("\n")}

Third-party processing:

${answers.dataSafety.thirdPartyProcessing.map((item) => `- ${item}`).join("\n")}

Data types:

| Data type | Collected | Shared | Required | Purpose |
|---|---:|---:|---:|---|
${answers.dataSafety.dataTypes
  .map(
    (item) =>
      `| ${item.name} | ${yesNo(item.collected)} | ${yesNo(item.shared)} | ${yesNo(item.required)} | ${item.purpose} |`,
  )
  .join("\n")}

Detailed Play Console input matrix:

| Category | Data type | Collected | Shared | Required | Purposes | Deletion/retention handling |
|---|---|---:|---:|---:|---|---|
${answers.dataSafety.detailMatrix
  .map(
    (item) =>
      `| ${item.category} | ${item.dataType} | ${item.collected} | ${item.shared} | ${item.required} | ${item.purposes} | ${item.deletionHandling} |`,
  )
  .join("\n")}

## Content Rating

- Category: ${answers.contentRating.category}
- User-generated content: ${yesNo(answers.contentRating.hasUserGeneratedContent)}
- User messaging: ${yesNo(answers.contentRating.hasMessagingBetweenUsers)}
- Voice content: ${yesNo(answers.contentRating.hasVoiceContent)}
- Open chat / invite links: ${yesNo(answers.contentRating.hasOpenChatOrInviteLinks)}
- User-initiated location sharing: ${yesNo(answers.contentRating.hasLocationSharing)}
- Purchases: ${yesNo(answers.contentRating.hasPurchases)}
- Gambling: ${yesNo(answers.contentRating.hasGambling)}
- News: ${yesNo(answers.contentRating.hasNews)}
- Government: ${yesNo(answers.contentRating.hasGovernment)}
- Health/medical: ${yesNo(answers.contentRating.hasHealthOrMedical)}
- Financial features: ${yesNo(answers.contentRating.hasFinancialFeatures)}
- Safety controls: ${answers.contentRating.safetyControls}

## Target Audience

- Recommended initial selection: ${answers.targetAudience.recommendedForInitialRelease}
- Teens caveat: ${answers.targetAudience.teensCaveat}

## Sensitive Permissions

| Permission | User-facing feature | Optional |
|---|---|---:|
${answers.sensitivePermissions
  .map((item) => `| ${item.permission} | ${item.userFacingFeature} | ${yesNo(item.optional)} |`)
  .join("\n")}

## UGC And Safety

- UGC present: ${yesNo(answers.userGeneratedContent.present)}
- Policy URL: ${answers.userGeneratedContent.policyUrl}

Moderation controls:

${answers.userGeneratedContent.moderationControls.map((item) => `- ${item}`).join("\n")}

## Other Declarations

- News: ${yesNo(answers.declarations.news)}
- Government: ${yesNo(answers.declarations.government)}
- COVID-19: ${yesNo(answers.declarations.covid19)}
- Health: ${yesNo(answers.declarations.health)}
- Financial: ${yesNo(answers.declarations.financial)}
- Gambling: ${yesNo(answers.declarations.gambling)}

## App Category / Contact / Store Listing

- App category: ${answers.storeListing.appCategory}
- Contact email: ${answers.storeListing.contactEmail}
- Website: ${answers.storeListing.website}
- Short description source: \`${answers.storeListing.shortDescriptionSource}\`
- Full description source: \`${answers.storeListing.fullDescriptionSource}\`
- App icon source: \`${answers.storeListing.appIconSource}\`
- Feature graphic source: \`${answers.storeListing.featureGraphicSource}\`
- Phone screenshot source: \`${answers.storeListing.screenshotSource}\`

## Record Evidence After Saving

After every App content and Data Safety section is saved in Play Console:

\`\`\`powershell
${answers.recordCommand}
\`\`\`
`;
}

function yesNo(value) {
  return value ? "Yes" : "No";
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
