const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const resultPath = path.join(
  artifactDir,
  `launch-readiness-${runId}.json`,
);
const latestResultPath = path.join(artifactDir, "launch-readiness-latest.json");
const skipNetwork = process.argv.includes("--skip-network");

const checks = [];
const manualRequired = [
  {
    item: "Google Play Data Safety form completion",
    why: "Must be entered and confirmed in Play Console using the prepared draft.",
  },
  {
    item: "Google Play Pre-launch report review",
    why: "Generated only after Play Console upload; stability, performance, accessibility, screenshots, and blocking issues must be reviewed before public exposure.",
  },
  {
    item: "Google Play closed testing or production access readiness",
    why: "Some Play Console accounts must complete closed testing before production access; this must be recorded or explicitly marked not required.",
  },
  {
    item: "Android real-device E2E",
    why: "Real phone auth, microphone capture, STT quality, permissions, and native push cannot be fully proven locally.",
  },
  {
    item: "FCM foreground/background/terminated delivery",
    why: "Requires an installed app on a real Android device and notification-state testing.",
  },
  {
    item: "iOS APNs/TestFlight verification if iOS launch is in scope",
    why: "Requires Apple Developer/TestFlight setup and real iOS devices.",
  },
];

main().catch((error) => {
  checks.push({
    name: "unexpected_error",
    ok: false,
    detail: String(error?.stack || error),
  });
  writeResultAndExit();
});

async function main() {
  fs.mkdirSync(artifactDir, {recursive: true});

  checkAndroidIdentity();
  checkReleaseAab();
  checkPublicPages();
  checkStoreSubmissionPack();
  checkDataSafetyPack();
  checkRuntimeTelemetryWiring();
  checkPolicyConsentGate();
  checkVerificationScripts();
  await checkHostedUrls();

  writeResultAndExit();
}

function checkAndroidIdentity() {
  const gradlePath = path.join(
    repoRoot,
    "apps",
    "mobile",
    "android",
    "app",
    "build.gradle.kts",
  );
  const googleServicesPath = path.join(
    repoRoot,
    "apps",
    "mobile",
    "android",
    "app",
    "google-services.json",
  );
  const gradle = readText(gradlePath);
  const googleServices = JSON.parse(readText(googleServicesPath));
  const applicationId = /applicationId\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  const namespace = /namespace\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  const firebasePackage =
    googleServices.client?.[0]?.client_info?.android_client_info?.package_name;
  const appId = googleServices.client?.[0]?.client_info?.mobilesdk_app_id;

  addCheck("android_package_id_is_verbal", applicationId === "com.voicebeta.verbal", {
    applicationId,
  });
  addCheck("android_namespace_matches_package", namespace === applicationId, {
    namespace,
    applicationId,
  });
  addCheck("firebase_android_package_matches", firebasePackage === applicationId, {
    firebasePackage,
    applicationId,
  });
  addCheck("firebase_android_app_id_present", isNonEmptyString(appId), {appId});
}

function checkReleaseAab() {
  const aabPath = path.join(repoRoot, "dist", "android", "app-release.aab");
  const stat = safeStat(aabPath);
  addCheck("release_aab_exists", Boolean(stat), {
    path: relative(aabPath),
  });
  if (!stat) {
    return;
  }
  addCheck("release_aab_size_plausible", stat.size > 40 * 1024 * 1024, {
    bytes: stat.size,
  });

  const latestAppSource = latestMtime([
    path.join(repoRoot, "apps", "mobile", "lib"),
    path.join(repoRoot, "apps", "mobile", "android", "app", "build.gradle.kts"),
    path.join(repoRoot, "apps", "mobile", "android", "app", "google-services.json"),
    path.join(repoRoot, "apps", "mobile", "pubspec.yaml"),
  ]);
  addCheck(
    "release_aab_newer_than_app_sources",
    stat.mtimeMs >= latestAppSource.mtimeMs,
    {
      aabLastWriteTime: stat.mtime.toISOString(),
      latestAppSource: latestAppSource.path
        ? {
            path: relative(latestAppSource.path),
            lastWriteTime: new Date(latestAppSource.mtimeMs).toISOString(),
          }
        : null,
    },
  );
}

function checkPublicPages() {
  const publicFiles = [
    "public/index.html",
    "public/privacy/index.html",
    "public/terms/index.html",
    "public/community-guidelines/index.html",
    "public/account/delete/index.html",
    "public/data-deletion/index.html",
  ];
  for (const file of publicFiles) {
    const fullPath = path.join(repoRoot, file);
    addCheck(`public_file_exists:${file}`, Boolean(safeStat(fullPath)), {
      path: file,
    });
  }

  const accountDelete = readText(
    path.join(repoRoot, "public", "account", "delete", "index.html"),
  );
  const privacy = readText(
    path.join(repoRoot, "public", "privacy", "index.html"),
  );
  const terms = readText(
    path.join(repoRoot, "public", "terms", "index.html"),
  );
  const communityGuidelines = readText(
    path.join(repoRoot, "public", "community-guidelines", "index.html"),
  );
  const dataDeletion = readText(
    path.join(repoRoot, "public", "data-deletion", "index.html"),
  );
  const publicPageTexts = {
    privacy,
    terms,
    communityGuidelines,
    accountDelete,
    dataDeletion,
  };
  const internalOnlyPatterns = [
    "초안",
    "내부 테스트",
    "공개 출시 전",
    "최종 운영 전",
    "확정해야",
    "법무 검토",
    "Draft",
    "before public launch",
  ];
  for (const [name, text] of Object.entries(publicPageTexts)) {
    const matches = internalOnlyPatterns.filter((pattern) => text.includes(pattern));
    addCheck(`public_page_has_no_internal_draft_copy:${name}`, matches.length === 0, {
      matches,
    });
  }
  addCheck(
    "privacy_page_mentions_support_email",
    privacy.includes("support@verbal.chat"),
    {},
  );
  addCheck(
    "terms_page_mentions_support_email",
    terms.includes("support@verbal.chat"),
    {},
  );
  addCheck(
    "community_guidelines_page_mentions_support_email",
    communityGuidelines.includes("support@verbal.chat"),
    {},
  );
  addCheck(
    "account_delete_page_mentions_support_email",
    accountDelete.includes("support@verbal.chat"),
    {},
  );
  addCheck(
    "data_deletion_page_mentions_support_email",
    dataDeletion.includes("support@verbal.chat"),
    {},
  );
}

