const childProcess = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const {pathToFileURL} = require("node:url");

const repoRoot = path.resolve(__dirname, "..");
const outDir = path.join(repoRoot, "artifacts", "demo");
const htmlPath = path.join(outDir, "verbal_current_user_demo.html");
const rawWebmPath = path.join(outDir, "verbal_current_user_demo.raw.webm");
const webmPath = path.join(outDir, "verbal_current_user_demo.webm");
const mp4Path = path.join(outDir, "verbal_current_user_demo.mp4");
const previewPath = path.join(outDir, "verbal_current_user_demo_preview.png");
const storyboardPath = path.join(outDir, "verbal_current_user_demo_storyboard.md");

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
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "voice-current-demo-"));
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
      expression: "window.renderCurrentUserDemoVideo()",
      awaitPromise: true,
      returnByValue: true,
    });
    const videoBase64 = renderResult.result?.value;
    if (!videoBase64) {
      throw new Error(`Video rendering returned no data. ${JSON.stringify(renderResult)}`);
    }
    fs.writeFileSync(rawWebmPath, Buffer.from(videoBase64, "base64"));

    const previewResult = await cdp.send("Runtime.evaluate", {
      expression: "window.drawFrameAt(44.0); document.getElementById('stage').toDataURL('image/png').split(',')[1]",
      awaitPromise: true,
      returnByValue: true,
    });
    fs.writeFileSync(previewPath, Buffer.from(previewResult.result.value, "base64"));
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
  return `# Verbal Current User Demo

Maximum length: 49 seconds.

1. User starts from signup with phone verification.
2. User completes nickname and user ID profile setup.
3. User lands on the current green DM inbox with notes, messages/channels tabs, sponsored tile, and active rooms.
4. User opens Minji direct chat.
5. User records a voice message from the composer.
6. STT review sheet shows editable recognized text.
7. User sends the STT voice message and receives a transcript-based reply.
8. User opens Calendar from the home header.
9. User adds a calendar event by voice.
10. STT calendar confirmation sheet shows transcript, title, detail, date, and time before saving.
11. The monthly calendar updates with the new upcoming event card.
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
    "-t", "49.5",
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
  try {
    fs.rmSync(dir, {recursive: true, force: true});
  } catch (_) {}
}

class CdpClient {
  constructor(socket) {
    this.socket = socket;
    this.id = 0;
    this.pending = new Map();
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (!message.id) {
        return;
      }
      const callbacks = this.pending.get(message.id);
      if (!callbacks) {
        return;
      }
      this.pending.delete(message.id);
      if (message.error) {
        callbacks.reject(new Error(JSON.stringify(message.error)));
      } else {
        callbacks.resolve(message.result);
      }
    });
  }

  static connect(url) {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.addEventListener("open", () => resolve(new CdpClient(socket)));
      socket.addEventListener("error", reject);
    });
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
  <title>Verbal Current User Demo</title>
  <style>
    html, body { margin: 0; width: 100%; height: 100%; background: #E8FFF2; overflow: hidden; }
    body { display: grid; place-items: center; }
    canvas { display: block; width: min(100vw, 56.25vh); height: min(177.7778vw, 100vh); background: #fff; }
  </style>
</head>
<body>
<canvas id="stage" width="1080" height="1920"></canvas>
<script>
const canvas = document.getElementById("stage");
const ctx = canvas.getContext("2d");
const W = canvas.width;
const H = canvas.height;
const DURATION = 49;
const FPS = 24;

const green = "#00A86B";
const greenDark = "#006B4A";
const greenDeep = "#005A42";
const mint = "#E2FAEE";
const soft = "#F2F3F5";
const ink = "#101114";
const muted = "#70727A";
const border = "#E7E8EC";
const users = [
  {name:"민지", note:"오늘 저녁 통화 가능해?", initial:"M"},
  {name:"지훈", note:"회의 링크 보냈어", initial:"J"},
  {name:"서연", note:"자료 확인 중", initial:"S"},
  {name:"현우", note:"위치 공유했어", initial:"H"},
  {name:"유나", note:"사진 보냈어", initial:"Y"},
  {name:"태오", note:"운동 끝", initial:"T"},
  {name:"다은", note:"예약 확인", initial:"D"},
  {name:"준호", note:"공항 도착", initial:"J"},
  {name:"하린", note:"쿠폰 공유", initial:"H"},
  {name:"소라", note:"카페 자리 있어", initial:"S"}
];

function ease(x) { return x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x); }
function seg(t, a, b) { return ease((t - a) / (b - a)); }
function rr(x, y, w, h, r) {
  const q = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + q, y);
  ctx.arcTo(x + w, y, x + w, y + h, q);
  ctx.arcTo(x + w, y + h, x, y + h, q);
  ctx.arcTo(x, y + h, x, y, q);
  ctx.arcTo(x, y, x + w, y, q);
  ctx.closePath();
}
function fillRound(x, y, w, h, r, color) { ctx.fillStyle = color; rr(x, y, w, h, r); ctx.fill(); }
function strokeRound(x, y, w, h, r, color, line = 2) { ctx.strokeStyle = color; ctx.lineWidth = line; rr(x, y, w, h, r); ctx.stroke(); }
function circle(x, y, r, color) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); }
function gradientCircle(x, y, r, a = "#35C987", b = green) {
  const g = ctx.createLinearGradient(x - r, y - r, x + r, y + r);
  g.addColorStop(0, a); g.addColorStop(1, b);
  circle(x, y, r, g);
}
function text(s, x, y, size = 34, weight = 700, color = ink, align = "left") {
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = "top";
  ctx.font = weight + " " + size + "px Malgun Gothic, Apple SD Gothic Neo, Noto Sans KR, Segoe UI, sans-serif";
  ctx.fillText(s, x, y);
}
function wrapText(s, x, y, maxWidth, lineHeight, size = 32, weight = 700, color = ink) {
  ctx.font = weight + " " + size + "px Malgun Gothic, Apple SD Gothic Neo, Noto Sans KR, Segoe UI, sans-serif";
  ctx.fillStyle = color;
  ctx.textAlign = "left";
  ctx.textBaseline = "top";
  let line = "";
  let yy = y;
  for (const ch of [...s]) {
    const next = line + ch;
    if (ctx.measureText(next).width > maxWidth && line) {
      ctx.fillText(line, x, yy);
      line = ch;
      yy += lineHeight;
    } else {
      line = next;
    }
  }
  if (line) ctx.fillText(line, x, yy);
}
function clear() {
  const bg = ctx.createLinearGradient(0, 0, 0, H);
  bg.addColorStop(0, "#E8FFF2");
  bg.addColorStop(0.55, "#B2F1D0");
  bg.addColorStop(1, "#35C987");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);
  fillRound(22, 16, W - 44, H - 32, 76, "#fff");
  ctx.save();
  rr(22, 16, W - 44, H - 32, 76);
  ctx.clip();
}
function finish() {
  ctx.restore();
}
function status() {
  text("9:41", 78, 48, 28, 800, ink);
  text("◢  Wi-Fi  ▮", 830, 48, 23, 900, ink);
}
function nav(title, subtitle = "", back = true) {
  status();
  if (back) text("‹", 56, 110, 58, 500, ink);
  text(title, back ? 122 : 58, 124, 42, 900, ink);
  if (subtitle) text(subtitle, back ? 124 : 60, 170, 24, 700, muted);
}
function homeIndicator() { fillRound(408, 1870, 264, 10, 5, "#111"); }
function avatar(x, y, label, r = 46) {
  gradientCircle(x, y, r + 7);
  circle(x, y, r + 1, "#fff");
  gradientCircle(x, y, r - 4);
  text(label, x, y - r * 0.47, r * 0.82, 900, "#fff", "center");
}
function noteBubble(x, y, s) {
  fillRound(x - 80, y - 68, 160, 50, 22, "#fff");
  ctx.shadowColor = "rgba(0,0,0,0.13)";
  ctx.shadowBlur = 16;
  ctx.shadowOffsetY = 5;
  fillRound(x - 80, y - 68, 160, 50, 22, "#fff");
  ctx.shadowColor = "transparent";
  text(s, x, y - 58, 19, 800, ink, "center");
}
function tap(t, x, y, a, b) {
  const p = seg(t, a, b);
  if (p <= 0 || p >= 1) return;
  circle(x, y, 18 + p * 42, "rgba(0,168,107," + (0.26 * (1 - p)) + ")");
  circle(x, y, 16, "rgba(0,168,107,0.78)");
}
function auth(t) {
  clear();
  status();
  gradientCircle(540, 230, 82);
  text("V", 540, 184, 78, 900, "#fff", "center");
  text("Verbal", 540, 350, 54, 900, ink, "center");
  text("전화번호로 시작", 540, 422, 32, 700, muted, "center");
  fillRound(92, 548, 896, 88, 26, soft);
  text("+82 10 4821 0927", 132, 570, 36, 900, ink);
  fillRound(92, 680, 896, 88, 30, green);
  text("인증번호 받기", 540, 702, 34, 900, "#fff", "center");
  if (t > 1.1) {
    fillRound(92, 824, 896, 88, 26, soft);
    text("428913", 132, 846, 36, 900, ink);
    text("SMS 인증 완료", 92, 948, 32, 900, green);
  }
  if (t > 2.1) {
    fillRound(92, 1032, 896, 88, 26, soft);
    text("민지", 132, 1054, 36, 900, ink);
    fillRound(92, 1164, 896, 88, 30, greenDeep);
    text("프로필 만들기", 540, 1186, 34, 900, "#fff", "center");
  }
  tap(t, 540, 724, 0.5, 1.0);
  tap(t, 540, 1208, 3.0, 3.5);
  homeIndicator();
  finish();
}
function inbox(t) {
  clear();
  status();
  text("☰", 64, 124, 34, 900, ink, "center");
  text("demo", 126, 124, 42, 900, ink);
  text("▣", 842, 126, 32, 900, ink, "center");
  text("✎", 972, 120, 40, 900, ink, "center");
  for (let i = 0; i < 4; i++) {
    const x = 116 + i * 210;
    noteBubble(x, 268, i === 0 ? "메모 남기기" : users[i].note);
    avatar(x, 320, users[i].initial, 52);
    if (i === 0 || i === 3) circle(x + 46, 366, 11, green);
    text(i === 0 ? "내 노트" : users[i].name, x, 390, 21, 800, muted, "center");
  }
  fillRound(8, 460, 512, 64, 18, mint);
  text("• 메시지", 264, 477, 26, 900, green, "center");
  fillRound(548, 460, 512, 64, 18, soft);
  text("채널", 804, 477, 26, 900, ink, "center");
  const rows = users.slice(0, 7);
  for (let i = 0; i < rows.length; i++) {
    const y = 570 + i * 118;
    avatar(108, y + 45, rows[i].initial, 42);
    text(rows[i].name, 178, y + 10, 31, 900, ink);
    text(rows[i].note + " · " + (i + 2) + "분", 178, y + 51, 25, 700, muted);
    if (i === 1) {
      fillRound(58, y + 102, 964, 110, 16, "#F7F8FA");
      strokeRound(58, y + 102, 964, 110, 16, border, 2);
      text("Sponsored", 176, y + 124, 28, 900, ink);
      text("대화방 밖에서만 노출되는 네이티브 광고", 176, y + 164, 24, 700, muted);
      text("Ad", 962, y + 146, 23, 700, muted, "right");
      i += 1;
    }
  }
  tap(t, 178, 625, 7.1, 7.7);
  homeIndicator();
  finish();
}
function waveform(x, y, w, h, p, color = green) {
  ctx.strokeStyle = color;
  ctx.lineWidth = 6;
  ctx.lineCap = "round";
  for (let i = 0; i < 28; i++) {
    const px = x + i * (w / 28);
    const amp = 14 + Math.abs(Math.sin(i * 0.9 + p * 20)) * h;
    ctx.beginPath();
    ctx.moveTo(px, y + h / 2 - amp / 2);
    ctx.lineTo(px, y + h / 2 + amp / 2);
    ctx.stroke();
  }
}
function bubble(x, y, w, h, mine, msg, meta, voice = false) {
  fillRound(x, y, w, h, 34, mine ? greenDeep : "#F0F0F0");
  const fg = mine ? "#fff" : ink;
  if (voice) {
    text("▶", x + 34, y + 24, 30, 900, mine ? "#DDFCEE" : "#6B6E76");
    waveform(x + 100, y + 31, 190, 28, 0.6, mine ? "#DDFCEE" : green);
    text(meta.split(" · ")[0], x + 315, y + 21, 24, 800, mine ? "#DDFCEE" : muted);
    wrapText(msg, x + 34, y + 82, w - 68, 40, 31, 800, fg);
    text(meta.split(" · ").slice(1).join(" · "), x + w - 34, y + h - 34, 21, 700, mine ? "#B8EFD6" : muted, "right");
    return;
  }
  wrapText(msg, x + 34, y + 26, w - 68, 40, 31, 800, fg);
  text(meta, x + w - 34, y + h - 34, 21, 700, mine ? "#B8EFD6" : muted, "right");
}
function composer(recording, label = "Message...") {
  fillRound(0, 1680, W, 240, 0, "#fff");
  fillRound(52, 1724, 68, 68, 34, green);
  text("●", 86, 1738, 34, 900, "#fff", "center");
  fillRound(140, 1724, 720, 68, 34, soft);
  text(label, 176, 1744, 27, 700, recording ? "#D92D20" : muted);
  text(recording ? "■" : "🎙", 918, 1737, 32, 900, ink, "center");
  text("➤", 990, 1737, 36, 900, green, "center");
  homeIndicator();
}
function chat(t) {
  clear();
  nav("Minji", "Direct chat", true);
  text("☎", 840, 124, 34, 900, ink, "center");
  text("▣", 932, 124, 34, 900, ink, "center");
  text("⋯", 1002, 122, 40, 900, ink, "center");
  avatar(104, 326, "M", 34);
  bubble(156, 280, 830, 218, false, "오늘 저녁에 통화 가능해?", "00:03 · 12:35", true);
  bubble(48, 532, 920, 126, true, "Yes, 8 PM works for me.", "12:36");
  if (t < 13.6) {
    composer(false);
    tap(t, 918, 1760, 10.5, 11.1);
  } else if (t < 16.2) {
    composer(true, "녹음 중 00:" + String(Math.floor(4 + (t - 13.6) * 7)).padStart(2, "0"));
    waveform(220, 1590, 630, 58, t, green);
    tap(t, 918, 1760, 15.5, 16.1);
  } else if (t < 20.1) {
    composer(false);
    sttSheet(t);
  } else {
    bubble(92, 700, 870, 230, true, "오늘 저녁 8시에 보이스톡 가능해? 회의 자료도 보내줄게.", "00:28 · 방금", true);
    if (t > 23.2) {
      avatar(104, 1010, "M", 34);
      bubble(156, 966, 810, 205, false, "응 가능해. 회의 링크도 음성으로 보내줘.", "00:14 · 방금", true);
    }
    composer(false);
  }
  finish();
}
function sttSheet(t) {
  const p = seg(t, 16.2, 20.1);
  fillRound(0, 1124, W, 796, 62, "#fff");
  text("음성 메시지 확인", 58, 1190, 43, 900, ink);
  if (p < 0.45) {
    text("변환된 텍스트", 90, 1280, 22, 700, muted);
    fillRound(58, 1320, 964, 200, 34, "#EFFAF4");
    text("음성을 텍스트로 변환 중입니다.", 104, 1372, 33, 800, ink);
    waveform(118, 1480, 800, 58, t, green);
  } else {
    text("변환된 텍스트", 90, 1280, 22, 700, muted);
    fillRound(58, 1320, 964, 234, 34, "#EFFAF4");
    wrapText("오늘 저녁 8시에 보이스톡 가능해? 회의 자료도 보내줄게.", 104, 1364, 872, 46, 34, 800, ink);
    fillRound(58, 1648, 964, 82, 32, green);
    text("➤  전송", 540, 1670, 34, 900, "#fff", "center");
    tap(t, 540, 1690, 19.2, 19.8);
  }
}

function calendarEntry(t) {
  inbox(t);
  tap(t, 842, 142, 27.4, 28.2);
}

function calendarHeader() {
  status();
  text("‹", 56, 110, 58, 500, ink);
  text("일정", 124, 124, 42, 900, ink);
  text("🔔", 990, 116, 32, 900, ink, "center");
}

function calendarCell(x, y, day, mutedDay = false, selected = false) {
  fillRound(x, y, 118, 124, 26, selected ? "#DFF9EC" : "#fff");
  strokeRound(x, y, 118, 124, 26, selected ? green : border, selected ? 3 : 1.5);
  text(String(day), x + 22, y + 18, 21, 900, mutedDay ? "#CBD0D6" : ink);
}

function calendarMonth(eventSaved) {
  fillRound(46, 320, 988, 1110, 38, "#fff");
  text("‹", 88, 364, 44, 600, ink);
  text("5월", 150, 370, 46, 900, ink);
  text("2026 · " + (eventSaved ? "1개 일정" : "일정 없음"), 150, 430, 25, 700, muted);
  text("오늘", 584, 374, 25, 900, greenDeep, "center");
  text("⌕", 710, 365, 42, 900, ink, "center");
  text("›", 970, 366, 44, 600, ink, "center");
  const week = ["월", "화", "수", "목", "금", "토", "일"];
  for (let i = 0; i < week.length; i++) {
    text(week[i], 112 + i * 135, 500, 21, 900, i === 6 ? "#F04438" : muted, "center");
  }
  const days = [27,28,29,30,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,1,2,3,4,5,6,7];
  for (let i = 0; i < 42; i++) {
    const col = i % 7;
    const row = Math.floor(i / 7);
    const x = 52 + col * 135;
    const y = 542 + row * 148;
    const current = i >= 4 && i <= 34;
    const selected = current && days[i] === 29;
    calendarCell(x, y, days[i], !current, selected && eventSaved);
    if (eventSaved && selected) {
      circle(x + 58, y + 44, 22, green);
      text("29", x + 58, y + 31, 20, 900, "#fff", "center");
      fillRound(x + 18, y + 78, 82, 28, 10, green);
      text("Demo…", x + 59, y + 83, 14, 900, "#fff", "center");
    }
  }
}

function upcomingCard(eventSaved) {
  if (eventSaved) {
    fillRound(48, 222, 984, 126, 24, "#F1F3F2");
    avatar(116, 285, "✓", 34);
    text("다가오는 일정", 186, 246, 24, 900, greenDeep);
    text("Demo launch review", 186, 282, 29, 900, ink);
    text("5/29", 884, 246, 25, 900, ink, "right");
    text("14:30", 884, 286, 25, 700, muted, "right");
    text("›", 952, 266, 44, 600, muted, "center");
  } else {
    fillRound(48, 222, 984, 104, 24, "#F1F3F2");
    text("다가오는 일정", 86, 246, 25, 900, greenDeep);
    text("아직 등록된 일정이 없습니다", 86, 284, 25, 700, muted);
  }
}

function calendarBottom(eventSaved) {
  fillRound(52, 1454, 824, 130, 30, "#F1F3F2");
  text("5월 29일 금요일", 88, 1486, 30, 900, ink);
  text(eventSaved ? "14:30  Demo launch review" : "선택한 날짜에 일정을 추가할 수 있습니다", 88, 1532, 25, 700, eventSaved ? greenDeep : muted);
  fillRound(52, 1628, 786, 92, 32, green);
  text("🎙  음성으로 추가", 445, 1654, 31, 900, "#fff", "center");
  fillRound(862, 1628, 166, 92, 32, mint);
  text("✎", 945, 1650, 36, 900, greenDeep, "center");
  homeIndicator();
}

function calendarScene(t) {
  const eventSaved = t > 43.2;
  clear();
  calendarHeader();
  upcomingCard(eventSaved);
  calendarMonth(eventSaved);
  calendarBottom(eventSaved);
  if (t < 32.2) {
    tap(t, 445, 1674, 30.2, 31.0);
  } else if (t < 35.2) {
    fillRound(52, 1628, 786, 92, 32, greenDeep);
    text("■  저장할 음성 확인 0:" + String(Math.floor(4 + (t - 32.2) * 5)).padStart(2, "0"), 445, 1654, 29, 900, "#fff", "center");
    waveform(150, 1532, 780, 56, t, green);
    tap(t, 445, 1674, 34.4, 35.1);
  } else if (t < 43.2) {
    calendarVoiceSheet(t);
  }
  finish();
}

function calendarVoiceSheet(t) {
  const p = seg(t, 35.2, 43.2);
  fillRound(0, 1058, W, 862, 64, "#fff");
  fillRound(470, 1090, 140, 10, 5, border);
  text("음성 일정 확인", 58, 1140, 42, 900, ink);
  text("변환된 음성 명령", 58, 1228, 23, 700, muted);
  fillRound(58, 1266, 964, 116, 28, "#EFFAF4");
  wrapText("올해 5월 29일 오후 2시 반에 Demo launch review 일정 추가해줘", 94, 1294, 890, 36, 27, 800, ink);
  fillRound(58, 1416, 964, 82, 24, soft);
  text(p < 0.35 ? "제목 분석 중..." : "Demo launch review", 92, 1438, 30, 900, p < 0.35 ? muted : ink);
  fillRound(58, 1520, 964, 82, 24, soft);
  text(p < 0.55 ? "상세 내용 분석 중..." : "런칭 전 최종 UX 점검", 92, 1542, 30, 800, p < 0.55 ? muted : ink);
  fillRound(58, 1624, 450, 82, 24, soft);
  fillRound(532, 1624, 490, 82, 24, soft);
  text(p < 0.75 ? "날짜" : "2026-05-29", 92, 1646, 29, 900, p < 0.75 ? muted : ink);
  text(p < 0.75 ? "시간" : "14:30", 566, 1646, 29, 900, p < 0.75 ? muted : ink);
  fillRound(58, 1742, 964, 82, 30, p > 0.78 ? green : "#D7D7D7");
  text("저장", 540, 1764, 32, 900, "#fff", "center");
  if (p > 0.78) tap(t, 540, 1784, 41.5, 42.4);
}

function finalFrame(t) {
  calendarScene(47.0);
  const p = seg(t, 47.5, 49.0);
  fillRound(86, 1228, 908, 106, 32, "rgba(0,90,66," + (0.92 * p) + ")");
  text("가입 → 음성 메시지/STT → 음성 캘린더 일정 추가", 540, 1258, 29, 900, "rgba(255,255,255," + p + ")", "center");
}
function drawFrameAt(t) {
  if (t < 4.3) auth(t);
  else if (t < 8.4) inbox(t);
  else if (t < 26.4) chat(t);
  else if (t < 29.0) calendarEntry(t);
  else if (t < 47.5) calendarScene(t);
  else finalFrame(t);
}
async function renderCurrentUserDemoVideo() {
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
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
window.drawFrameAt = drawFrameAt;
window.renderCurrentUserDemoVideo = renderCurrentUserDemoVideo;
drawFrameAt(0);
</script>
</body>
</html>`;
}
