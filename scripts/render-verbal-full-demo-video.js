const childProcess = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const {pathToFileURL} = require("node:url");

const repoRoot = path.resolve(__dirname, "..");
const outDir = path.join(repoRoot, "artifacts", "demo");
const htmlPath = path.join(outDir, "verbal_full_feature_demo.html");
const rawWebmPath = path.join(outDir, "verbal_full_feature_demo.raw.webm");
const webmPath = path.join(outDir, "verbal_full_feature_demo.webm");
const mp4Path = path.join(outDir, "verbal_full_feature_demo.mp4");
const previewPath = path.join(outDir, "verbal_full_feature_demo_preview.png");
const storyboardPath = path.join(outDir, "verbal_full_feature_demo_storyboard.md");

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

async function main() {
  fs.mkdirSync(outDir, {recursive: true});
  fs.writeFileSync(htmlPath, demoHtml(), "utf8");
  fs.writeFileSync(storyboardPath, storyboardMarkdown(), "utf8");

  const chromePath = findChrome();
  const port = await freePort();
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "verbal-full-demo-"));
  const chrome = childProcess.spawn(chromePath, [
    "--headless=new",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--autoplay-policy=no-user-gesture-required",
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    pathToFileURL(htmlPath).href,
  ], {stdio: ["ignore", "pipe", "pipe"]});

  let stderr = "";
  chrome.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  try {
    const tabs = await waitForJson(`http://127.0.0.1:${port}/json`, 20_000);
    const page = Array.isArray(tabs) ? tabs.find((item) => item.type === "page") || tabs[0] : tabs;
    if (!page?.webSocketDebuggerUrl) {
      throw new Error(`Chrome DevTools tab was not available. ${stderr}`);
    }
    const cdp = await CdpClient.connect(page.webSocketDebuggerUrl);
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    await cdp.send("Runtime.evaluate", {
      expression: "document.fonts ? document.fonts.ready : Promise.resolve()",
      awaitPromise: true,
    });

    const renderResult = await cdp.send("Runtime.evaluate", {
      expression: "window.renderFullFeatureDemoVideo()",
      awaitPromise: true,
      returnByValue: true,
    });
    const videoBase64 = renderResult.result?.result?.value ?? renderResult.result?.value;
    if (!videoBase64) {
      throw new Error(`Video rendering returned no data. ${JSON.stringify(renderResult)}`);
    }
    fs.writeFileSync(rawWebmPath, Buffer.from(videoBase64, "base64"));

    const previewResult = await cdp.send("Runtime.evaluate", {
      expression: "window.drawFrameAt(64); document.getElementById('stage').toDataURL('image/png').split(',')[1]",
      awaitPromise: true,
      returnByValue: true,
    });
    const previewBase64 = previewResult.result?.result?.value ?? previewResult.result?.value;
    fs.writeFileSync(previewPath, Buffer.from(previewBase64, "base64"));
    cdp.close();
  } finally {
    await stopProcess(chrome);
    safeRemoveDir(userDataDir);
  }

  const ffmpegPath = findPlaywrightFfmpeg();
  if (ffmpegPath) {
    normalizeWebmDuration(ffmpegPath, rawWebmPath, webmPath);
    convertMp4(ffmpegPath, webmPath, mp4Path);
  } else {
    fs.copyFileSync(rawWebmPath, webmPath);
  }

  console.log(JSON.stringify({
    htmlPath,
    webmPath,
    mp4Path: fs.existsSync(mp4Path) ? mp4Path : null,
    previewPath,
    storyboardPath,
  }, null, 2));
}

function storyboardMarkdown() {
  return `# Verbal Full Feature Demo

Maximum length: 96 seconds.

This is a screen-only, real-user-style mobile demo. It covers the current user-facing Verbal feature set:

1. Phone signup, SMS code, nickname, and user ID setup.
2. DM inbox with notes, contacts, message/channel tabs, sponsored slot, and hamburger settings.
3. Profile, invite QR, friends, saved messages, notification/privacy/data/language/theme/support/policy menu structure.
4. Voice message recording with STT, instant send, playable voice, and received transcript reply.
5. Message edit, delete, reaction, search, translation, schedule, media/file/location attachments.
6. Message pin, pinned banner, long-press unpin action.
7. Monthly calendar, today shortcut, upcoming card, country holidays.
8. Voice calendar creation with automatic save and completion voice guidance.
9. Event detail editing with notes/details.
10. Reminder lead time, morning briefing, Google Calendar and Apple Calendar sync.
11. Chat room calendar proposal, candidate voting, finalize, and add-to-calendar.
`;
}