function checkStoreSubmissionPack() {
  const files = [
    "artifacts/store/google-play/ko-KR/short-description.txt",
    "artifacts/store/google-play/ko-KR/full-description.txt",
    "artifacts/store/google-play/ko-KR/release-notes-internal.txt",
    "artifacts/store/google-play/en-US/short-description.txt",
    "artifacts/store/google-play/en-US/full-description.txt",
    "artifacts/store/google-play/en-US/release-notes-internal.txt",
    "docs/GOOGLE_PLAY_SUBMISSION.md",
    "docs/ko/GOOGLE_PLAY_SUBMISSION.md",
    "docs/PLAY_CONSOLE_MANUAL_CHECKLIST.md",
    "docs/ko/PLAY_CONSOLE_MANUAL_CHECKLIST.md",
    "docs/PLAY_REVIEWER_ACCESS.md",
    "docs/ko/PLAY_REVIEWER_ACCESS.md",
    "docs/PLAY_APP_CONTENT_WORKSHEET.md",
    "docs/ko/PLAY_APP_CONTENT_WORKSHEET.md",
    "artifacts/play-console/verbal-app-content-answers-latest.md",
    "artifacts/play-console/verbal-app-content-copy-sheet-latest.html",
    "docs/CLOSED_TESTING_RUNBOOK.md",
    "docs/ko/CLOSED_TESTING_RUNBOOK.md",
    "docs/LAUNCH_GATE_REPORT.md",
    "docs/ko/LAUNCH_GATE_REPORT.md",
    "docs/LAUNCH_MANUAL_EVIDENCE.md",
    "docs/ko/LAUNCH_MANUAL_EVIDENCE.md",
    "docs/PREINTERNAL_RELEASE_CHECK.md",
    "docs/ko/PREINTERNAL_RELEASE_CHECK.md",
    "docs/LAUNCH_HANDOFF.md",
    "docs/ko/LAUNCH_HANDOFF.md",
    "docs/LAUNCH_STATUS.md",
    "docs/ko/LAUNCH_STATUS.md",
    "docs/LAUNCH_CONSISTENCY.md",
    "docs/ko/LAUNCH_CONSISTENCY.md",
    "docs/PUBLIC_RELEASE_GATE.md",
    "docs/ko/PUBLIC_RELEASE_GATE.md",
    "docs/ANDROID_RELEASE_VERIFICATION.md",
    "docs/ko/ANDROID_RELEASE_VERIFICATION.md",
    "docs/ANDROID_REAL_DEVICE_QA.md",
    "docs/ko/ANDROID_REAL_DEVICE_QA.md",
    "docs/FCM_REAL_DEVICE_QA.md",
    "docs/ko/FCM_REAL_DEVICE_QA.md",
    "scripts/verify-android-release-artifact.ps1",
    "scripts/run-android-real-device-qa.ps1",
    "scripts/run-fcm-real-device-qa.ps1",
    "functions/scripts/prepare-launch-evidence-template.js",
    "functions/scripts/record-launch-evidence.js",
    "functions/scripts/record-app-content-submitted.js",
    "functions/scripts/launch-evidence-utils.js",
    "functions/scripts/verify-launch-evidence.js",
    "functions/scripts/generate-play-console-pack.js",
    "functions/scripts/generate-app-content-answers.js",
    "functions/scripts/generate-app-content-copy-sheet.js",
    "functions/scripts/generate-launch-gate-report.js",
    "functions/scripts/generate-closed-testing-pack.js",
    "functions/scripts/generate-launch-handoff.js",
    "functions/scripts/generate-next-external-step-guide.js",
    "functions/scripts/generate-launch-status.js",
    "functions/scripts/verify-launch-consistency.js",
    "functions/scripts/verify-public-release-gate.js",
    "functions/scripts/run-preinternal-release-check.js",
  ];
  for (const file of files) {
    const fullPath = path.join(repoRoot, file);
    const stat = safeStat(fullPath);
    addCheck(`store_submission_file_ready:${file}`, Boolean(stat && stat.size > 0), {
      path: file,
      bytes: stat?.size || 0,
    });
  }

  const koreanStoreFiles = [
    "artifacts/store/google-play/ko-KR/short-description.txt",
    "artifacts/store/google-play/ko-KR/full-description.txt",
    "artifacts/store/google-play/ko-KR/release-notes-internal.txt",
  ];
  for (const file of koreanStoreFiles) {
    const text = stripBom(readText(path.join(repoRoot, file)));
    addCheck(`korean_store_listing_has_readable_hangul:${file}`, hangulCount(text) >= 5, {
      path: file,
      hangulCount: hangulCount(text),
    });
    addCheck(`korean_store_listing_has_no_mojibake:${file}`, !hasMojibake(text), {
      path: file,
    });
  }
  const koFullDescription = stripBom(readText(
    path.join(repoRoot, "artifacts", "store", "google-play", "ko-KR", "full-description.txt"),
  ));
  const enFullDescription = stripBom(readText(
    path.join(repoRoot, "artifacts", "store", "google-play", "en-US", "full-description.txt"),
  ));
  const staleVoiceReviewPatterns = [
    "확인 후 전송",
    "Review-before-send",
    "review-before-send",
  ];
  const combinedStoreDescription = `${koFullDescription}\n${enFullDescription}`;
  addCheck(
    "store_listing_has_no_stale_voice_review_mode_copy",
    !staleVoiceReviewPatterns.some((pattern) =>
      combinedStoreDescription.includes(pattern),
    ),
    {patterns: staleVoiceReviewPatterns},
  );
  addCheck(
    "store_listing_describes_voice_auto_send",
    koFullDescription.includes("자동 전송") &&
      enFullDescription.includes("Automatic voice sending"),
    {},
  );
  const homeScreen = readText(
    path.join(repoRoot, "apps", "mobile", "lib", "src", "ui", "home", "home_screen.dart"),
  );
  const chatScreen = readText(
    path.join(repoRoot, "apps", "mobile", "lib", "src", "ui", "chat", "chat_screen.dart"),
  );
  addCheck(
    "app_ui_has_no_voice_review_mode_toggle",
    !homeScreen.includes("기본 음성 전송 방식") &&
      !homeScreen.includes("변환된 음성을 확인 후 전송") &&
      !chatScreen.includes("확인 후 전송") &&
      !chatScreen.includes("SendMode.confirm"),
    {},
  );

  const reviewerAccess = readText(path.join(repoRoot, "docs", "PLAY_REVIEWER_ACCESS.md"));
  addCheck(
    "play_reviewer_access_has_test_phone",
    reviewerAccess.includes("+16505550101") && reviewerAccess.includes("123456"),
    {},
  );
  addCheck(
    "play_reviewer_access_has_profile_values",
    reviewerAccess.includes("Play Reviewer") &&
      reviewerAccess.includes("play_reviewer_001"),
    {},
  );
  addCheck(
    "play_reviewer_access_has_policy_urls",
    reviewerAccess.includes("https://verbal.chat/privacy") &&
      reviewerAccess.includes("https://verbal.chat/account/delete"),
    {},
  );

  const appContentWorksheet = readText(
    path.join(repoRoot, "docs", "PLAY_APP_CONTENT_WORKSHEET.md"),
  );
  addCheck(
    "play_app_content_worksheet_points_to_generated_answers",
    appContentWorksheet.includes("artifacts/play-console/verbal-app-content-answers-latest.md"),
    {},
  );
  addCheck(
    "play_app_content_worksheet_points_to_copy_sheet",
    appContentWorksheet.includes("artifacts/play-console/verbal-app-content-copy-sheet-latest.html"),
    {},
  );
  for (const section of [
    "App Access",
    "Ads",
    "Data Safety",
    "Data Deletion",
    "Target Audience",
    "Content Rating",
    "Sensitive Permissions",
    "UGC",
  ]) {
    addCheck(`play_app_content_worksheet_has_section:${section}`, appContentWorksheet.includes(section), {
      section,
    });
  }

  const screenshotDir = path.join(repoRoot, "dist", "screenshots");
  const screenshotCount = listFiles(screenshotDir)
    .filter((file) => /\.(png|jpe?g|webp)$/i.test(file))
    .length;
  addCheck("store_screenshot_candidates_present", screenshotCount >= 2, {
    path: relative(screenshotDir),
    count: screenshotCount,
  });

  const appContentAnswers = readText(
    path.join(repoRoot, "artifacts", "play-console", "verbal-app-content-answers-latest.md"),
  );
  addCheck(
    "app_content_answers_include_required_urls_and_reviewer_access",
    appContentAnswers.includes("https://verbal.chat/privacy") &&
      appContentAnswers.includes("https://verbal.chat/account/delete") &&
      appContentAnswers.includes("https://verbal.chat/data-deletion") &&
      appContentAnswers.includes("+16505550101") &&
      appContentAnswers.includes("123456"),
    {},
  );
  addCheck(
    "app_content_answers_include_data_safety_and_ugc",
    appContentAnswers.includes("Data encrypted in transit: Yes") &&
      appContentAnswers.includes("Voice recordings") &&
      appContentAnswers.includes("Deepgram") &&
      appContentAnswers.includes("Calendar events and reminders") &&
      appContentAnswers.includes("Safety reports and moderation metadata") &&
      appContentAnswers.includes("UGC present: Yes") &&
    appContentAnswers.includes("Report message/user/chat"),
    {},
  );
  addCheck(
    "app_content_answers_include_detailed_data_safety_matrix",
    appContentAnswers.includes("Detailed Play Console input matrix") &&
      appContentAnswers.includes("Deletion/retention handling") &&
      appContentAnswers.includes("service-provider processing by Deepgram") &&
      appContentAnswers.includes("Calendar events and reminders inside Verbal") &&
      appContentAnswers.includes("Safety reports and moderation metadata"),
    {},
  );
  addCheck(
    "app_content_answers_include_data_safety_quick_answers",
    appContentAnswers.includes("Console quick answers") &&
      appContentAnswers.includes("Does the app collect or share user data?") &&
      appContentAnswers.includes("Is all user data encrypted in transit?") &&
      appContentAnswers.includes("Can users request that their data be deleted?") &&
      appContentAnswers.includes("Does the app collect data for advertising?") &&
      appContentAnswers.includes("Does the app share data with third parties?"),
    {},
  );
  addCheck(
    "app_content_answers_include_section_by_section_console_flow",
    appContentAnswers.includes("## Section-by-section Console Flow") &&
      appContentAnswers.includes("Evidence flag") &&
      appContentAnswers.includes("--confirm-privacy-policy") &&
      appContentAnswers.includes("--confirm-app-access") &&
      appContentAnswers.includes("--confirm-data-safety") &&
      appContentAnswers.includes("--confirm-ugc") &&
      appContentAnswers.includes("--confirm-government-app") &&
      appContentAnswers.includes("--confirm-financial-features") &&
      appContentAnswers.includes("--confirm-health") &&
      appContentAnswers.includes("--confirm-app-category-contact") &&
      appContentAnswers.includes("--confirm-store-listing"),
    {},
  );
  addCheck(
    "app_content_answers_has_no_mojibake",
    !hasMojibake(appContentAnswers),
    {},
  );
  const expectedKoreanConsoleLabels = [
    "개인정보처리방침",
    "앱 액세스",
    "광고",
    "데이터 보안",
    "계정 삭제",
    "데이터 삭제",
    "콘텐츠 등급",
    "타겟 사용자",
    "민감한 권한",
    "사용자 제작 콘텐츠",
  ];
  for (const label of expectedKoreanConsoleLabels) {
    addCheck(
      `app_content_answers_has_korean_console_label:${label}`,
      appContentAnswers.includes(label),
      {label},
    );
  }

  const appContentCopySheet = readText(
    path.join(repoRoot, "artifacts", "play-console", "verbal-app-content-copy-sheet-latest.html"),
  );
  addCheck(
    "app_content_copy_sheet_has_copy_buttons",
    appContentCopySheet.includes("data-copy=") &&
      appContentCopySheet.includes("navigator.clipboard.writeText"),
    {},
  );
  addCheck(
    "app_content_copy_sheet_has_required_sections",
    appContentCopySheet.includes("Verbal Play Console App Content Copy Sheet") &&
      appContentCopySheet.includes("개인정보처리방침") &&
      appContentCopySheet.includes("앱 액세스") &&
      appContentCopySheet.includes("데이터 보안") &&
      appContentCopySheet.includes("정부 앱") &&
      appContentCopySheet.includes("스토어 등록정보 설정"),
    {},
  );
  addCheck(
    "app_content_copy_sheet_has_record_command",
    appContentCopySheet.includes("record:app-content-submitted"),
    {},
  );
  addCheck(
    "app_content_copy_sheet_has_no_mojibake",
    !hasMojibake(appContentCopySheet),
    {},
  );

  const generatedAssetDir = path.join(
    repoRoot,
    "artifacts",
    "store",
    "google-play",
    "assets",
  );
  const generatedAssets = [
    {
      file: "app-icon-512.png",
      width: 512,
      height: 512,
    },
    {
      file: "feature-graphic-1024x500.png",
      width: 1024,
      height: 500,
    },
  ];
  for (const asset of generatedAssets) {
    const fullPath = path.join(generatedAssetDir, asset.file);
    const dimensions = readPngDimensions(fullPath);
    addCheck(`play_store_asset_ready:${asset.file}`, Boolean(dimensions), {
      path: relative(fullPath),
      dimensions,
    });
    if (dimensions) {
      addCheck(
        `play_store_asset_dimensions:${asset.file}`,
        dimensions.width === asset.width && dimensions.height === asset.height,
        {
          expected: `${asset.width}x${asset.height}`,
          actual: `${dimensions.width}x${dimensions.height}`,
        },
      );
    }
  }

  const generatedPhoneScreenshots = listFiles(
    path.join(generatedAssetDir, "phone-screenshots"),
  ).filter((file) => /\.(png|jpe?g|webp)$/i.test(file));
  addCheck("play_store_phone_screenshots_ready", generatedPhoneScreenshots.length >= 2, {
    path: relative(path.join(generatedAssetDir, "phone-screenshots")),
    count: generatedPhoneScreenshots.length,
  });
  for (const screenshot of generatedPhoneScreenshots) {
    const dimensions = readPngDimensions(screenshot);
    addCheck(`play_store_phone_screenshot_dimensions:${path.basename(screenshot)}`, Boolean(
      dimensions &&
        dimensions.width >= 320 &&
        dimensions.height >= 320 &&
        Math.max(dimensions.width, dimensions.height) <=
          Math.min(dimensions.width, dimensions.height) * 2,
    ), {
      path: relative(screenshot),
      dimensions,
    });
  }
}

