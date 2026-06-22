const fs = require("node:fs");
const path = require("node:path");

const expectedPackageName = "com.voicebeta.verbal";
const expectedUrls = {
  privacyPolicyUrl: "https://verbal.chat/privacy",
  accountDeletionUrl: "https://verbal.chat/account/delete",
  dataDeletionUrl: "https://verbal.chat/data-deletion",
};

function evaluateManualEvidence({evidence, androidRelease, repoRoot}) {
  const releaseSha = String(androidRelease?.release?.sha256 || "").toLowerCase();
  const versionCode = String(androidRelease?.android?.versionCode || "");
  const evidencePath = evidence ? "artifacts/launch-manual-evidence.json" : "";
  const appCreated = evidence?.playConsole?.appCreated || {};
  const internalUpload = evidence?.playConsole?.internalTestingUpload || {};
  const preLaunchReport = evidence?.playConsole?.preLaunchReportReviewed || {};
  const closedTesting = evidence?.playConsole?.closedTestingCompleted || {};
  const appContent = evidence?.playConsole?.appContentSubmitted || {};
  const e2e = evidence?.realDevice?.e2e || {};
  const fcm = evidence?.realDevice?.fcm || {};
  const sections = appContent.completedSections || {};
  const fcmStates = fcm.states || {};
  const e2eArtifactOk = realDeviceE2eArtifactOk(repoRoot, e2e.artifact);
  const fcmArtifactOk = fcmArtifactStatesOk(repoRoot, fcm.artifact);

  return {
    playAppCreated: {
      ok: Boolean(
        appCreated.done &&
          appCreated.appName === "Verbal" &&
          appCreated.packageName === expectedPackageName &&
          appCreated.createdAt &&
          appCreated.consoleUrl,
      ),
      artifact: evidencePath,
    },
    internalTestingUpload: {
      ok: Boolean(
        internalUpload.done &&
          internalUpload.track === "internal" &&
          internalUpload.packageName === expectedPackageName &&
          String(internalUpload.versionCode) === versionCode &&
          String(internalUpload.aabSha256 || "").toLowerCase() === releaseSha &&
          internalUpload.uploadedAt,
      ),
      artifact: evidencePath,
    },
    preLaunchReportReviewed: {
      ok: Boolean(
        preLaunchReport.done &&
          preLaunchReport.reviewedAt &&
          /^https:\/\/\S+$/i.test(String(preLaunchReport.reportUrl || "")) &&
          preLaunchReport.completedSections?.stability &&
          preLaunchReport.completedSections?.performance &&
          preLaunchReport.completedSections?.accessibility &&
          preLaunchReport.completedSections?.screenshots &&
          preLaunchReport.noBlockingIssues === true,
      ),
      artifact: evidencePath,
    },
    closedTestingCompleted: {
      ok: closedTesting.requiredByPlayConsole === false
        ? Boolean(
            closedTesting.done &&
              closedTesting.notRequiredReason &&
              closedTesting.productionAccessReady === true,
          )
        : Boolean(
            closedTesting.done &&
              closedTesting.startedAt &&
              closedTesting.endedAt &&
              Number(closedTesting.testerCount || 0) >= 12 &&
              Number(closedTesting.continuousDays || 0) >= 14 &&
              closedTesting.feedbackReviewed === true &&
              closedTesting.productionAccessReady === true,
          ),
      artifact: evidencePath,
    },
    appContentSubmitted: {
      ok: Boolean(
        appContent.done &&
          appContent.submittedAt &&
          appContent.privacyPolicyUrl === expectedUrls.privacyPolicyUrl &&
          appContent.accountDeletionUrl === expectedUrls.accountDeletionUrl &&
          appContent.dataDeletionUrl === expectedUrls.dataDeletionUrl &&
          sections.privacyPolicy &&
          sections.appAccess &&
          sections.ads &&
          sections.dataSafety &&
          sections.accountDeletion &&
          sections.dataDeletion &&
          sections.contentRating &&
          sections.targetAudience &&
          sections.sensitivePermissions &&
          sections.ugc &&
          sections.governmentApp &&
          sections.financialFeatures &&
          sections.health &&
          sections.appCategoryContact &&
          sections.storeListing,
      ),
      artifact: evidencePath,
    },
    realDeviceE2e: {
      ok: Boolean(
        e2e.done &&
          e2e.testedAt &&
          e2e.artifact &&
          e2eArtifactOk,
      ),
      artifact: e2e.artifact || evidencePath,
    },
    fcm: {
      ok: Boolean(
        fcm.done &&
          fcm.testedAt &&
          fcm.artifact &&
          fcmArtifactOk &&
          fcmStates.foreground &&
          fcmStates.background &&
          fcmStates.terminated &&
          fcmStates.lockScreen,
      ),
      artifact: fcm.artifact || evidencePath,
    },
  };
}