function findChrome() {
  const candidates = [
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  ];
  const found = candidates.find((candidate) => fs.existsSync(candidate));
  if (!found) {
    throw new Error("Chrome or Edge was not found.");
  }
  return found;
}

function findPlaywrightFfmpeg() {
  const root = path.join(os.homedir(), "AppData", "Local", "ms-playwright");
  if (!fs.existsSync(root)) {
    return null;
  }
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.name.toLowerCase() === "ffmpeg-win64.exe") {
        return full;
      }
    }
  }
  return null;
}

function normalizeWebmDuration(ffmpegPath, inputPath, outputPath) {
  const result = childProcess.spawnSync(ffmpegPath, [
    "-y",
    "-i", inputPath,
    "-t", "96.5",
    "-c:v", "libvpx",
    "-auto-alt-ref", "0",
    "-b:v", "3600k",
    outputPath,
  ], {encoding: "utf8"});
  if (result.status !== 0 || !fs.existsSync(outputPath)) {
    console.warn("WebM duration normalization skipped.");
    fs.copyFileSync(inputPath, outputPath);
  }
}

function convertMp4(ffmpegPath, inputPath, outputPath) {
  const result = childProcess.spawnSync(ffmpegPath, [
    "-y",
    "-i", inputPath,
    "-an",
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    outputPath,
  ], {encoding: "utf8"});
  if (result.status !== 0 || !fs.existsSync(outputPath)) {
    console.warn("MP4 conversion skipped.");
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
}

function waitForJson(url, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      http.get(url, (response) => {
        let body = "";
        response.on("data", (chunk) => {
          body += chunk;
        });
        response.on("end", () => {
          if (response.statusCode === 200) {
            try {
              resolve(JSON.parse(body));
            } catch (error) {
              reject(error);
            }
            return;
          }
          retry();
        });
      }).on("error", retry);
    };
    const retry = () => {
      if (Date.now() - started > timeoutMs) {
        reject(new Error(`Timed out waiting for ${url}`));
        return;
      }
      setTimeout(tick, 250);
    };
    tick();
  });
}

function stopProcess(processHandle) {
  return new Promise((resolve) => {
    if (processHandle.exitCode !== null || processHandle.killed) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      if (processHandle.exitCode === null) {
        processHandle.kill("SIGKILL");
      }
      resolve();
    }, 2000);
    processHandle.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
    processHandle.kill();
  });
}

function safeRemoveDir(dir) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      fs.rmSync(dir, {recursive: true, force: true});
      return;
    } catch {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 150);
    }
  }
}

class CdpClient {
  static connect(url) {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.onopen = () => resolve(new CdpClient(socket));
      socket.onerror = () => reject(new Error("CDP socket failed."));
    });
  }

  constructor(socket) {
    this.socket = socket;
    this.id = 0;
    this.pending = new Map();
    socket.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id && this.pending.has(message.id)) {
        const pending = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) {
          pending.reject(new Error(JSON.stringify(message.error)));
        } else {
          pending.resolve(message);
        }
      }
    };
  }

  send(method, params = {}) {
    const id = ++this.id;
    const payload = JSON.stringify({id, method, params});
    return new Promise((resolve, reject) => {
      this.pending.set(id, {resolve, reject});
      this.socket.send(payload);
    });
  }

  close() {
    this.socket.close();
  }
}