function checkDataSafetyPack() {
  const files = [
    "docs/GOOGLE_PLAY_DATA_SAFETY.md",
    "docs/ko/GOOGLE_PLAY_DATA_SAFETY.md",
    "docs/PRIVACY_POLICY.md",
    "docs/ko/PRIVACY_POLICY.md",
    "docs/TERMS_OF_SERVICE.md",
    "docs/ko/TERMS_OF_SERVICE.md",
    "docs/COMMUNITY_GUIDELINES.md",
    "docs/ko/COMMUNITY_GUIDELINES.md",
    "docs/DATA_DELETION_POLICY.md",
    "docs/ko/DATA_DELETION_POLICY.md",
  ];
  for (const file of files) {
    const fullPath = path.join(repoRoot, file);
    const stat = safeStat(fullPath);
    addCheck(`policy_document_ready:${file}`, Boolean(stat && stat.size > 0), {
      path: file,
      bytes: stat?.size || 0,
    });
  }
  const dataSafetyDoc = readText(path.join(repoRoot, "docs", "GOOGLE_PLAY_DATA_SAFETY.md"));
  const koDataSafetyDoc = readText(path.join(repoRoot, "docs", "ko", "GOOGLE_PLAY_DATA_SAFETY.md"));
  addCheck(
    "data_safety_docs_include_calendar_and_moderation_data",
    dataSafetyDoc.includes("Calendar events/reminders") &&
      dataSafetyDoc.includes("Safety reports/moderation metadata") &&
      koDataSafetyDoc.includes("캘린더 일정/리마인더") &&
      koDataSafetyDoc.includes("신고/안전 처리 메타데이터"),
    {},
  );
  addCheck(
    "data_safety_docs_include_detailed_play_console_matrix",
    dataSafetyDoc.includes("Detailed Play Console Input Matrix") &&
      dataSafetyDoc.includes("Deletion/retention handling") &&
      koDataSafetyDoc.includes("상세 Play Console 입력 매트릭스") &&
      koDataSafetyDoc.includes("Deletion/retention handling"),
    {},
  );
  addCheck(
    "data_safety_docs_include_quick_answers",
    dataSafetyDoc.includes("Quick answers") &&
      dataSafetyDoc.includes("Does the app collect or share user data?") &&
      dataSafetyDoc.includes("Does the app share data with third parties?") &&
      koDataSafetyDoc.includes("빠른 답변") &&
      koDataSafetyDoc.includes("앱이 사용자 데이터를 수집하거나 공유하나요?") &&
      koDataSafetyDoc.includes("앱이 제3자와 데이터를 공유하나요?"),
    {},
  );
}

function checkRuntimeTelemetryWiring() {
  const pubspec = readText(path.join(repoRoot, "apps", "mobile", "pubspec.yaml"));
  const main = readText(path.join(repoRoot, "apps", "mobile", "lib", "main.dart"));
  const telemetry = readText(
    path.join(repoRoot, "apps", "mobile", "lib", "src", "services", "telemetry_service.dart"),
  );
  addCheck("firebase_analytics_dependency_present", pubspec.includes("firebase_analytics:"), {});
  addCheck("firebase_crashlytics_dependency_present", pubspec.includes("firebase_crashlytics:"), {});
  addCheck("telemetry_configured_in_main", main.includes("AppTelemetry.configure"), {});
  addCheck("telemetry_service_exists", telemetry.includes("class AppTelemetry"), {});
}

