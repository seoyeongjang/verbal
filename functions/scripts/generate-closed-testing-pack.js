const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const artifactDir = path.join(repoRoot, "artifacts", "play-console", "closed-testing");
const runId = new Date().toISOString().replace(/\D/g, "").slice(0, 14);

const jsonPath = path.join(artifactDir, `verbal-closed-testing-pack-${runId}.json`);
const mdPath = path.join(artifactDir, `verbal-closed-testing-pack-${runId}.md`);
const csvPath = path.join(artifactDir, "tester-list-template.csv");
const latestJsonPath = path.join(artifactDir, "verbal-closed-testing-pack-latest.json");
const latestMdPath = path.join(artifactDir, "verbal-closed-testing-pack-latest.md");

main();

function main() {
  fs.mkdirSync(artifactDir, {recursive: true});
  const pack = buildPack();
  writeJson(jsonPath, pack);
  writeJson(latestJsonPath, pack);
  fs.writeFileSync(mdPath, renderMarkdown(pack), "utf8");
  fs.writeFileSync(latestMdPath, renderMarkdown(pack), "utf8");
  fs.writeFileSync(csvPath, renderTesterCsv(), "utf8");
  console.log(
    JSON.stringify(
      {
        ok: true,
        json: path.relative(repoRoot, jsonPath),
        markdown: path.relative(repoRoot, mdPath),
        testerCsv: path.relative(repoRoot, csvPath),
      },
      null,
      2,
    ),
  );
}

function buildPack() {
  return {
    generatedAt: new Date().toISOString(),
    purpose:
      "Prepare Play Console internal/closed testing operation materials before public exposure.",
    scope: {
      appName: "Verbal",
      packageName: "com.voicebeta.verbal",
      testingTrack: "Internal testing first, then Closed testing if Play Console requires production access evidence.",
      publicExposure: "Do not expose to public users until launch gate is green.",
    },
    closedTestingThreshold: {
      minimumOptedInTesters: 12,
      minimumContinuousDays: 14,
      source:
        "https://support.google.com/googleplay/android-developer/answer/14151465",
      note:
        "Use this threshold when Play Console requires production access testing. If Play Console states the account/app is not subject to the requirement, record the non-required reason instead.",
    },
    testerListTemplate: {
      file: "artifacts/play-console/closed-testing/tester-list-template.csv",
      columns: ["email", "name", "device", "android_version", "joined_at", "notes"],
      minimumRows: 12,
    },
    invitationMessage: {
      subject: "[Verbal] Android closed test invitation",
      ko: [
        "안녕하세요.",
        "Verbal Android 테스트에 참여해 주셔서 감사합니다.",
        "Play Console 테스트 링크를 열고 Google 계정으로 opt-in 한 뒤 앱을 설치해 주세요.",
        "테스트 기간에는 회원가입, 메시지, 음성 STT, 음성 재생, 캘린더, 알림, 신고/차단 흐름을 실제 사용처럼 확인해 주세요.",
        "문제가 생기면 재현 단계, 화면 캡처, 기기명, Android 버전을 함께 남겨 주세요.",
        "지원/문의: support@verbal.chat",
      ],
      en: [
        "Hello,",
        "Thank you for joining the Verbal Android test.",
        "Open the Play Console test link, opt in with your Google account, then install the app.",
        "During the test, please verify sign-up, messages, voice STT, voice playback, calendar, notifications, report, and block flows as real usage.",
        "For issues, include reproduction steps, a screenshot, device model, and Android version.",
        "Support: support@verbal.chat",
      ],
    },
    dailyTesterTasks: [
      "Launch the app and confirm sign-in/session persistence.",
      "Create or enter a 1:1 chat.",
      "Send a text message.",
      "Record and send a voice message; confirm transcript and playback.",
      "Create a calendar event from voice or manual input.",
      "Open notification settings and confirm no crash.",
      "Use report/block flow only with test content.",
      "Record any crash, UI break, STT miss, delayed send, or notification failure.",
    ],
    feedbackQuestions: [
      "Did sign-up complete without confusion?",
      "Was the home/chat UI understandable without guidance?",
      "How long did voice message sending feel after tapping send?",
      "Was the STT transcript accurate enough for real use?",
      "Did voice playback work after receiving a message?",
      "Did calendar creation feel connected to the chat workflow?",
      "Did push notifications arrive in expected states?",
      "Were report/block/account deletion paths findable?",
      "What is the one issue that would stop you from using Verbal again?",
      "Would you recommend Verbal to a friend after this build? Why?",
    ],
    issueTemplate: {
      title: "[Closed Test] <short issue title>",
      fields: [
        "Tester email",
        "Device model",
        "Android version",
        "App version / versionCode",
        "Feature area",
        "Expected result",
        "Actual result",
        "Reproduction steps",
        "Screenshot or screen recording path",
        "Frequency: once / sometimes / always",
        "Severity: blocker / high / medium / low",
      ],
    },
    evidenceChecklist: [
      "Closed testing track created if required.",
      "At least 12 opted-in testers confirmed if required.",
      "14 continuous days completed if required.",
      "Tester feedback reviewed and blocking issues triaged.",
      "Production access request is ready or non-required reason is recorded.",
      "Launch evidence command has been run with matching flags.",
    ],
    recordCommands: {
      requiredClosedTesting:
        "npm run record:closed-testing-completed -- --started-at <date> --ended-at <date> --tester-count <n> --continuous-days <n>",
      notRequired:
        'npm run record:closed-testing-not-required -- --reason "<reason>"',
      status: "npm run record:launch-evidence -- status",
      gate: "npm run report:launch-gate",
    },
  };
}

