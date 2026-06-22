const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const outputDir = path.join(repoRoot, "artifacts", "play-console");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const htmlPath = path.join(outputDir, `verbal-app-content-copy-sheet-${runId}.html`);
const latestHtmlPath = path.join(outputDir, "verbal-app-content-copy-sheet-latest.html");
const answersPath = path.join(outputDir, "verbal-app-content-answers-latest.json");

main();

function main() {
  fs.mkdirSync(outputDir, {recursive: true});
  const answers = readJson(answersPath);
  const storeListing = readStoreListing();
  const html = renderHtml(answers, storeListing);
  fs.writeFileSync(htmlPath, html, "utf8");
  fs.writeFileSync(latestHtmlPath, html, "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        html: relative(htmlPath),
        latest: relative(latestHtmlPath),
        sections: answers.consoleSections.length,
      },
      null,
      2,
    ),
  );
}

function readStoreListing() {
  return {
    koShort: readText("artifacts/store/google-play/ko-KR/short-description.txt"),
    koFull: readText("artifacts/store/google-play/ko-KR/full-description.txt"),
    koReleaseNotes: readText("artifacts/store/google-play/ko-KR/release-notes-internal.txt"),
    enShort: readText("artifacts/store/google-play/en-US/short-description.txt"),
    enFull: readText("artifacts/store/google-play/en-US/full-description.txt"),
    enReleaseNotes: readText("artifacts/store/google-play/en-US/release-notes-internal.txt"),
    assets: [
      "artifacts/store/google-play/assets/app-icon-512.png",
      "artifacts/store/google-play/assets/feature-graphic-1024x500.png",
      "artifacts/store/google-play/assets/phone-screenshots/01-home.png",
      "artifacts/store/google-play/assets/phone-screenshots/02-voice-chat.png",
      "artifacts/store/google-play/assets/phone-screenshots/03-calendar.png",
      "artifacts/store/google-play/assets/phone-screenshots/04-create-chat.png",
      "artifacts/store/google-play/assets/phone-screenshots/05-settings-menu.png",
    ],
  };
}