function checkPolicyConsentGate() {
  const authScreen = readText(
    path.join(repoRoot, "apps", "mobile", "lib", "src", "ui", "auth", "auth_screen.dart"),
  );
  const backend = readText(
    path.join(repoRoot, "apps", "mobile", "lib", "src", "services", "firebase_backend.dart"),
  );
  const rules = readText(path.join(repoRoot, "firebase", "firestore.rules"));

  addCheck(
    "signup_policy_consent_ui_present",
    authScreen.includes("terms-consent-checkbox") &&
      authScreen.includes("privacy-consent-checkbox") &&
      authScreen.includes("community-consent-checkbox") &&
      authScreen.includes("_hasRequiredConsent"),
    {},
  );
  addCheck("signup_policy_consent_saved", backend.includes("savePolicyConsent"), {});
  addCheck("firestore_policy_consent_rules_present", rules.includes("validPolicyConsent"), {});
}

function checkVerificationScripts() {
  const packageJson = JSON.parse(readText(path.join(repoRoot, "functions", "package.json")));
  addCheck(
    "audio_retention_verifier_script_registered",
    Boolean(packageJson.scripts?.["verify:audio-retention"]),
    {},
  );
  addCheck(
    "audio_retention_prod_verifier_script_registered",
    Boolean(packageJson.scripts?.["verify:audio-retention:prod"]),
    {},
  );
  addCheck(
    "hosted_policy_url_verifier_script_registered",
    Boolean(packageJson.scripts?.["verify:hosted-policy-urls"]),
    {},
  );
  addCheck(
    "production_e2e_script_registered",
    Boolean(packageJson.scripts?.["smoke:prod-e2e"]),
    {},
  );
  addCheck(
    "android_release_verifier_script_registered",
    Boolean(packageJson.scripts?.["verify:android-release"]),
    {},
  );
  addCheck(
    "android_device_precheck_script_registered",
    Boolean(packageJson.scripts?.["verify:android-device-precheck"]),
    {},
  );
  const androidReleaseVerifier = readText(
    path.join(repoRoot, "scripts", "verify-android-release-artifact.ps1"),
  );
  addCheck(
    "android_release_verifier_checks_aab_identity_and_signing",
    androidReleaseVerifier.includes("dist_aab_matches_build_output") &&
      androidReleaseVerifier.includes("release_build_does_not_fallback_to_debug") &&
      androidReleaseVerifier.includes("release_keystore_readable_by_keytool") &&
      androidReleaseVerifier.includes("firebase_package_matches_application_id"),
    {},
  );
  const realDeviceQa = readText(
    path.join(repoRoot, "scripts", "run-android-real-device-qa.ps1"),
  );
  const realDevicePrecheck = readText(
    path.join(repoRoot, "scripts", "run-android-real-device-precheck.ps1"),
  );
  addCheck(
    "android_real_device_precheck_captures_install_version_and_permissions",
    realDevicePrecheck.includes("android-real-device-precheck-latest.json") &&
      realDevicePrecheck.includes("version_code_matches_expected") &&
      realDevicePrecheck.includes("version_name_matches_expected") &&
      realDevicePrecheck.includes("POST_NOTIFICATIONS") &&
      realDevicePrecheck.includes("RECORD_AUDIO") &&
      realDevicePrecheck.includes("wakefulness") &&
      realDevicePrecheck.includes("device_not_awake") &&
      realDevicePrecheck.includes("Get-DeviceLockState") &&
      realDevicePrecheck.includes("deviceLocked") &&
      realDevicePrecheck.includes("device_locked") &&
      realDevicePrecheck.includes("precheck_completed"),
    {},
  );
  addCheck(
    "android_real_device_qa_script_captures_evidence",
    realDeviceQa.includes("manual-checklist.md") &&
      realDeviceQa.includes("logcat") &&
      realDeviceQa.includes("uiautomator dump") &&
      realDeviceQa.includes("screencap"),
    {},
  );
  addCheck(
    "android_real_device_qa_script_blocks_locked_device",
    realDeviceQa.includes("Get-DeviceLockState") &&
      realDeviceQa.includes("device_unlocked_for_qa") &&
      realDeviceQa.includes("launch_skipped_device_locked") &&
      realDeviceQa.includes("Android keyguard/PIN screen prevents Verbal UI capture"),
    {},
  );
  addCheck(
    "android_real_device_qa_script_supports_dry_run",
    realDeviceQa.includes("[switch]$DryRun") &&
      realDeviceQa.includes("dry_run_completed") &&
      realDeviceQa.includes("android-real-device-qa-dryrun-latest.json") &&
      realDeviceQa.includes("android-real-device-qa-latest.json"),
    {},
  );
  addCheck(
    "fcm_real_device_qa_script_registered",
    Boolean(packageJson.scripts?.["verify:fcm-real-device"]),
    {},
  );
  const fcmRealDeviceQa = readText(
    path.join(repoRoot, "scripts", "run-fcm-real-device-qa.ps1"),
  );
  addCheck(
    "fcm_real_device_qa_script_captures_all_delivery_states",
    fcmRealDeviceQa.includes('Confirm-State -State "foreground"') &&
      fcmRealDeviceQa.includes('Confirm-State -State "background"') &&
      fcmRealDeviceQa.includes('Confirm-State -State "terminated"') &&
      fcmRealDeviceQa.includes('Confirm-State -State "lock-screen"') &&
      fcmRealDeviceQa.includes("$states.foreground") &&
      fcmRealDeviceQa.includes("$states.background") &&
      fcmRealDeviceQa.includes("$states.terminated") &&
      fcmRealDeviceQa.includes("$states.lockScreen") &&
      (fcmRealDeviceQa.includes("artifacts\\fcm-real-device-latest.json") ||
        fcmRealDeviceQa.includes("artifacts/fcm-real-device-latest.json")) &&
      fcmRealDeviceQa.includes("fcm-real-device-dryrun-latest.json"),
    {},
  );
  addCheck(
    "fcm_real_device_qa_script_blocks_locked_start",
    fcmRealDeviceQa.includes("Get-DeviceLockState") &&
      fcmRealDeviceQa.includes("device_unlocked_for_fcm_start") &&
      fcmRealDeviceQa.includes("if (-not $lockState.locked)"),
    {},
  );
  addCheck(
    "fcm_real_device_qa_script_supports_dry_run",
    fcmRealDeviceQa.includes("[switch]$DryRun") &&
      fcmRealDeviceQa.includes("dry_run_completed"),
    {},
  );
  const androidRealDeviceQaDoc = readText(
    path.join(repoRoot, "docs", "ANDROID_REAL_DEVICE_QA.md"),
  );
  const androidRealDeviceQaKoDoc = readText(
    path.join(repoRoot, "docs", "ko", "ANDROID_REAL_DEVICE_QA.md"),
  );
  const fcmRealDeviceQaDoc = readText(path.join(repoRoot, "docs", "FCM_REAL_DEVICE_QA.md"));
  const fcmRealDeviceQaKoDoc = readText(
    path.join(repoRoot, "docs", "ko", "FCM_REAL_DEVICE_QA.md"),
  );
  addCheck(
    "android_real_device_docs_explain_unlock_requirement",
    androidRealDeviceQaDoc.includes("device_unlocked_for_qa: false") &&
      androidRealDeviceQaDoc.includes("keyguard/PIN") &&
      androidRealDeviceQaKoDoc.includes("device_unlocked_for_qa: false") &&
      androidRealDeviceQaKoDoc.includes("잠금을 해제"),
    {},
  );
  addCheck(
    "fcm_real_device_docs_explain_unlock_start_requirement",
    fcmRealDeviceQaDoc.includes("device_unlocked_for_fcm_start") &&
      fcmRealDeviceQaDoc.includes("phone awake and unlocked") &&
      fcmRealDeviceQaKoDoc.includes("device_unlocked_for_fcm_start") &&
      fcmRealDeviceQaKoDoc.includes("잠금 해제"),
    {},
  );
  const productionE2e = readText(
    path.join(repoRoot, "functions", "scripts", "production-e2e-smoke.js"),
  );
  for (const callable of [
    "sendTextMessage",
    "editMessage",
    "deleteMessage",
    "scheduleTextMessage",
    "sendScheduledMessageNow",
    "sendAttachmentMessage",
    "translateMessage",
    "createTranscriptionDraft",
    "sendVoiceMessage",
    "sendInstantVoiceMessage",
    "createCalendarIntentDraft",
    "createCalendarEvent",
    "updateCalendarEvent",
    "deleteCalendarEvent",
    "createCalendarProposal",
    "voteCalendarProposal",
    "finalizeCalendarProposal",
    "createRoomInvite",
    "joinRoomByInvite",
    "leaveRoom",
    "reportMessage",
    "blockUser",
  ]) {
    addCheck(`production_e2e_covers_callable:${callable}`, productionE2e.includes(callable), {
      callable,
    });
  }
  addCheck(
    "play_store_assets_script_registered",
    Boolean(packageJson.scripts?.["prepare:play-store-assets"]),
    {},
  );
  addCheck(
    "play_console_pack_script_registered",
    Boolean(packageJson.scripts?.["prepare:play-console-pack"]),
    {},
  );
  addCheck(
    "app_content_answers_script_registered",
    Boolean(packageJson.scripts?.["prepare:app-content-answers"]),
    {},
  );
  addCheck(
    "app_content_copy_sheet_script_registered",
    Boolean(packageJson.scripts?.["prepare:app-content-copy-sheet"]),
    {},
  );
  addCheck(
    "closed_testing_pack_script_registered",
    Boolean(packageJson.scripts?.["prepare:closed-testing-pack"]),
    {},
  );
  addCheck(
    "launch_handoff_script_registered",
    Boolean(packageJson.scripts?.["prepare:launch-handoff"]),
    {},
  );
  addCheck(
    "launch_status_script_registered",
    Boolean(packageJson.scripts?.["status:launch"]),
    {},
  );
  addCheck(
    "next_external_step_guide_script_registered",
    Boolean(packageJson.scripts?.["guide:next-launch-step"]),
    {},
  );
  addCheck(
    "open_next_launch_step_script_registered",
    Boolean(packageJson.scripts?.["open:next-launch-step"]),
    {},
  );
  addCheck(
    "launch_gate_report_script_registered",
    Boolean(packageJson.scripts?.["report:launch-gate"]),
    {},
  );
  addCheck(
    "launch_evidence_template_script_registered",
    Boolean(packageJson.scripts?.["prepare:launch-evidence"]),
    {},
  );
  addCheck(
    "launch_evidence_recorder_script_registered",
    Boolean(packageJson.scripts?.["record:launch-evidence"]),
    {},
  );
  addCheck(
    "app_content_submitted_shortcut_script_registered",
    Boolean(packageJson.scripts?.["record:app-content-submitted"]),
    {},
  );
  addCheck(
    "prelaunch_reviewed_shortcut_script_registered",
    Boolean(packageJson.scripts?.["record:prelaunch-reviewed"]),
    {},
  );
  addCheck(
    "closed_testing_shortcut_scripts_registered",
    Boolean(packageJson.scripts?.["record:closed-testing-completed"]) &&
      Boolean(packageJson.scripts?.["record:closed-testing-not-required"]),
    {},
  );
  addCheck(
    "real_device_evidence_shortcut_scripts_registered",
    Boolean(packageJson.scripts?.["record:real-device-e2e"]) &&
      Boolean(packageJson.scripts?.["record:fcm-real-device"]),
    {},
  );
  addCheck(
    "launch_evidence_verifier_script_registered",
    Boolean(packageJson.scripts?.["verify:launch-evidence"]),
    {},
  );
  const launchReadinessVerifier = readText(
    path.join(repoRoot, "functions", "scripts", "verify-launch-readiness.js"),
  );
  const hostedPolicyUrlVerifier = readText(
    path.join(repoRoot, "functions", "scripts", "verify-hosted-policy-urls.js"),
  );
  addCheck(
    "hosted_policy_url_verifier_checks_play_console_urls",
    hostedPolicyUrlVerifier.includes("hosted-policy-url-verification-latest.md") &&
      hostedPolicyUrlVerifier.includes("https://verbal.chat/privacy") &&
      hostedPolicyUrlVerifier.includes("https://verbal.chat/terms") &&
      hostedPolicyUrlVerifier.includes("https://verbal.chat/community-guidelines") &&
      hostedPolicyUrlVerifier.includes("https://verbal.chat/account/delete") &&
      hostedPolicyUrlVerifier.includes("https://verbal.chat/data-deletion") &&
      hostedPolicyUrlVerifier.includes("voice-messenger-jangs-260522.web.app/account/delete") &&
      hostedPolicyUrlVerifier.includes("support@verbal.chat"),
    {},
  );
  addCheck(
    "launch_readiness_writes_latest_artifact",
    launchReadinessVerifier.includes("launch-readiness-latest.json") &&
      launchReadinessVerifier.includes("latestResultPath"),
    {},
  );
  addCheck(
    "launch_consistency_script_registered",
    Boolean(packageJson.scripts?.["verify:launch-consistency"]),
    {},
  );
  addCheck(
    "public_release_gate_script_registered",
    Boolean(packageJson.scripts?.["verify:public-release"]),
    {},
  );
  addCheck(
    "public_release_gate_alias_registered",
    packageJson.scripts?.["verify:public-release-gate"] === "npm run verify:public-release",
    {},
  );
  addCheck(
    "preinternal_release_check_script_registered",
    Boolean(packageJson.scripts?.["verify:preinternal"]),
    {},
  );
  addCheck(
    "launch_readiness_manual_required_lists_public_exposure_blockers",
    manualRequired.some((item) => item.item.includes("Pre-launch report")) &&
      manualRequired.some((item) => item.item.includes("closed testing")) &&
      manualRequired.some((item) => item.item.includes("Data Safety")) &&
      manualRequired.some((item) => item.item.includes("real-device E2E")) &&
      manualRequired.some((item) => item.item.includes("FCM")),
    {},
  );
  const launchEvidenceTemplate = readText(
    path.join(repoRoot, "functions", "scripts", "prepare-launch-evidence-template.js"),
  );
  const closedTestingPackGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-closed-testing-pack.js"),
  );
  const launchHandoffGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-launch-handoff.js"),
  );
  const launchStatusGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-launch-status.js"),
  );
  const nextExternalStepGuideGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-next-external-step-guide.js"),
  );
  const nextExternalStepGuideLatest = readText(
    path.join(repoRoot, "artifacts", "next-external-step-latest.md"),
  );
  const closedTestingRunbook = readText(
    path.join(repoRoot, "docs", "CLOSED_TESTING_RUNBOOK.md"),
  );
  const launchHandoffRunbook = readText(
    path.join(repoRoot, "docs", "LAUNCH_HANDOFF.md"),
  );
  const launchStatusRunbook = readText(
    path.join(repoRoot, "docs", "LAUNCH_STATUS.md"),
  );
  const publicReleaseGateVerifier = readText(
    path.join(repoRoot, "functions", "scripts", "verify-public-release-gate.js"),
  );
  const launchConsistencyVerifier = readText(
    path.join(repoRoot, "functions", "scripts", "verify-launch-consistency.js"),
  );
  const launchConsistencyRunbook = readText(
    path.join(repoRoot, "docs", "LAUNCH_CONSISTENCY.md"),
  );
  const publicReleaseGateRunbook = readText(
    path.join(repoRoot, "docs", "PUBLIC_RELEASE_GATE.md"),
  );
  addCheck(
    "closed_testing_pack_covers_tester_feedback_and_evidence",
    closedTestingPackGenerator.includes("minimumOptedInTesters: 12") &&
      closedTestingPackGenerator.includes("minimumContinuousDays: 14") &&
      closedTestingPackGenerator.includes("tester-list-template.csv") &&
      closedTestingPackGenerator.includes("feedbackQuestions") &&
      closedTestingPackGenerator.includes("requiredClosedTesting") &&
      closedTestingRunbook.includes("npm run prepare:closed-testing-pack") &&
      closedTestingRunbook.includes("closed-testing-completed"),
    {},
  );
  addCheck(
    "launch_handoff_covers_external_sequence_and_gate",
    launchHandoffGenerator.includes("readyForInternalTestingUpload") &&
      launchHandoffGenerator.includes("readyForPublicUserExposure") &&
      launchHandoffGenerator.includes("play-app-created") &&
      launchHandoffGenerator.includes("internal-testing-upload") &&
      launchHandoffGenerator.includes("app-content-submitted") &&
      launchHandoffGenerator.includes("prelaunch-reviewed") &&
      launchHandoffGenerator.includes("closed-testing-completed") &&
      launchHandoffGenerator.includes("real-device-e2e") &&
      launchHandoffGenerator.includes("fcm") &&
      launchHandoffGenerator.includes("launch-handoff-latest.md") &&
      launchHandoffRunbook.includes("npm run prepare:launch-handoff") &&
      launchHandoffRunbook.includes("readyForPublicUserExposure"),
    {},
  );
  addCheck(
    "launch_handoff_separates_completed_and_remaining_external_work",
    launchHandoffGenerator.includes("completedExternalSteps") &&
      launchHandoffGenerator.includes("remainingExternalSteps") &&
      launchHandoffGenerator.includes("Completed External Work") &&
      launchHandoffGenerator.includes("Remaining External Work Sequence") &&
      launchHandoffGenerator.includes("verbal-app-content-copy-sheet-latest.html"),
    {},
  );
  addCheck(
    "launch_status_summarizes_gate_evidence_and_next_step",
    launchStatusGenerator.includes("launch-status-latest.md") &&
      launchStatusGenerator.includes("readyForInternalTestingUpload") &&
      launchStatusGenerator.includes("readyForPublicUserExposure") &&
      launchStatusGenerator.includes("publicExposureBlockedAsExpected") &&
      launchStatusGenerator.includes("allowIncompleteExternalEvidence !== true") &&
      launchStatusGenerator.includes("Next External Step") &&
      launchStatusGenerator.includes("play_console_app_created") &&
      launchStatusGenerator.includes("play_internal_testing_uploaded") &&
      launchStatusGenerator.includes("play_data_safety_submitted") &&
      launchStatusGenerator.includes("android_real_device_e2e_verified") &&
      launchStatusGenerator.includes("fcm_real_device_delivery_verified") &&
      launchStatusRunbook.includes("npm run status:launch") &&
      launchStatusRunbook.includes("readyForPublicUserExposure"),
    {},
  );
  addCheck(
    "next_external_step_guide_targets_current_highest_priority_blocker",
    nextExternalStepGuideGenerator.includes("next-external-step-latest.md") &&
      nextExternalStepGuideGenerator.includes("play_data_safety_submitted") &&
      nextExternalStepGuideGenerator.includes("verbal-app-content-answers-latest.md") &&
      nextExternalStepGuideGenerator.includes("Section-by-section Console Flow") &&
      nextExternalStepGuideGenerator.includes("consoleQuickAnswers") &&
      nextExternalStepGuideGenerator.includes("Korean Console Flow") &&
      nextExternalStepGuideGenerator.includes("Korean UI label") &&
      nextExternalStepGuideGenerator.includes("Remaining Public Exposure Sequence") &&
      nextExternalStepGuideGenerator.includes("open:next-launch-step") &&
      nextExternalStepGuideGenerator.includes("play_prelaunch_report_reviewed") &&
      nextExternalStepGuideGenerator.includes("play_closed_testing_completed") &&
      nextExternalStepGuideGenerator.includes("npm run record:launch-evidence") &&
      nextExternalStepGuideGenerator.includes("readyForPublicUserExposure"),
    {},
  );
  addCheck(
    "next_external_step_latest_has_no_control_characters",
    !hasUnsafeControlChars(nextExternalStepGuideLatest) &&
      nextExternalStepGuideLatest.includes("cd .\\functions") &&
      nextExternalStepGuideLatest.includes("npm run open:next-launch-step"),
    {},
  );
  addCheck(
    "public_release_gate_blocks_until_public_exposure_ready",
    publicReleaseGateVerifier.includes("verify:launch-evidence") &&
      publicReleaseGateVerifier.includes("report:launch-gate") &&
      publicReleaseGateVerifier.includes("readyForPublicUserExposure") &&
      publicReleaseGateVerifier.includes("public-release-gate-latest.json") &&
      publicReleaseGateVerifier.includes("process.env.npm_execpath") &&
      publicReleaseGateVerifier.includes("maxBuffer") &&
      publicReleaseGateVerifier.includes("error: result.error") &&
      publicReleaseGateVerifier.includes("process.exitCode = ok ? 0 : 1") &&
      publicReleaseGateRunbook.includes("npm run verify:public-release") &&
      publicReleaseGateRunbook.includes("npm run verify:public-release-gate") &&
      publicReleaseGateRunbook.includes("failure is intentional") &&
      publicReleaseGateRunbook.includes("readyForPublicUserExposure"),
    {},
  );
  addCheck(
    "launch_consistency_checks_release_pack_gate_and_handoff",
    launchConsistencyVerifier.includes("verbal-play-console-pack-latest.json") &&
      launchConsistencyVerifier.includes("android-release-verification-latest.json") &&
      launchConsistencyVerifier.includes("launch-gate-latest.json") &&
      launchConsistencyVerifier.includes("launch-handoff-latest.json") &&
      launchConsistencyVerifier.includes("play_pack_aab_sha_matches_current_aab") &&
      launchConsistencyVerifier.includes("handoff_blockers_match_launch_gate") &&
      launchConsistencyVerifier.includes("handoff_points_to_latest_play_pack") &&
      launchConsistencyVerifier.includes("handoff_points_to_latest_closed_testing_pack") &&
      launchConsistencyVerifier.includes("launch-consistency-latest.json") &&
      launchConsistencyRunbook.includes("npm run verify:launch-consistency") &&
      launchConsistencyRunbook.includes("same release candidate"),
    {},
  );
  addCheck(
    "launch_evidence_template_has_play_and_real_device_sections",
      launchEvidenceTemplate.includes("playConsole") &&
      launchEvidenceTemplate.includes("internalTestingUpload") &&
      launchEvidenceTemplate.includes("preLaunchReportReviewed") &&
      launchEvidenceTemplate.includes("closedTestingCompleted") &&
      launchEvidenceTemplate.includes("realDevice") &&
      launchEvidenceTemplate.includes("fcm") &&
      launchEvidenceTemplate.includes("record:launch-evidence"),
    {},
  );
  addCheck(
    "launch_evidence_template_prefills_release_identity",
    launchEvidenceTemplate.includes("readLatestAndroidRelease") &&
      launchEvidenceTemplate.includes("releaseSha256") &&
      launchEvidenceTemplate.includes("releaseVersionCode"),
    {},
  );
  const launchEvidenceRecorder = readText(
    path.join(repoRoot, "functions", "scripts", "record-launch-evidence.js"),
  );
  addCheck(
    "launch_evidence_recorder_updates_all_manual_sections",
      launchEvidenceRecorder.includes("play-app-created") &&
      launchEvidenceRecorder.includes("internal-testing-upload") &&
      launchEvidenceRecorder.includes("prelaunch-reviewed") &&
      launchEvidenceRecorder.includes("confirm-no-blocking-issues") &&
      launchEvidenceRecorder.includes("closed-testing-completed") &&
      launchEvidenceRecorder.includes("confirm-production-access-ready") &&
      launchEvidenceRecorder.includes("app-content-submitted") &&
      launchEvidenceRecorder.includes("confirm-privacy-policy") &&
      launchEvidenceRecorder.includes("confirm-account-deletion") &&
      launchEvidenceRecorder.includes("confirm-data-deletion") &&
      launchEvidenceRecorder.includes("confirm-government-app") &&
      launchEvidenceRecorder.includes("confirm-financial-features") &&
      launchEvidenceRecorder.includes("confirm-health") &&
      launchEvidenceRecorder.includes("confirm-app-category-contact") &&
      launchEvidenceRecorder.includes("confirm-store-listing") &&
      launchEvidenceRecorder.includes("real-device-e2e") &&
      launchEvidenceRecorder.includes("fcm") &&
      launchEvidenceRecorder.includes("requireExistingArtifact"),
    {},
  );
  addCheck(
    "launch_evidence_recorder_validates_app_content_prerequisites",
    launchEvidenceRecorder.includes("requireAppContentSubmissionPrerequisites") &&
      launchEvidenceRecorder.includes("verbal-app-content-answers-latest.md") &&
      launchEvidenceRecorder.includes("Console quick answers") &&
      launchEvidenceRecorder.includes("Detailed Play Console input matrix") &&
      launchEvidenceRecorder.includes("hosted-policy-url-verification-latest.json") &&
      launchEvidenceRecorder.includes("Run npm run verify:hosted-policy-urls first"),
    {},
  );
  addCheck(
    "launch_evidence_recorder_status_lists_remaining_actions",
    launchEvidenceRecorder.includes("remainingGates") &&
      launchEvidenceRecorder.includes("remainingGateOrder") &&
      launchEvidenceRecorder.includes("buildRemainingEvidenceActions") &&
      launchEvidenceRecorder.includes("alternativeCommand") &&
      launchEvidenceRecorder.includes("prerequisite"),
    {},
  );
  const launchEvidenceVerifier = readText(
    path.join(repoRoot, "functions", "scripts", "verify-launch-evidence.js"),
  );
  const launchEvidenceUtils = readText(
    path.join(repoRoot, "functions", "scripts", "launch-evidence-utils.js"),
  );
  addCheck(
    "launch_evidence_verifier_checks_play_and_real_device_sections",
    launchEvidenceVerifier.includes("buildLaunchEvidenceChecks") &&
      launchEvidenceVerifier.includes("allowIncompleteExternalEvidence") &&
      launchEvidenceUtils.includes("playAppCreated") &&
      launchEvidenceUtils.includes("internalTestingUpload") &&
      launchEvidenceUtils.includes("preLaunchReportReviewed") &&
      launchEvidenceUtils.includes("closedTestingCompleted") &&
      launchEvidenceUtils.includes("privacyPolicy") &&
      launchEvidenceUtils.includes("accountDeletion") &&
      launchEvidenceUtils.includes("dataDeletion") &&
      launchEvidenceUtils.includes("governmentApp") &&
      launchEvidenceUtils.includes("financialFeatures") &&
      launchEvidenceUtils.includes("appCategoryContact") &&
      launchEvidenceUtils.includes("storeListing") &&
      launchEvidenceUtils.includes("realDeviceE2e") &&
      launchEvidenceUtils.includes("fcm") &&
      launchEvidenceUtils.includes("manual_e2e_confirmed") &&
      launchEvidenceUtils.includes("fcmArtifactStatesOk") &&
      launchEvidenceUtils.includes("realDeviceE2eArtifactOk"),
    {},
  );
  const launchGateReport = readText(
    path.join(repoRoot, "functions", "scripts", "generate-launch-gate-report.js"),
  );
  addCheck(
    "launch_gate_report_separates_internal_testing_from_public_exposure",
    launchGateReport.includes("readyForInternalTestingUpload") &&
      launchGateReport.includes("readyForPublicUserExposure") &&
      launchGateReport.includes("play_console_app_created") &&
      launchGateReport.includes("play_prelaunch_report_reviewed") &&
      launchGateReport.includes("play_closed_testing_completed") &&
      launchGateReport.includes("fcm_real_device_delivery_verified") &&
      launchGateReport.includes("launch-manual-evidence.json"),
    {},
  );
  addCheck(
    "launch_gate_report_points_to_evidence_recorder",
      launchGateReport.includes("record:launch-evidence") &&
      launchGateReport.includes("play-app-created") &&
      launchGateReport.includes("internal-testing-upload") &&
      launchGateReport.includes("prelaunch-reviewed") &&
      launchGateReport.includes("closed-testing-completed") &&
      launchGateReport.includes("app-content-submitted") &&
      launchGateReport.includes("run-fcm-real-device-qa.ps1") &&
      launchGateReport.includes("fcm-real-device-latest.json"),
    {},
  );
  addCheck(
    "launch_gate_report_orders_public_exposure_blockers",
    launchGateReport.includes("publicExposureGateOrder") &&
      launchGateReport.indexOf("play_data_safety_submitted") <
        launchGateReport.indexOf("play_prelaunch_report_reviewed") &&
      launchGateReport.indexOf("play_prelaunch_report_reviewed") <
        launchGateReport.indexOf("play_closed_testing_completed") &&
      launchGateReport.includes("compareGatePriority") &&
      launchGateReport.includes("blockers = gates.filter((item) => !item.ok).sort(compareGatePriority)"),
    {},
  );
  addCheck(
    "launch_evidence_status_prioritizes_app_content_before_prelaunch",
    launchEvidenceRecorder.indexOf("gate: \"appContentSubmitted\"") <
      launchEvidenceRecorder.indexOf("gate: \"preLaunchReportReviewed\"") &&
      launchEvidenceVerifier.indexOf("gates.appContentSubmitted") <
        launchEvidenceVerifier.indexOf("gates.preLaunchReportReviewed"),
    {},
  );
  const preinternalCheck = readText(
    path.join(repoRoot, "functions", "scripts", "run-preinternal-release-check.js"),
  );
  addCheck(
    "preinternal_release_check_runs_local_upload_gates",
    preinternalCheck.includes("verify:android-release") &&
      preinternalCheck.includes("verify:hosted-policy-urls") &&
      preinternalCheck.includes("verify:launch-readiness") &&
      preinternalCheck.includes("prepare:app-content-answers") &&
      preinternalCheck.includes("prepare:app-content-copy-sheet") &&
      preinternalCheck.includes("prepare:play-console-pack") &&
      preinternalCheck.includes("prepare:closed-testing-pack") &&
    preinternalCheck.includes("prepare:launch-handoff") &&
    preinternalCheck.includes("verify:launch-consistency") &&
      preinternalCheck.includes("status:launch") &&
    preinternalCheck.includes("report:launch-gate") &&
    preinternalCheck.includes("launchHandoff") &&
    preinternalCheck.includes("appContentCopySheet") &&
    preinternalCheck.includes("launchConsistency") &&
      preinternalCheck.includes("launchStatus") &&
    preinternalCheck.includes("hostedPolicyUrls") &&
    preinternalCheck.includes("readyForInternalTestingUpload"),
    {},
  );
  const playConsolePackGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-play-console-pack.js"),
  );
  addCheck(
    "play_console_pack_points_to_evidence_recorder",
    playConsolePackGenerator.includes("record:launch-evidence") &&
      playConsolePackGenerator.includes("verbal-app-content-copy-sheet-latest.html") &&
      playConsolePackGenerator.includes("play-app-created") &&
      playConsolePackGenerator.includes("internal-testing-upload") &&
      playConsolePackGenerator.includes("prelaunch-reviewed") &&
      playConsolePackGenerator.includes("closed-testing-completed") &&
      playConsolePackGenerator.includes("app-content-submitted") &&
      playConsolePackGenerator.includes("fcmRealDeviceQa") &&
      playConsolePackGenerator.includes("run-fcm-real-device-qa.ps1"),
    {},
  );
  const appContentAnswersGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-app-content-answers.js"),
  );
  addCheck(
    "app_content_answers_generator_covers_play_console_form",
    appContentAnswersGenerator.includes("Data Safety") &&
      appContentAnswersGenerator.includes("consoleQuickAnswers") &&
      appContentAnswersGenerator.includes("Does the app collect or share user data?") &&
      appContentAnswersGenerator.includes("App Access") &&
      appContentAnswersGenerator.includes("Content Rating") &&
      appContentAnswersGenerator.includes("Target Audience") &&
      appContentAnswersGenerator.includes("Sensitive Permissions") &&
      appContentAnswersGenerator.includes("User-generated content") &&
      appContentAnswersGenerator.includes("Government App") &&
      appContentAnswersGenerator.includes("Financial Features") &&
      appContentAnswersGenerator.includes("Health") &&
      appContentAnswersGenerator.includes("App Category And Contact Details") &&
      appContentAnswersGenerator.includes("Store Listing") &&
      appContentAnswersGenerator.includes("--confirm-government-app") &&
      appContentAnswersGenerator.includes("--confirm-financial-features") &&
      appContentAnswersGenerator.includes("--confirm-health") &&
      appContentAnswersGenerator.includes("--confirm-app-category-contact") &&
      appContentAnswersGenerator.includes("--confirm-store-listing"),
    {},
  );
  const appContentCopySheetGenerator = readText(
    path.join(repoRoot, "functions", "scripts", "generate-app-content-copy-sheet.js"),
  );
  const openNextLaunchStep = readText(
    path.join(repoRoot, "scripts", "open-play-console-next-step.ps1"),
  );
  const appContentSubmittedShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-app-content-submitted.js"),
  );
  const shortcutUtils = readText(
    path.join(repoRoot, "functions", "scripts", "record-launch-shortcut-utils.js"),
  );
  const prelaunchReviewedShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-prelaunch-reviewed.js"),
  );
  const closedTestingCompletedShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-closed-testing-completed.js"),
  );
  const closedTestingNotRequiredShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-closed-testing-not-required.js"),
  );
  const realDeviceE2eShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-real-device-e2e.js"),
  );
  const fcmRealDeviceShortcut = readText(
    path.join(repoRoot, "functions", "scripts", "record-fcm-real-device.js"),
  );
  addCheck(
    "app_content_copy_sheet_generator_covers_play_console_form",
    appContentCopySheetGenerator.includes("verbal-app-content-answers-latest.json") &&
      appContentCopySheetGenerator.includes("verbal-app-content-copy-sheet-latest.html") &&
      appContentCopySheetGenerator.includes("navigator.clipboard.writeText") &&
      appContentCopySheetGenerator.includes("Data Safety Quick Answers") &&
      appContentCopySheetGenerator.includes("Evidence Command"),
    {},
  );
  addCheck(
    "open_next_launch_step_helper_opens_current_artifacts",
    openNextLaunchStep.includes("next-external-step-latest.json") &&
      openNextLaunchStep.includes("verbal-app-content-copy-sheet-latest.html") &&
      openNextLaunchStep.includes("launch-status-latest.md") &&
      openNextLaunchStep.includes("playConsoleAppUrl") &&
      openNextLaunchStep.includes("Start-Process"),
    {},
  );
  addCheck(
    "app_content_submitted_shortcut_records_all_sections",
    appContentSubmittedShortcut.includes("record-launch-evidence.js") &&
      appContentSubmittedShortcut.includes("app-content-submitted") &&
      appContentSubmittedShortcut.includes("--confirm-privacy-policy") &&
      appContentSubmittedShortcut.includes("--confirm-store-listing") &&
      appContentSubmittedShortcut.includes("report:launch-gate") &&
      appContentSubmittedShortcut.includes("status:launch") &&
      appContentSubmittedShortcut.includes("guide:next-launch-step") &&
      appContentSubmittedShortcut.includes("prepare:launch-handoff"),
    {},
  );
  addCheck(
    "manual_evidence_shortcuts_wrap_strict_recorder",
    shortcutUtils.includes("record-launch-evidence.js") &&
      shortcutUtils.includes("report:launch-gate") &&
      shortcutUtils.includes("status:launch") &&
      shortcutUtils.includes("guide:next-launch-step") &&
      prelaunchReviewedShortcut.includes("prelaunch-reviewed") &&
      prelaunchReviewedShortcut.includes("--confirm-no-blocking-issues") &&
      closedTestingCompletedShortcut.includes("closed-testing-completed") &&
      closedTestingCompletedShortcut.includes("--confirm-production-access-ready") &&
      closedTestingNotRequiredShortcut.includes("--not-required") &&
      realDeviceE2eShortcut.includes("artifacts/android-real-device-qa-latest.json") &&
      fcmRealDeviceShortcut.includes("artifacts/fcm-real-device-latest.json") &&
      fcmRealDeviceShortcut.includes("--lock-screen"),
    {},
  );
  addCheck(
    "play_console_pack_points_to_app_content_answers",
    playConsolePackGenerator.includes("verbal-app-content-answers-latest.md") &&
      playConsolePackGenerator.includes("verbal-app-content-copy-sheet-latest.html"),
    {},
  );
  addCheck(
    "security_rules_test_script_registered",
    Boolean(packageJson.scripts?.["rules:test"]),
    {},
  );
}

