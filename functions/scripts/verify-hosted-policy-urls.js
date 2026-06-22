const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const jsonPath = path.join(artifactDir, `hosted-policy-url-verification-${runId}.json`);
const mdPath = path.join(artifactDir, `hosted-policy-url-verification-${runId}.md`);
const latestJsonPath = path.join(artifactDir, "hosted-policy-url-verification-latest.json");
const latestMdPath = path.join(artifactDir, "hosted-policy-url-verification-latest.md");

const targets = [
  {
    name: "home",
    url: "https://verbal.chat",
    expected: ["Verbal"],
  },
  {
    name: "privacy",
    url: "https://verbal.chat/privacy",
    expected: ["Verbal", "개인정보처리방침", "support@verbal.chat"],
  },
  {
    name: "terms",
    url: "https://verbal.chat/terms",
    expected: ["Verbal", "이용약관", "support@verbal.chat"],
  },
  {
    name: "community_guidelines",
    url: "https://verbal.chat/community-guidelines",
    expected: ["Verbal", "커뮤니티 운영정책", "support@verbal.chat"],
  },
  {
    name: "account_delete",
    url: "https://verbal.chat/account/delete",
    expected: ["Verbal", "계정 삭제 요청", "support@verbal.chat"],
  },
  {
    name: "data_deletion",
    url: "https://verbal.chat/data-deletion",
    expected: ["Verbal", "데이터 삭제 정책", "support@verbal.chat"],
  },
  {
    name: "firebase_account_delete_fallback",
    url: "https://voice-messenger-jangs-260522.web.app/account/delete",
    expected: ["Verbal", "계정 삭제 요청", "support@verbal.chat"],
  },
];

main().catch((error) => {
  fs.mkdirSync(artifactDir, {recursive: true});
  const result = {
    ok: false,
    generatedAt: new Date().toISOString(),
    error: String(error?.stack || error),
    checks: [],
    artifact: path.relative(repoRoot, jsonPath),
  };
  writeArtifacts(result);
  console.error(JSON.stringify(result, null, 2));
  process.exitCode = 1;
});

async function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const checks = [];

  for (const target of targets) {
    const fetched = await fetchText(target.url);
    const title = extractTitle(fetched.body);
    const contentType = fetched.headers["content-type"] || "";
    const requiredTextChecks = target.expected.map((text) => ({
      text,
      ok: fetched.body.includes(text),
    }));
    const ok = Boolean(
      fetched.ok &&
        fetched.status >= 200 &&
        fetched.status < 300 &&
        /text\/html/i.test(contentType) &&
        requiredTextChecks.every((item) => item.ok),
    );
    checks.push({
      name: target.name,
      ok,
      url: target.url,
      status: fetched.status,
      contentType,
      title,
      length: fetched.body.length,
      expected: requiredTextChecks,
      error: fetched.error,
    });
  }

  const failed = checks.filter((check) => !check.ok);
  const result = {
    ok: failed.length === 0,
    generatedAt: new Date().toISOString(),
    checkedUrls: checks.length,
    passedCount: checks.length - failed.length,
    failedCount: failed.length,
    checks,
    artifact: path.relative(repoRoot, jsonPath),
    markdown: path.relative(repoRoot, mdPath),
  };
  writeArtifacts(result);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}

async function fetchText(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: {"User-Agent": "verbal-policy-url-verifier/1.0"},
    });
    const body = await response.text();
    return {
      ok: response.ok,
      status: response.status,
      headers: Object.fromEntries(response.headers.entries()),
      body,
      error: "",
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      headers: {},
      body: "",
      error: String(error?.message || error),
    };
  } finally {
    clearTimeout(timeout);
  }
}

function extractTitle(html) {
  return /<title>(.*?)<\/title>/is.exec(html)?.[1]?.replace(/\s+/g, " ").trim() || "";
}

function writeArtifacts(result) {
  writeJson(jsonPath, result);
  writeJson(latestJsonPath, result);
  const markdown = renderMarkdown(result);
  fs.writeFileSync(mdPath, markdown, "utf8");
  fs.writeFileSync(latestMdPath, markdown, "utf8");
}

function renderMarkdown(result) {
  return `# Verbal Hosted Policy URL Verification

Generated: ${result.generatedAt}

- Overall result: ${result.ok ? "PASS" : "FAIL"}
- Checked URLs: ${result.checkedUrls || 0}
- Passed: ${result.passedCount || 0}
- Failed: ${result.failedCount || 0}

| URL | Status | Result | Title |
|---|---:|---|---|
${(result.checks || [])
  .map((check) => `| ${check.url} | ${check.status} | ${check.ok ? "PASS" : "FAIL"} | ${escapeTable(check.title || "")} |`)
  .join("\n")}

## Required Text Checks

${(result.checks || [])
  .map((check) => {
    const expected = (check.expected || [])
      .map((item) => `  - ${item.ok ? "PASS" : "FAIL"}: \`${item.text}\``)
      .join("\n");
    return `### ${check.name}\n\n- URL: ${check.url}\n- Content-Type: ${check.contentType || "n/a"}\n- Error: ${check.error || "n/a"}\n${expected}`;
  })
  .join("\n\n")}

Use this artifact before filling Google Play App content and Data Safety URLs.
`;
}

function escapeTable(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\r?\n/g, " ");
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