function buildLaunchEvidenceChecks({evidence, androidRelease, repoRoot}) {
  const checks = [];
  const appCreated = evidence?.playConsole?.appCreated || {};
  const internalUpload = evidence?.playConsole?.internalTestingUpload || {};
  const preLaunchReport = evidence?.playConsole?.preLaunchReportReviewed || {};
  const closedTesting = evidence?.playConsole?.closedTestingCompleted || {};
  const appContent = evidence?.playConsole?.appContentSubmitted || {};
  const e2e = evidence?.realDevice?.e2e || {};
  const fcm = evidence?.realDevice?.fcm || {};
  const sections = appContent.completedSections || {};
  const fcmStates = fcm.states || {};
  const expectedSha = String(androidRelease?.release?.sha256 || "").toLowerCase();
  const expectedVersionCode = String(androidRelease?.android?.versionCode || "");
  const gates = evaluateManualEvidence({evidence, androidRelease, repoRoot});

  add(checks, "manual_evidence_file_loaded", Boolean(evidence), {});
  add(checks, "android_release_verification_loaded", Boolean(androidRelease?.ok), {
    expectedSha,
    expectedVersionCode,
  });

  add(checks, "play_app_created_done", appCreated.done === true, {});
  add(checks, "play_app_created_name", appCreated.appName === "Verbal", {
    actual: appCreated.appName || "",
  });
  add(checks, "play_app_created_package", appCreated.packageName === expectedPackageName, {
    actual: appCreated.packageName || "",
  });
  add(checks, "play_app_created_timestamp_present", isNonEmpty(appCreated.createdAt), {});
  add(checks, "play_app_created_console_url_present", isNonEmpty(appCreated.consoleUrl), {});
  add(checks, "play_app_created_gate", gates.playAppCreated.ok, {});

  add(checks, "internal_upload_done", internalUpload.done === true, {});
  add(checks, "internal_upload_track", internalUpload.track === "internal", {
    actual: internalUpload.track || "",
  });
  add(checks, "internal_upload_package", internalUpload.packageName === expectedPackageName, {
    actual: internalUpload.packageName || "",
  });
  add(checks, "internal_upload_version_code_matches_release", String(internalUpload.versionCode || "") === expectedVersionCode, {
    actual: String(internalUpload.versionCode || ""),
    expected: expectedVersionCode,
  });
  add(checks, "internal_upload_aab_sha_matches_release", String(internalUpload.aabSha256 || "").toLowerCase() === expectedSha, {
    actual: String(internalUpload.aabSha256 || "").toLowerCase(),
    expected: expectedSha,
  });
  add(checks, "internal_upload_timestamp_present", isNonEmpty(internalUpload.uploadedAt), {});
  add(checks, "internal_upload_gate", gates.internalTestingUpload.ok, {});

  add(checks, "prelaunch_report_done", preLaunchReport.done === true, {});
  add(checks, "prelaunch_report_timestamp_present", isNonEmpty(preLaunchReport.reviewedAt), {});
  add(checks, "prelaunch_report_url_present", /^https:\/\/\S+$/i.test(String(preLaunchReport.reportUrl || "")), {
    actual: preLaunchReport.reportUrl || "",
  });
  for (const section of ["stability", "performance", "accessibility", "screenshots"]) {
    add(
      checks,
      `prelaunch_report_section_${section}`,
      preLaunchReport.completedSections?.[section] === true,
      {},
    );
  }
  add(checks, "prelaunch_report_no_blocking_issues", preLaunchReport.noBlockingIssues === true, {});
  add(checks, "prelaunch_report_gate", gates.preLaunchReportReviewed.ok, {});

  add(checks, "closed_testing_done", closedTesting.done === true, {});
  add(checks, "closed_testing_required_flag_present", typeof closedTesting.requiredByPlayConsole === "boolean", {
    actual: closedTesting.requiredByPlayConsole,
  });
  if (closedTesting.requiredByPlayConsole === false) {
    add(checks, "closed_testing_not_required_reason_present", isNonEmpty(closedTesting.notRequiredReason), {});
  } else {
    add(checks, "closed_testing_started_at_present", isNonEmpty(closedTesting.startedAt), {});
    add(checks, "closed_testing_ended_at_present", isNonEmpty(closedTesting.endedAt), {});
    add(checks, "closed_testing_tester_count_at_least_12", Number(closedTesting.testerCount || 0) >= 12, {
      actual: Number(closedTesting.testerCount || 0),
    });
    add(checks, "closed_testing_continuous_days_at_least_14", Number(closedTesting.continuousDays || 0) >= 14, {
      actual: Number(closedTesting.continuousDays || 0),
    });
    add(checks, "closed_testing_feedback_reviewed", closedTesting.feedbackReviewed === true, {});
  }
  add(checks, "closed_testing_production_access_ready", closedTesting.productionAccessReady === true, {});
  add(checks, "closed_testing_gate", gates.closedTestingCompleted.ok, {});

  add(checks, "app_content_done", appContent.done === true, {});
  add(checks, "app_content_timestamp_present", isNonEmpty(appContent.submittedAt), {});
  for (const [field, expected] of Object.entries(expectedUrls)) {
    add(checks, `app_content_${field}_matches`, appContent[field] === expected, {
      actual: appContent[field] || "",
      expected,
    });
  }
  for (const section of [
    "privacyPolicy",
    "appAccess",
    "ads",
    "dataSafety",
    "accountDeletion",
    "dataDeletion",
    "contentRating",
    "targetAudience",
    "sensitivePermissions",
    "ugc",
    "governmentApp",
    "financialFeatures",
    "health",
    "appCategoryContact",
    "storeListing",
  ]) {
    add(checks, `app_content_section_${section}`, sections[section] === true, {});
  }
  add(checks, "app_content_gate", gates.appContentSubmitted.ok, {});

  add(checks, "real_device_e2e_done", e2e.done === true, {});
  add(checks, "real_device_e2e_timestamp_present", isNonEmpty(e2e.testedAt), {});
  add(checks, "real_device_e2e_artifact_exists", isNonEmpty(e2e.artifact) && artifactExists(repoRoot, e2e.artifact), {
    artifact: e2e.artifact || "",
  });
  add(checks, "real_device_e2e_artifact_valid", realDeviceE2eArtifactOk(repoRoot, e2e.artifact), {
    artifact: e2e.artifact || "",
  });
  add(checks, "real_device_e2e_gate", gates.realDeviceE2e.ok, {});

  add(checks, "fcm_done", fcm.done === true, {});
  add(checks, "fcm_timestamp_present", isNonEmpty(fcm.testedAt), {});
  add(checks, "fcm_artifact_exists", isNonEmpty(fcm.artifact) && artifactExists(repoRoot, fcm.artifact), {
    artifact: fcm.artifact || "",
  });
  add(checks, "fcm_artifact_states_verified", fcmArtifactStatesOk(repoRoot, fcm.artifact), {
    artifact: fcm.artifact || "",
  });
  for (const state of ["foreground", "background", "terminated", "lockScreen"]) {
    add(checks, `fcm_state_${state}`, fcmStates[state] === true, {});
  }
  add(checks, "fcm_gate", gates.fcm.ok, {});

  return {checks, gates};
}