async function checkHostedUrls() {
  if (skipNetwork) {
    addCheck("hosted_url_checks_skipped", true, {skipNetwork});
    return;
  }

  const targets = [
    {
      name: "custom_domain_home",
      url: "https://verbal.chat",
      expected: "Verbal",
    },
    {
      name: "custom_domain_privacy",
      url: "https://verbal.chat/privacy",
      expected: "support@verbal.chat",
    },
    {
      name: "custom_domain_terms",
      url: "https://verbal.chat/terms",
      expected: "support@verbal.chat",
    },
    {
      name: "custom_domain_community_guidelines",
      url: "https://verbal.chat/community-guidelines",
      expected: "support@verbal.chat",
    },
    {
      name: "custom_domain_account_delete",
      url: "https://verbal.chat/account/delete",
      expected: "support@verbal.chat",
    },
    {
      name: "custom_domain_data_deletion",
      url: "https://verbal.chat/data-deletion",
      expected: "support@verbal.chat",
    },
    {
      name: "firebase_account_delete_fallback",
      url: "https://voice-messenger-jangs-260522.web.app/account/delete",
      expected: "support@verbal.chat",
    },
  ];

  for (const target of targets) {
    const result = await fetchText(target.url);
    addCheck(`hosted_url_reachable:${target.name}`, result.ok, {
      url: target.url,
      status: result.status,
      error: result.error,
    });
    if (result.ok) {
      addCheck(`hosted_url_content:${target.name}`, result.body.includes(target.expected), {
        url: target.url,
        expected: target.expected,
      });
    }
  }
}

