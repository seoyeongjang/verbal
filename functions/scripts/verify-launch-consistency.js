const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `launch-consistency-${runId}.json`);
const latestJsonPath = path.join(artifactDir, "launch-consistency-latest.json");

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});

  const playPack = readJsonIfExists(
    path.join(artifactDir, "play-console", "verbal-play-console-pack-latest.json"),
  );
  const androidRelease = readJsonIfExists(
    path.join(artifactDir, "android-release-verification-latest.json"),
  );
  const launchGate = readJsonIfExists(path.join(artifactDir, "launch-gate-latest.json"));
  const handoff = readJsonIfExists(path.join(artifactDir, "launch-handoff-latest.json"));
  const currentAab = getCurrentAab();
  const latestPlayPackMd = latestArtifactIn("play-console", "verbal-play-console-pack-*.md");
  const latestClosedTestingPackMd = latestArtifactIn(
    path.join("play-console", "closed-testing"),
    "verbal-closed-testing-pack-*.md",
  );
  const checks = [];

  addCheck(checks, "latest_play_console_pack_exists", Boolean(playPack), {
    path: "artifacts/play-console/verbal-play-console-pack-latest.json",
  });
  addCheck(checks, "latest_android_release_exists", Boolean(androidRelease?.ok), {
    path: "artifacts/android-release-verification-latest.json",
  });
  addCheck(checks, "latest_launch_gate_exists", Boolean(launchGate?.ok), {
    path: "artifacts/launch-gate-latest.json",
  });
  addCheck(checks, "latest_launch_handoff_exists", Boolean(handoff), {
    path: "artifacts/launch-handoff-latest.json",
  });
  addCheck(checks, "current_aab_exists", Boolean(currentAab), {
    path: "dist/android/app-release.aab",
  });

  if (playPack && androidRelease && currentAab) {
    addCheck(checks, "play_pack_aab_sha_matches_current_aab", playPack.release?.sha256 === currentAab.sha256, {
      playPackSha256: playPack.release?.sha256 || "",
      currentSha256: currentAab.sha256,
    });
    addCheck(checks, "android_release_sha_matches_current_aab", androidRelease.release?.sha256 === currentAab.sha256, {
      androidReleaseSha256: androidRelease.release?.sha256 || "",
      currentSha256: currentAab.sha256,
    });
    addCheck(checks, "play_pack_aab_size_matches_current_aab", Number(playPack.release?.bytes) === currentAab.bytes, {
      playPackBytes: playPack.release?.bytes || 0,
      currentBytes: currentAab.bytes,
    });
    addCheck(checks, "android_release_size_matches_current_aab", Number(androidRelease.release?.bytes) === currentAab.bytes, {
      androidReleaseBytes: androidRelease.release?.bytes || 0,
      currentBytes: currentAab.bytes,
    });
    addCheck(checks, "play_pack_package_matches_android_release", playPack.app?.packageName === androidRelease.android?.applicationId, {
      playPackPackage: playPack.app?.packageName || "",
      androidApplicationId: androidRelease.android?.applicationId || "",
    });
    addCheck(checks, "play_pack_firebase_app_matches_android_release", playPack.app?.firebaseAndroidAppId === androidRelease.firebase?.appId, {
      playPackFirebaseAppId: playPack.app?.firebaseAndroidAppId || "",
      androidReleaseFirebaseAppId: androidRelease.firebase?.appId || "",
    });
  }

  if (playPack && handoff) {
    addCheck(checks, "handoff_release_aab_matches_play_pack", handoff.artifacts?.releaseAab === playPack.release?.path, {
      handoffReleaseAab: handoff.artifacts?.releaseAab || "",
      playPackReleaseAab: playPack.release?.path || "",
    });
    addCheck(checks, "handoff_policy_urls_match_play_pack",
      handoff.artifacts?.privacyPolicyUrl === playPack.policyUrls?.privacyPolicy &&
        handoff.artifacts?.accountDeletionUrl === playPack.policyUrls?.accountDeletion &&
        handoff.artifacts?.dataDeletionUrl === playPack.policyUrls?.dataDeletion,
      {
        handoffPrivacy: handoff.artifacts?.privacyPolicyUrl || "",
        playPackPrivacy: playPack.policyUrls?.privacyPolicy || "",
        handoffAccountDeletion: handoff.artifacts?.accountDeletionUrl || "",
        playPackAccountDeletion: playPack.policyUrls?.accountDeletion || "",
        handoffDataDeletion: handoff.artifacts?.dataDeletionUrl || "",
        playPackDataDeletion: playPack.policyUrls?.dataDeletion || "",
      },
    );
    addCheck(checks, "handoff_points_to_existing_play_pack", artifactExists(handoff.artifacts?.playConsolePack), {
      handoffPlayConsolePack: handoff.artifacts?.playConsolePack || "",
    });
    addCheck(checks, "handoff_points_to_existing_closed_testing_pack", artifactExists(handoff.artifacts?.closedTestingPack), {
      handoffClosedTestingPack: handoff.artifacts?.closedTestingPack || "",
    });
    addCheck(checks, "handoff_points_to_latest_play_pack", handoff.artifacts?.playConsolePack === latestPlayPackMd, {
      handoffPlayConsolePack: handoff.artifacts?.playConsolePack || "",
      latestPlayConsolePack: latestPlayPackMd,
    });
    addCheck(checks, "handoff_points_to_latest_closed_testing_pack", handoff.artifacts?.closedTestingPack === latestClosedTestingPackMd, {
      handoffClosedTestingPack: handoff.artifacts?.closedTestingPack || "",
      latestClosedTestingPack: latestClosedTestingPackMd,
    });
  }

  if (launchGate && handoff) {
    addCheck(checks, "handoff_internal_readiness_matches_launch_gate",
      Boolean(handoff.status?.readyForInternalTestingUpload) === Boolean(launchGate.readyForInternalTestingUpload),
      {
        handoff: Boolean(handoff.status?.readyForInternalTestingUpload),
        launchGate: Boolean(launchGate.readyForInternalTestingUpload),
      },
    );
    addCheck(checks, "handoff_public_readiness_matches_launch_gate",
      Boolean(handoff.status?.readyForPublicUserExposure) === Boolean(launchGate.readyForPublicUserExposure),
      {
        handoff: Boolean(handoff.status?.readyForPublicUserExposure),
        launchGate: Boolean(launchGate.readyForPublicUserExposure),
      },
    );
    const handoffBlockers = Array.isArray(handoff.status?.blockers)
      ? handoff.status.blockers.slice().sort()
      : [];
    const gateBlockers = Array.isArray(launchGate.blockers)
      ? launchGate.blockers.map((item) => item.name).sort()
      : [];
    addCheck(checks, "handoff_blockers_match_launch_gate", JSON.stringify(handoffBlockers) === JSON.stringify(gateBlockers), {
      handoffBlockers,
      gateBlockers,
    });
  }

  if (playPack) {
    addCheck(checks, "play_pack_uses_public_verbal_chat_urls",
      playPack.policyUrls?.website === "https://verbal.chat" &&
        playPack.policyUrls?.privacyPolicy === "https://verbal.chat/privacy" &&
        playPack.policyUrls?.accountDeletion === "https://verbal.chat/account/delete" &&
        playPack.policyUrls?.dataDeletion === "https://verbal.chat/data-deletion",
      playPack.policyUrls || {},
    );
    addCheck(checks, "play_pack_support_email_is_public_domain", playPack.support?.email === "support@verbal.chat", {
      supportEmail: playPack.support?.email || "",
    });
  }

  const failed = checks.filter((check) => !check.ok);
  const result = {
    ok: failed.length === 0,
    checkedAt: new Date().toISOString(),
    purpose:
      "Verify that the latest Play Console pack, release artifact, launch gate, and launch handoff describe the same release candidate.",
    passedCount: checks.length - failed.length,
    failedCount: failed.length,
    failed,
    checks,
    artifact: path.relative(repoRoot, jsonPath),
  };
  writeJson(jsonPath, result);
  writeJson(latestJsonPath, result);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}

function getCurrentAab() {
  const aabPath = path.join(repoRoot, "dist", "android", "app-release.aab");
  if (!fs.existsSync(aabPath)) {
    return null;
  }
  const buffer = fs.readFileSync(aabPath);
  const stat = fs.statSync(aabPath);
  return {
    path: "dist/android/app-release.aab",
    bytes: stat.size,
    sha256: crypto.createHash("sha256").update(buffer).digest("hex"),
  };
}

function addCheck(checks, name, ok, detail) {
  checks.push({name, ok: Boolean(ok), detail});
}

function artifactExists(relativePath) {
  return typeof relativePath === "string" &&
    relativePath.length > 0 &&
    fs.existsSync(path.join(repoRoot, relativePath));
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