function renderHtml(answers, storeListing) {
  const sections = answers.consoleSections
    .map((section, index) => renderSection(section, index))
    .join("\n");
  const quickAnswers = answers.dataSafety.consoleQuickAnswers
    .map(
      (item) => `
        <tr>
          <td>${escapeHtml(item.question)}</td>
          <td><code>${escapeHtml(item.answer)}</code></td>
          <td>${copyButton(item.answer)}</td>
        </tr>`,
    )
    .join("\n");
  const dataTypes = answers.dataSafety.detailMatrix
    .map(
      (item) => `
        <tr>
          <td>${escapeHtml(item.category)}</td>
          <td>${escapeHtml(item.dataType)}</td>
          <td>${escapeHtml(item.collected)}</td>
          <td>${escapeHtml(item.shared)}</td>
          <td>${escapeHtml(item.required)}</td>
          <td>${escapeHtml(item.purposes)}</td>
          <td>${escapeHtml(item.deletionHandling)}</td>
        </tr>`,
    )
    .join("\n");
  const assets = storeListing.assets
    .map((asset) => `<li><code>${escapeHtml(asset)}</code> ${copyButton(asset)}</li>`)
    .join("\n");

  return `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Verbal Play Console App Content Copy Sheet</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f7faf8;
      --panel: #ffffff;
      --text: #101815;
      --muted: #66736e;
      --line: #dce8e2;
      --green: #00a970;
      --green-dark: #006b49;
      --code: #eef8f3;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Arial, "Malgun Gothic", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
    }
    header {
      position: sticky;
      top: 0;
      z-index: 10;
      background: rgba(247, 250, 248, 0.96);
      border-bottom: 1px solid var(--line);
      padding: 18px 24px;
      backdrop-filter: blur(10px);
    }
    main {
      max-width: 1120px;
      margin: 0 auto;
      padding: 24px;
    }
    h1, h2, h3 { margin: 0 0 10px; }
    h1 { font-size: 24px; }
    h2 { font-size: 20px; margin-top: 28px; }
    h3 { font-size: 16px; }
    p { margin: 6px 0; color: var(--muted); }
    .grid {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 16px;
      box-shadow: 0 8px 20px rgba(18, 50, 35, 0.06);
    }
    .section-card {
      display: grid;
      grid-template-columns: auto 1fr auto;
      gap: 12px;
      align-items: start;
    }
    .section-card input { margin-top: 4px; }
    code, pre {
      background: var(--code);
      border-radius: 8px;
      color: var(--green-dark);
    }
    code { padding: 2px 6px; }
    pre {
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      padding: 12px;
      margin: 8px 0 0;
    }
    button {
      border: 0;
      border-radius: 999px;
      background: var(--green);
      color: white;
      cursor: pointer;
      font-weight: 700;
      padding: 8px 12px;
    }
    button.secondary {
      background: #e5f8ef;
      color: var(--green-dark);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      overflow: hidden;
    }
    th, td {
      border-bottom: 1px solid var(--line);
      padding: 10px;
      text-align: left;
      vertical-align: top;
      font-size: 14px;
    }
    th { background: #edf8f2; }
    tr:last-child td { border-bottom: 0; }
    .muted { color: var(--muted); }
    .record {
      border-left: 4px solid var(--green);
    }
    .toast {
      position: fixed;
      right: 18px;
      bottom: 18px;
      display: none;
      background: #101815;
      color: white;
      border-radius: 10px;
      padding: 10px 14px;
      box-shadow: 0 10px 28px rgba(0, 0, 0, 0.2);
    }
    ul { padding-left: 18px; }
  </style>
</head>
<body>
  <header>
    <h1>Verbal Play Console App Content Copy Sheet</h1>
    <p>생성 시간: ${escapeHtml(answers.generatedAt)}. Google Play Console 입력 보조용 로컬 파일입니다. 모든 섹션 저장 후 증거 기록 커맨드를 실행하세요.</p>
  </header>
  <main>
    <section class="grid">
      ${valueCard("앱 이름", answers.appIdentity.appName)}
      ${valueCard("패키지명", answers.appIdentity.packageName)}
      ${valueCard("지원 이메일", answers.appIdentity.supportEmail)}
      ${valueCard("개인정보처리방침", answers.policyUrls.privacyPolicy)}
      ${valueCard("계정 삭제 URL", answers.policyUrls.accountDeletion)}
      ${valueCard("데이터 삭제 URL", answers.policyUrls.dataDeletion)}
    </section>

    <h2>1. Console Section Flow</h2>
    <p>각 항목을 Play Console에서 저장한 뒤 왼쪽 체크박스를 표시하면 브라우저에만 진행 상태가 저장됩니다.</p>
    <section class="grid">${sections}</section>

    <h2>2. Reviewer Access</h2>
    <section class="card">
      <p>테스트 전화번호: <code>${escapeHtml(answers.appAccess.testPhoneNumber)}</code> ${copyButton(answers.appAccess.testPhoneNumber)}</p>
      <p>인증 코드: <code>${escapeHtml(answers.appAccess.testVerificationCode)}</code> ${copyButton(answers.appAccess.testVerificationCode)}</p>
      <p>표시명: <code>${escapeHtml(answers.appAccess.testDisplayName)}</code> ${copyButton(answers.appAccess.testDisplayName)}</p>
      <p>사용자 ID: <code>${escapeHtml(answers.appAccess.testUserId)}</code> ${copyButton(answers.appAccess.testUserId)}</p>
      <pre>${escapeHtml(answers.appAccess.instructions)}</pre>
      ${copyButton(answers.appAccess.instructions)}
    </section>

    <h2>3. Data Safety Quick Answers</h2>
    <table>
      <thead><tr><th>Console question</th><th>Answer</th><th>Copy</th></tr></thead>
      <tbody>${quickAnswers}</tbody>
    </table>

    <h2>4. Data Safety Matrix</h2>
    <table>
      <thead>
        <tr><th>Category</th><th>Data type</th><th>Collected</th><th>Shared</th><th>Required</th><th>Purposes</th><th>Retention / deletion</th></tr>
      </thead>
      <tbody>${dataTypes}</tbody>
    </table>

    <h2>5. Store Listing</h2>
    <section class="grid">
      ${textAreaCard("ko-KR 짧은 설명", storeListing.koShort)}
      ${textAreaCard("ko-KR 전체 설명", storeListing.koFull)}
      ${textAreaCard("ko-KR 내부 테스트 출시 노트", storeListing.koReleaseNotes)}
      ${textAreaCard("en-US Short description", storeListing.enShort)}
      ${textAreaCard("en-US Full description", storeListing.enFull)}
      ${textAreaCard("en-US Internal release notes", storeListing.enReleaseNotes)}
    </section>
    <section class="card">
      <h3>Assets</h3>
      <ul>${assets}</ul>
    </section>

    <h2>6. Evidence Command</h2>
    <section class="card record">
      <p>Play Console의 모든 App content/Data Safety 항목을 저장한 뒤 실행합니다.</p>
      <pre>${escapeHtml(answers.recordCommand)}</pre>
      ${copyButton(answers.recordCommand)}
    </section>
  </main>
  <div id="toast" class="toast">복사했습니다</div>
  <script>
    const toast = document.getElementById("toast");
    document.querySelectorAll("[data-copy]").forEach((button) => {
      button.addEventListener("click", async () => {
        await navigator.clipboard.writeText(button.dataset.copy);
        toast.style.display = "block";
        setTimeout(() => toast.style.display = "none", 1200);
      });
    });
    document.querySelectorAll("[data-check-key]").forEach((box) => {
      const key = "verbal-play-console-" + box.dataset.checkKey;
      box.checked = localStorage.getItem(key) === "1";
      box.addEventListener("change", () => {
        localStorage.setItem(key, box.checked ? "1" : "0");
      });
    });
  </script>
</body>
</html>`;
}

function renderSection(section, index) {
  return `<article class="card section-card">
    <input type="checkbox" data-check-key="${escapeHtml(section.evidenceFlag)}" aria-label="${escapeHtml(section.koreanName)} 완료">
    <div>
      <h3>${index + 1}. ${escapeHtml(section.koreanName)}</h3>
      <p class="muted">${escapeHtml(section.name)}</p>
      <p>${escapeHtml(section.action)}</p>
      <p><code>${escapeHtml(section.value)}</code></p>
      <p class="muted">${escapeHtml(section.evidenceFlag)}</p>
    </div>
    ${copyButton(section.value)}
  </article>`;
}

function valueCard(label, value) {
  return `<section class="card">
    <h3>${escapeHtml(label)}</h3>
    <p><code>${escapeHtml(value)}</code></p>
    ${copyButton(value)}
  </section>`;
}

function textAreaCard(label, value) {
  return `<section class="card">
    <h3>${escapeHtml(label)}</h3>
    <pre>${escapeHtml(value)}</pre>
    ${copyButton(value)}
  </section>`;
}

function copyButton(value) {
  return `<button class="secondary" type="button" data-copy="${escapeHtml(value)}">Copy</button>`;
}

function readText(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), "utf8").replace(/^\uFEFF/, "");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function relative(filePath) {
  return path.relative(repoRoot, filePath).replace(/\\/g, "/");
}