async function fetchText(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: {"User-Agent": "verbal-launch-readiness/1.0"},
    });
    const body = await response.text();
    return {ok: response.ok, status: response.status, body};
  } catch (error) {
    return {ok: false, status: 0, body: "", error: String(error?.message || error)};
  } finally {
    clearTimeout(timeout);
  }
}

function latestMtime(paths) {
  let latest = {path: "", mtimeMs: 0};
  for (const item of paths) {
    const stat = safeStat(item);
    if (!stat) {
      continue;
    }
    if (stat.isDirectory()) {
      for (const file of walkFiles(item)) {
        const fileStat = safeStat(file);
        if (fileStat && fileStat.mtimeMs > latest.mtimeMs) {
          latest = {path: file, mtimeMs: fileStat.mtimeMs};
        }
      }
    } else if (stat.mtimeMs > latest.mtimeMs) {
      latest = {path: item, mtimeMs: stat.mtimeMs};
    }
  }
  return latest;
}

function* walkFiles(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if ([".dart_tool", "build"].includes(entry.name)) {
        continue;
      }
      yield* walkFiles(fullPath);
    } else {
      yield fullPath;
    }
  }
}

function listFiles(dir) {
  const stat = safeStat(dir);
  if (!stat || !stat.isDirectory()) {
    return [];
  }
  return Array.from(walkFiles(dir));
}