function demoHtml() {
  return String.raw`<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Verbal Full Feature Demo</title>
  <style>
    html, body { margin: 0; width: 100%; height: 100%; background: #111; overflow: hidden; }
    body { display: grid; place-items: center; }
    canvas {
      display: block;
      width: min(100vw, 56.25vh);
      height: min(177.7778vw, 100vh);
      background: #fff;
    }
  </style>
</head>
<body>
<canvas id="stage" width="1080" height="1920"></canvas>
<script>
const canvas = document.getElementById("stage");
const ctx = canvas.getContext("2d");
const W = canvas.width;
const H = canvas.height;
const DURATION = 96;
const FPS = 24;
const green = "#00A86B";
const green2 = "#008F6E";
const mint = "#E8FFF4";
const ink = "#111";
const muted = "#667085";

const contacts = [
  ["민지", "M", "#00A86B", "오늘 8시 가능?"],
  ["지훈", "J", "#23C48E", "Sea ranch this week..."],
  ["리키", "R", "#35C987", "사진 공유 완료"],
  ["알렉스", "A", "#1FBF84", "Boo!"],
  ["서연", "S", "#0095F6", "회의 링크 보냄"],
  ["현우", "H", "#7C3AED", "파일 확인"],
  ["유나", "Y", "#FF4D67", "위치 공유"],
  ["태오", "T", "#F97316", "일정 투표"],
  ["다은", "D", "#0EA5E9", "브리핑 확인"],
  ["하린", "H", "#64748B", "쿠폰 공유"]
];

function clamp(x) { return Math.max(0, Math.min(1, x)); }
function ease(x) { x = clamp(x); return x * x * (3 - 2 * x); }
function seg(t, a, b) { return ease((t - a) / (b - a)); }
function clear(bg = "#fff") { ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H); }
function rr(x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
function fillRound(x, y, w, h, r, color) { ctx.fillStyle = color; rr(x, y, w, h, r); ctx.fill(); }
function strokeRound(x, y, w, h, r, color, line = 2) { ctx.strokeStyle = color; ctx.lineWidth = line; rr(x, y, w, h, r); ctx.stroke(); }
function circle(x, y, r, color) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); }
function line(x1, y1, x2, y2, color, width = 5) { ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = "round"; ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
function text(s, x, y, size = 32, weight = 700, color = ink, align = "left") {
  ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = "top";
  ctx.font = weight + " " + size + "px 'Malgun Gothic', 'Apple SD Gothic Neo', 'Noto Sans KR', 'Segoe UI', sans-serif";
  ctx.fillText(s, x, y);
}
function wrapText(s, x, y, maxWidth, lineHeight, size = 30, weight = 700, color = ink, maxLines = 4) {
  ctx.fillStyle = color; ctx.textAlign = "left"; ctx.textBaseline = "top";
  ctx.font = weight + " " + size + "px 'Malgun Gothic', 'Apple SD Gothic Neo', 'Noto Sans KR', 'Segoe UI', sans-serif";
  let lineText = ""; let yy = y; let lines = 0;
  for (const ch of [...s]) {
    const next = lineText + ch;
    if (ctx.measureText(next).width > maxWidth && lineText) {
      ctx.fillText(lineText, x, yy);
      lineText = ch; yy += lineHeight; lines++;
      if (lines >= maxLines - 1) break;
    } else {
      lineText = next;
    }
  }
  if (lineText) ctx.fillText(lineText, x, yy);
}
function status() {
  text("9:41", 52, 34, 30, 900);
  text("▰ ᯤ ◼", 850, 34, 28, 900);
}
function navHome() { fillRound(414, 1870, 252, 10, 5, "#111"); }
function topBar(title, opts = {}) {
  clear(opts.bg || "#fff"); status();
  if (opts.menu) text("☰", 48, 112, 58, 900);
  if (opts.back) text("‹", 48, 106, 72, 600);
  text(title, opts.back ? 122 : 122, 132, 42, 900);
  if (opts.calendar) text("▣", 820, 120, 38, 900);
  if (opts.plus) text("+", 958, 112, 52, 700);
  if (opts.more) text("•••", 932, 116, 42, 900);
  navHome();
}
function avatar(x, y, letter, color = green, r = 46, online = false) {
  circle(x, y, r + 7, "#fff"); circle(x, y, r + 3, green); circle(x, y, r, color);
  text(letter, x, y - r * 0.58, r * 0.9, 900, "#fff", "center");
  if (online) { circle(x + r * 0.7, y + r * 0.68, 12, green); circle(x + r * 0.7, y + r * 0.68, 7, "#fff"); }
}
function chip(x, y, label, active = false, w = 300) {
  fillRound(x, y, w, 58, 16, active ? "#DCFCEB" : "#F0F1F4");
  text(label, x + w / 2, y + 15, 25, 900, active ? green : ink, "center");
}
function touch(t, x, y, a, b) {
  const p = seg(t, a, b); if (!p || p >= 1) return;
  circle(x, y, 20 + 55 * p, "rgba(0,168,107," + (0.24 * (1 - p)) + ")");
  circle(x, y, 16, "rgba(0,168,107,0.88)");
}
function phoneSignup(t) {
  const p = seg(t, 0, 8);
  clear("#F4FFF9"); status();
  text("Verbal", 56, 136, 64, 900);
  text("음성으로 메시지와 일정을 처리합니다", 56, 218, 32, 800, muted);
  fillRound(54, 326, 972, 96, 26, "#fff"); text("+82 10 4821 0927", 92, 354, 39, 900);
  fillRound(54, 460, 972, 88, 28, green); text("SMS 인증번호 받기", 540, 484, 33, 900, "#fff", "center");
  if (p > 0.28) { fillRound(54, 620, 972, 96, 26, "#fff"); text("428913", 92, 648, 40, 900); text("인증 완료", 56, 748, 32, 900, green); }
  if (p > 0.52) {
    fillRound(54, 830, 972, 86, 24, "#fff"); text("민지", 92, 852, 36, 900);
    fillRound(54, 942, 972, 86, 24, "#fff"); text("minji_2026", 92, 964, 36, 900);
    text("ID 허용: 한국어, 영어, 일본어, 중국어, 숫자, _", 60, 1048, 24, 800, muted);
    fillRound(54, 1120, 972, 88, 30, ink); text("프로필 만들기", 540, 1144, 33, 900, "#fff", "center");
  }
  if (p > 0.78) { fillRound(54, 1280, 972, 120, 30, "#fff"); text("연락처 10명 동기화 완료", 100, 1318, 36, 900, green); }
  touch(t, 540, 504, 1.2, 1.8); touch(t, 540, 1164, 6.3, 6.9); navHome();
}
function inboxAndMenu(t) {
  const p = seg(t, 8, 18);
  topBar("demo", {menu: true, calendar: true, plus: true});
  for (let i = 0; i < 4; i++) {
    const c = contacts[i]; const x = 126 + i * 230;
    fillRound(x - 72, 258, 144, 48, 20, "#fff"); strokeRound(x - 72, 258, 144, 48, 20, "#E5E7EB");
    text(i === 0 ? "Share a thought..." : c[3], x, 269, 18, 800, ink, "center");
    avatar(x, 360, c[1], c[2], 56, i === 0 || i === 3);
    text(i === 0 ? "Your note" : c[0], x, 430, 21, 800, muted, "center");
  }
  chip(38, 516, "• 메시지", true, 470); chip(540, 516, "채널", false, 470);
  for (let i = 0; i < 3; i++) {
    const c = contacts[i]; const y = 650 + i * 138;
    avatar(104, y + 46, c[1], c[2], 44, i === 0);
    text(c[0], 174, y + 14, 31, 900);
    text(["오늘 8시 가능합니까? · 8m", "음성 답장 도착 · now", "사진과 위치를 보냈습니다 · 2h"][i], 174, y + 54, 25, 800, muted);
    text("▣", 970, y + 34, 32, 700, "#8A94A6", "center");
  }
  fillRound(42, 1084, 996, 104, 18, "#F8FAFC"); strokeRound(42, 1084, 996, 104, 18, "#E4E7EC");
  text("스폰서드", 154, 1106, 27, 900); text("대화방 밖에서만 노출되는 네이티브 광고", 154, 1142, 23, 800, muted); text("광고", 952, 1130, 22, 900, muted, "center");
  if (p > 0.44) menuSheet(p);
  touch(t, 72, 142, 11.4, 12.0);
}
function menuSheet(p) {
  fillRound(0, 0, 760, H, 0, "#fff");
  text("Verbal", 46, 82, 48, 900); text("@minji_2026", 46, 142, 27, 800, muted);
  const sections = [
    ["계정/관계", "내 프로필 · 초대 링크/QR", "친구/연락처", "저장한 메시지"],
    ["대화/데이터", "데이터 및 저장 공간", "대화 백업 및 복원", "권한 관리"],
    ["설정", "알림 설정", "개인정보 및 보안", "언어 · 테마"],
    ["안전/지원", "안전센터", "고객지원", "공지사항"],
    ["정보/정책", "약관 및 정책", "앱 정보", "오픈소스 라이선스"],
    ["계정 상태", "로그아웃", "", ""]
  ];
  let y = 230;
  for (const section of sections) {
    text(section[0], 46, y, 22, 900, green); y += 42;
    for (let i = 1; i < section.length; i++) if (section[i]) { text(section[i], 70, y, 30, 850); y += 54; }
    y += 12;
  }
  if (p > 0.74) {
    fillRound(410, 184, 308, 308, 28, mint); text("QR", 564, 290, 80, 900, green, "center");
    text("내 프로필에서 초대 링크와 QR 공유", 564, 512, 24, 900, green, "center");
  }
}
function chatShell(title = "Minji") {
  topBar(title, {back: true, more: true, bg: "#fff"});
  text("☎", 704, 128, 36, 900); text("▣", 822, 128, 36, 900);
}
function bubble(x, y, w, h, mine, msg, meta, voice = false) {
  fillRound(x, y, w, h, 30, mine ? green : "#F0F1F4");
  wrapText(msg, x + 30, y + 24, w - 60, 38, 30, 800, mine ? "#fff" : ink, 4);
  if (voice) { circle(x - 36, y + h - 40, 24, green); text("▶", x - 36, y + h - 52, 25, 900, "#fff", "center"); }
  text(meta, x + w - 118, y + h - 40, 23, 700, mine ? "#CFFAEA" : "#8A94A6");
}
function composer(recording = false) {
  fillRound(0, 1658, W, 262, 0, "#fff"); strokeRound(0, 1658, W, 1, 0, "#E4E7EC");
  fillRound(46, 1718, 112, 86, 30, green); text("▣", 102, 1740, 32, 900, "#fff", "center");
  fillRound(190, 1718, 586, 86, 32, "#EFFAF4"); text(recording ? "녹음 중 00:28" : "메시지...", 230, 1742, 32, 800, recording ? "#D92D20" : muted);
  text("🎙", 830, 1738, 36, 900); text("⏱", 910, 1738, 36, 900); text("▶", 1000, 1738, 36, 900, green, "center");
}
function waveform(x, y, w, h, p) {
  for (let i = 0; i < 24; i++) {
    const a = 12 + Math.abs(Math.sin(i * 0.7 + p * 12)) * h;
    line(x + i * w / 24, y + h / 2 - a / 2, x + i * w / 24, y + h / 2 + a / 2, green, 5);
  }
}
function voiceChat(t) {
  const p = seg(t, 18, 30);
  chatShell("Minji");
  bubble(90, 250, 656, 122, false, "오늘 저녁에 통화 가능해?", "12:24", true);
  bubble(300, 422, 680, 128, true, "네, 8 PM 가능합니다.", "12:25");
  if (p < 0.32) {
    composer(true); waveform(260, 1542, 620, 90, p); touch(t, 1000, 1760, 20.5, 21.2);
  } else if (p < 0.52) {
    composer(false); sttConfirm("음성 메시지 확인", "변환된 텍스트", "오늘 저녁 8시에 통화 가능합니다. 필요한 파일도 보내드리겠습니다.", "바로 전송");
  } else {
    bubble(260, 640, 720, 180, true, "오늘 저녁 8시에 통화 가능합니다. 필요한 파일도 보내드리겠습니다.", "12:31", true);
    bubble(90, 860, 680, 136, false, "좋습니다. 음성도 잘 재생됩니다.", "12:32", true);
    composer(false);
  }
}
function sttConfirm(title, label, body, button) {
  fillRound(0, 1090, W, 830, 54, "#fff"); fillRound(448, 1120, 184, 10, 5, "#DADDE3");
  text(title, 54, 1182, 42, 900); text(label, 54, 1286, 24, 850, muted);
  fillRound(54, 1330, 972, 210, 30, "#EFFAF4"); wrapText(body, 92, 1370, 880, 45, 34, 800);
  fillRound(54, 1588, 972, 86, 30, green); text("▶  " + button, 540, 1612, 32, 900, "#fff", "center");
}
function messageTools(t) {
  const p = seg(t, 30, 42);
  chatShell("Minji");
  bubble(260, 260, 720, 120, true, "오늘 저녁 8시에 통화 가능합니다.", "12:31", true);
  if (p < 0.28) {
    actionSheet("메시지 작업", ["답장", "반응 👍", "메시지 고정", "번역", "수정", "삭제"]);
  } else if (p < 0.48) {
    fillRound(38, 224, 1004, 120, 24, mint); strokeRound(38, 224, 1004, 120, 24, "#BFEEDB");
    circle(104, 284, 38, green); text("📌", 104, 262, 31, 900, "#fff", "center");
    text("고정된 메시지", 158, 256, 29, 900, green); text("오늘 저녁 8시에 통화 가능합니다.", 158, 298, 30, 900);
    text("•••", 964, 276, 34, 900, green, "center");
    actionSheet("고정된 메시지", ["고정 해제"]);
  } else if (p < 0.68) {
    fillRound(54, 612, 972, 260, 32, "#fff"); strokeRound(54, 612, 972, 260, 32, "#E4E7EC");
    text("번역", 92, 640, 34, 900); text("English", 92, 706, 24, 900, green);
    wrapText("I can talk at 8 PM tonight. I will send the required file too.", 92, 748, 860, 38, 29, 800);
  } else {
    fillRound(54, 612, 972, 350, 32, "#fff"); strokeRound(54, 612, 972, 350, 32, "#E4E7EC");
    text("첨부 / 예약 전송", 92, 642, 36, 900);
    featurePill(92, 714, "사진", "이미지 미리보기");
    featurePill(92, 796, "파일", "meeting.pdf");
    featurePill(92, 878, "위치", "서울 강남구");
    fillRound(540, 714, 398, 72, 24, "#F0F1F4"); text("내일 9:00 예약", 568, 733, 29, 900);
  }
  composer(false);
}
function actionSheet(title, items) {
  fillRound(0, 1050, W, 870, 54, "#fff"); fillRound(448, 1080, 184, 10, 5, "#DADDE3");
  text(title, 54, 1138, 42, 900);
  let y = 1234;
  for (const item of items) { text(item, 92, y, 34, 850); y += 86; }
}
function featurePill(x, y, a, b) {
  fillRound(x, y, 398, 64, 20, "#F0FDF6"); text(a, x + 24, y + 15, 27, 900, green); text(b, x + 128, y + 15, 27, 800, ink);
}
function calendarScreen(t) {
  const p = seg(t, 42, 56);
  topBar("일정", {back: true, plus: true, bg: "#DDFBEA"});
  fillRound(30, 210, 1020, 122, 26, "#fff");
  circle(96, 270, 42, "#20C785"); text("▣", 96, 248, 30, 900, "#fff", "center");
  text("다가오는 일정", 156, 238, 24, 900, green); text("Demo launch review", 156, 274, 31, 900); text("5/29 14:30", 902, 248, 24, 900, ink, "center");
  fillRound(30, 360, 1020, 940, 34, "#fff");
  text("6월", 86, 402, 43, 900); text("오늘", 430, 416, 27, 900, green); text("🔔", 584, 404, 36, 900); text("⌕", 722, 404, 42, 900);
  const days = ["월","화","수","목","금","토","일"]; for (let i = 0; i < 7; i++) text(days[i], 102 + i * 135, 492, 22, 900, i === 6 ? "#FF3040" : muted, "center");
  for (let r = 0; r < 6; r++) for (let c = 0; c < 7; c++) {
    const d = r * 7 + c - 1; const x = 54 + c * 138; const y = 536 + r * 116;
    fillRound(x, y, 116, 96, 16, d === 12 && p > 0.55 ? mint : "#fff"); strokeRound(x, y, 116, 96, 16, d === 12 ? green : "#E4E7EC");
    text(String(d <= 0 ? d + 31 : d), x + 20, y + 16, 21, 900, d <= 0 ? "#C9CDD4" : ink);
    if (d === 6) text("현충일", x + 58, y + 56, 18, 900, "#FF3040", "center");
    if (d === 12 && p > 0.55) { circle(x + 84, y + 26, 5, green); fillRound(x + 18, y + 58, 80, 24, 9, green); text("Demo", x + 58, y + 62, 14, 900, "#fff", "center"); }
  }
  fillRound(54, 1360, 972, 126, 24, "#F6F8F7"); text("6월 12일 금요일", 84, 1394, 29, 900); text(p > 0.55 ? "14:00  데모 리허설" : "대한민국 공휴일 표시 · 국가 선택: KR", 84, 1442, 24, 800, muted);
  fillRound(54, 1520, 720, 88, 30, green); text("🎙  음성으로 추가", 414, 1544, 32, 900, "#fff", "center");
  fillRound(814, 1520, 160, 88, 30, "#F0FDF6"); text("▣", 894, 1540, 36, 900, green, "center");
  if (p > 0.24 && p < 0.55) voiceCalendarSheet();
}
function voiceCalendarSheet() {
  fillRound(0, 1030, W, 890, 54, "#fff"); fillRound(448, 1060, 184, 10, 5, "#DADDE3");
  text("음성 일정 추가", 54, 1120, 42, 900);
  fillRound(54, 1210, 972, 100, 24, "#F6F8F7"); text("6월 12일 오후 2시에 데모 리허설 추가해줘", 90, 1238, 29, 800);
  fillRound(54, 1340, 460, 78, 20, "#EFFAF4"); text("제목  데모 리허설", 86, 1362, 27, 900);
  fillRound(546, 1340, 480, 78, 20, "#EFFAF4"); text("날짜  2026-06-12", 578, 1362, 27, 900);
  fillRound(54, 1446, 460, 78, 20, "#EFFAF4"); text("시간  14:00", 86, 1468, 27, 900);
  fillRound(546, 1446, 480, 78, 20, "#EFFAF4"); text("상세  리허설 메모", 578, 1468, 27, 900);
  fillRound(54, 1580, 972, 86, 30, green); text("자동 저장", 540, 1604, 31, 900, "#fff", "center");
  fillRound(54, 1700, 972, 64, 22, "#F0FDF6"); text("음성 안내: 6월 12일 데모 리허설 일정이 추가되었습니다.", 540, 1718, 23, 900, green, "center");
}
function reminderSync(t) {
  topBar("일정 설정", {back: true, bg: "#DDFBEA"});
  fillRound(38, 220, 1004, 132, 28, "#fff"); text("알림", 78, 250, 34, 900); text("기본 30분 전 미리 알림", 78, 300, 27, 800, muted); toggle(924, 270, true);
  fillRound(38, 380, 1004, 132, 28, "#fff"); text("아침 브리핑", 78, 410, 34, 900); text("오전 8:00 오늘 일정 음성 브리핑", 78, 460, 27, 800, muted); toggle(924, 430, true);
  fillRound(38, 540, 1004, 132, 28, "#fff"); text("Google Calendar 연동", 78, 570, 34, 900); text("앱 내부 일정과 동기화", 78, 620, 27, 800, muted); toggle(924, 590, true);
  fillRound(38, 700, 1004, 132, 28, "#fff"); text("Apple Calendar 연동", 78, 730, 34, 900); text("iOS 캘린더 공유 준비", 78, 780, 27, 800, muted); toggle(924, 750, true);
  fillRound(38, 880, 1004, 230, 28, "#fff"); text("이벤트 상세", 78, 910, 34, 900); text("제목 · 날짜 · 시간 · 상세 내용 수정", 78, 960, 27, 800, muted); wrapText("상세 내용: 장소, 준비물, 메모를 일정에 함께 저장합니다.", 78, 1010, 860, 36, 27, 800, ink);
  fillRound(38, 1150, 1004, 124, 28, "#F0FDF6"); text("오늘 브리핑", 78, 1182, 30, 900, green); text("오후 2시 데모 리허설, 오후 8시 통화", 78, 1226, 27, 900);
}
function toggle(x, y, on) { fillRound(x - 84, y - 28, 112, 56, 28, on ? green : "#D0D5DD"); circle(on ? x : x - 56, y, 23, "#fff"); }
function proposal(t) {
  const p = seg(t, 68, 88);
  chatShell("프로젝트 방");
  if (p < 0.28) {
    actionSheet("일정 제안 만들기", ["제목: 런칭 회의", "상세: 스토어 제출 전 점검", "후보 1  6/12 14:00", "후보 2  6/12 18:00", "후보 3  6/13 10:00", "카드로 전송"]);
  } else {
    fillRound(80, 290, 900, 560, 34, "#fff"); strokeRound(80, 290, 900, 560, 34, "#D0F5E3", 3);
    text("일정 제안", 124, 328, 26, 900, green); text("런칭 회의", 124, 372, 38, 900);
    text("스토어 제출 전 최종 점검", 124, 424, 26, 800, muted);
    proposalOption(124, 492, "6/12 금 14:00", p > 0.40, 3);
    proposalOption(124, 584, "6/12 금 18:00", p > 0.55, 2);
    proposalOption(124, 676, "6/13 토 10:00", false, 1);
    fillRound(124, 772, 380, 62, 22, p > 0.68 ? green : "#F0F1F4"); text(p > 0.68 ? "확정됨" : "투표하기", 314, 787, 27, 900, p > 0.68 ? "#fff" : ink, "center");
    if (p > 0.72) { fillRound(80, 910, 900, 90, 26, mint); text("선택한 참석자 캘린더에 자동 등록", 540, 936, 30, 900, green, "center"); }
  }
  composer(false);
}
function proposalOption(x, y, label, selected, count) {
  fillRound(x, y, 760, 70, 22, selected ? "#E6FFF4" : "#F5F6F8");
  text(selected ? "✓" : "○", x + 34, y + 17, 28, 900, selected ? green : muted, "center");
  text(label, x + 78, y + 18, 27, 900); text(count + "명", x + 690, y + 18, 27, 900, selected ? green : muted, "center");
}
function finalSummary(t) {
  clear("#DDFBEA"); status();
  text("Verbal", 54, 130, 58, 900); text("실사용자 데모 완료", 54, 204, 36, 900, green);
  const items = [
    "회원가입 · 프로필 · user ID",
    "DM/채널 · 요청 메시지 · 설정 메뉴",
    "음성 메시지 STT · 즉시 전송 · 재생",
    "수정 · 삭제 · 반응 · 검색 · 번역",
    "고정 배너 · 길게 눌러 고정 해제",
    "사진 · 파일 · 위치 · 예약 전송",
    "월간 캘린더 · 공휴일 · 음성 일정 추가",
    "알림 · 아침 브리핑 · Google/Apple 연동",
    "채팅방 일정 제안 · 투표 · 확정 등록"
  ];
  let y = 330;
  for (const item of items) { fillRound(54, y, 972, 76, 24, "#fff"); text("✓", 96, y + 17, 29, 900, green); text(item, 144, y + 18, 29, 900); y += 94; }
  fillRound(54, 1516, 972, 110, 32, green); text("2분 이하 풀 기능 데모", 540, 1548, 38, 900, "#fff", "center");
  navHome();
}
function drawFrameAt(t) {
  if (t < 8) phoneSignup(t);
  else if (t < 18) inboxAndMenu(t);
  else if (t < 30) voiceChat(t);
  else if (t < 42) messageTools(t);
  else if (t < 56) calendarScreen(t);
  else if (t < 68) reminderSync(t);
  else if (t < 88) proposal(t);
  else finalSummary(t);
  progress(t);
}
function progress(t) {
  fillRound(54, 1816, 972, 8, 4, "rgba(17,17,17,0.08)");
  fillRound(54, 1816, 972 * clamp(t / DURATION), 8, 4, green);
}
async function renderFullFeatureDemoVideo() {
  drawFrameAt(0);
  const stream = canvas.captureStream(FPS);
  const mimeTypes = ["video/webm;codecs=vp8", "video/webm;codecs=vp9", "video/webm"];
  const mimeType = mimeTypes.find((type) => MediaRecorder.isTypeSupported(type)) || "";
  const recorder = new MediaRecorder(stream, mimeType ? {mimeType, videoBitsPerSecond: 6_000_000} : {videoBitsPerSecond: 6_000_000});
  const chunks = [];
  recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
  const stopped = new Promise((resolve) => { recorder.onstop = resolve; });
  recorder.start(1000);
  const frameMs = 1000 / FPS;
  for (let frame = 0; frame <= DURATION * FPS; frame++) {
    drawFrameAt(frame / FPS);
    await new Promise((resolve) => setTimeout(resolve, frameMs));
  }
  recorder.stop();
  await stopped;
  stream.getTracks().forEach((track) => track.stop());
  const blob = new Blob(chunks, {type: "video/webm"});
  const buffer = await blob.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
  return btoa(binary);
}
window.drawFrameAt = drawFrameAt;
window.renderFullFeatureDemoVideo = renderFullFeatureDemoVideo;
drawFrameAt(0);
</script>
</body>
</html>`;
}