function renderTesterCsv() {
  return [
    "email,name,device,android_version,joined_at,notes",
    "tester01@example.com,Tester 01,Galaxy,Android 14,,",
    "tester02@example.com,Tester 02,Pixel,Android 15,,",
  ].join("\n") + "\n";
}

function renderMarkdown(pack) {
  return `# Verbal Closed Testing Pack

Generated: ${pack.generatedAt}

## Scope

- App: ${pack.scope.appName}
- Package: \`${pack.scope.packageName}\`
- Track: ${pack.scope.testingTrack}
- Public exposure rule: ${pack.scope.publicExposure}

## Production Access Threshold

- Minimum opted-in testers: ${pack.closedTestingThreshold.minimumOptedInTesters}
- Minimum continuous days: ${pack.closedTestingThreshold.minimumContinuousDays}
- Official reference: ${pack.closedTestingThreshold.source}
- Note: ${pack.closedTestingThreshold.note}

## Tester List

- CSV template: \`${pack.testerListTemplate.file}\`
- Columns: ${pack.testerListTemplate.columns.map((item) => `\`${item}\``).join(", ")}
- Minimum rows when required: ${pack.testerListTemplate.minimumRows}

## Invitation Message

Subject: ${pack.invitationMessage.subject}

Korean:

\`\`\`text
${pack.invitationMessage.ko.join("\n")}
\`\`\`

English:

\`\`\`text
${pack.invitationMessage.en.join("\n")}
\`\`\`

## Daily Tester Tasks

${pack.dailyTesterTasks.map((item) => `- ${item}`).join("\n")}

## Feedback Questions

${pack.feedbackQuestions.map((item, index) => `${index + 1}. ${item}`).join("\n")}

## Issue Template

Title: ${pack.issueTemplate.title}

${pack.issueTemplate.fields.map((item) => `- ${item}:`).join("\n")}

## Evidence Checklist

${pack.evidenceChecklist.map((item) => `- [ ] ${item}`).join("\n")}

## Record Commands

Required closed testing:

\`\`\`powershell
${pack.recordCommands.requiredClosedTesting}
\`\`\`

Not required:

\`\`\`powershell
${pack.recordCommands.notRequired}
\`\`\`

Check status:

\`\`\`powershell
${pack.recordCommands.status}
${pack.recordCommands.gate}
\`\`\`
`;
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