function readPngDimensions(filePath) {
  const stat = safeStat(filePath);
  if (!stat || stat.size < 24) {
    return null;
  }
  const buffer = fs.readFileSync(filePath);
  if (
    buffer[0] !== 0x89 ||
    buffer[1] !== 0x50 ||
    buffer[2] !== 0x4e ||
    buffer[3] !== 0x47
  ) {
    return null;
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
    bytes: stat.size,
  };
}

function addCheck(name, ok, detail) {
  checks.push({name, ok: Boolean(ok), detail});
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function safeStat(filePath) {
  try {
    return fs.statSync(filePath);
  } catch {
    return null;
  }
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function stripBom(value) {
  return value.replace(/^\uFEFF/, "");
}

function hasMojibake(value) {
  return /[\uFFFD]|뚯|꽦|諛|硫|怨|媛|鍮|蹂|濡|묒|쒖|꾩|ㅽ/.test(value);
}

function hasUnsafeControlChars(value) {
  return /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(value);
}

function hangulCount(value) {
  return (value.match(/[가-힣]/g) || []).length;
}

function relative(filePath) {
  return path.relative(repoRoot, filePath);
}

function writeResultAndExit() {
  const failed = checks.filter((check) => !check.ok);
  const result = {
    ok: failed.length === 0,
    checkedAt: new Date().toISOString(),
    failedCount: failed.length,
    passedCount: checks.length - failed.length,
    checks,
    manualRequired,
    artifact: path.relative(repoRoot, resultPath),
  };
  fs.mkdirSync(artifactDir, {recursive: true});
  fs.writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  fs.writeFileSync(latestResultPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}