function add(checks, name, ok, detail) {
  checks.push({name, ok: Boolean(ok), detail});
}

function isNonEmpty(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function artifactExists(repoRoot, artifact) {
  if (!isNonEmpty(artifact)) {
    return false;
  }
  return fs.existsSync(path.join(repoRoot, artifact));
}

function readArtifactJson(repoRoot, artifact) {
  if (!artifactExists(repoRoot, artifact) || !String(artifact).endsWith(".json")) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(path.join(repoRoot, artifact), "utf8").replace(/^\uFEFF/, ""));
  } catch {
    return null;
  }
}

function hasCheck(report, name) {
  return Array.isArray(report?.checks) &&
    report.checks.some((check) => check.name === name && check.ok);
}

function realDeviceE2eArtifactOk(repoRoot, artifact) {
  const report = readArtifactJson(repoRoot, artifact);
  return Boolean(
    report?.ok === true &&
      report?.deviceId &&
      report?.dryRun !== true &&
      hasCheck(report, "manual_e2e_confirmed") &&
      !hasCheck(report, "precheck_completed") &&
      !hasCheck(report, "dry_run_completed"),
  );
}

function fcmArtifactStatesOk(repoRoot, artifact) {
  const report = readArtifactJson(repoRoot, artifact);
  const states = report?.states || {};
  return Boolean(
    report?.ok === true &&
      report?.deviceId &&
      report?.dryRun !== true &&
      states.foreground === true &&
      states.background === true &&
      states.terminated === true &&
      states.lockScreen === true &&
      !hasCheck(report, "dry_run_completed"),
  );
}

module.exports = {
  buildLaunchEvidenceChecks,
  evaluateManualEvidence,
};
