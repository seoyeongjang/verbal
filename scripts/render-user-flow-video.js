const childProcess = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const {pathToFileURL} = require("node:url");

const repoRoot = path.resolve(__dirname, "..");
const outDir = path.join(repoRoot, "artifacts", "demo");
const htmlPath = path.join(outDir, "voice_messenger_user_flow_demo.html");
const rawWebmPath = path.join(outDir, "voice_messenger_user_flow_demo.raw.webm");
const webmPath = path.join(outDir, "voice_messenger_user_flow_demo.webm");
const previewPath = path.join(outDir, "voice_messenger_user_flow_demo_preview.png");
const storyboardPath = path.join(outDir, "voice_messenger_user_flow_storyboard.md");

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
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "voice-user-flow-chrome-"));
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
      expression: "window.renderUserFlowVideo()",
      awaitPromise: true,
      returnByValue: true,
    });
    const videoBase64 = renderResult.result?.value;
    if (!videoBase64) {
      throw new Error(`Video rendering returned no data. ${JSON.stringify(renderResult)}`);
    }
    fs.writeFileSync(rawWebmPath, Buffer.from(videoBase64, "base64"));

    const previewResult = await cdp.send("Runtime.evaluate", {
      expression: "window.drawFrameAt(37.5); document.getElementById('stage').toDataURL('image/png').split(',')[1]",
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
  if (!(ffmpegPath && normalizeWebmDuration(ffmpegPath, rawWebmPath, webmPath))) {
    fs.copyFileSync(rawWebmPath, webmPath);
  }

  console.log(JSON.stringify({
    htmlPath,
    webmPath,
    previewPath,
    storyboardPath,
  }, null, 2));
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
    "-i",
    inputPath,
    "-c:v",
    "libvpx",
    "-auto-alt-ref",
    "0",
    "-b:v",
    "3200k",
    outputPath,
  ], {encoding: "utf8"});
  if (result.status !== 0 || !fs.existsSync(outputPath)) {
    console.warn("WebM duration normalization skipped.");
    return false;
  }
  return true;
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
    } catch (error) {
      if (attempt === 2) {
        console.warn(`Could not remove temporary Chrome profile: ${dir}`);
      }
    }
  }
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

function storyboardMarkdown() {
  return `# Voice Messenger Real-User Demo Storyboard

This demo is a screen-only mobile flow, not an IR/pitch video.

1. First launch and phone signup.
2. SMS verification and profile creation.
3. DM inbox with notes, tabs, and 10 active contacts.
4. New group selection with 10 users.
5. Group chat opens with realistic messages.
6. Sender records an unlimited-length voice message.
7. STT bottom sheet shows conversion and editable transcript.
8. Sender sends transcript plus playable voice.
9. Recipient receives the incoming STT voice message.
10. Recipient sends an STT voice reply and the sender receives it.
`;
}

function demoHtml() {
  return String.raw`<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Voice Messenger User Flow Demo</title>
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
const DURATION = 56;
const FPS = 24;

const users = [
  {name:"민지", handle:"minji.voice", color:"#0095F6", note:"저녁 8시 가능?"},
  {name:"지훈", handle:"jihoon.song", color:"#16C784", note:"회의 링크 보내줘"},
  {name:"서연", handle:"seoyeon.k", color:"#FFB020", note:"자료 확인 중"},
  {name:"현우", handle:"hyunwoo.dev", color:"#8A5CFF", note:"이동 중"},
  {name:"유나", handle:"yuna.pic", color:"#FF4D67", note:"사진 공유 완료"},
  {name:"태오", handle:"taeo.run", color:"#00B8A9", note:"운동 끝"},
  {name:"다은", handle:"daeun.note", color:"#F97316", note:"예약 확인"},
  {name:"준호", handle:"junho.travel", color:"#2F80ED", note:"공항 도착"},
  {name:"하린", handle:"harin.shop", color:"#E84393", note:"쿠폰 확인"},
  {name:"소라", handle:"sora.cafe", color:"#64748B", note:"카페 자리 있어"}
];

function ease(x) {
  return x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x);
}
function seg(t, a, b) {
  return ease((t - a) / (b - a));
}
function lerp(a, b, p) {
  return a + (b - a) * p;
}
function clear(bg = "#fff") {
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);
}
function rr(x, y, w, h, r) {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}
function fillRound(x, y, w, h, r, color) {
  ctx.fillStyle = color;
  rr(x, y, w, h, r);
  ctx.fill();
}
function strokeRound(x, y, w, h, r, color, line = 2) {
  ctx.strokeStyle = color;
  ctx.lineWidth = line;
  rr(x, y, w, h, r);
  ctx.stroke();
}
function circle(x, y, r, color) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}
function text(s, x, y, size = 38, weight = 600, color = "#111", align = "left") {
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = "top";
  ctx.font = weight + " " + size + "px \"Malgun Gothic\", \"Apple SD Gothic Neo\", \"Noto Sans KR\", \"Segoe UI\", sans-serif";
  ctx.fillText(s, x, y);
}
function wrapText(s, x, y, maxWidth, lineHeight, size = 34, weight = 600, color = "#111", align = "left") {
  ctx.font = weight + " " + size + "px \"Malgun Gothic\", \"Apple SD Gothic Neo\", \"Noto Sans KR\", \"Segoe UI\", sans-serif";
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = "top";
  const words = [...s];
  let line = "";
  let yy = y;
  for (const ch of words) {
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
  return yy + lineHeight;
}
function statusBar(title = "", dark = false) {
  const color = dark ? "#fff" : "#111";
  text("9:41", 54, 34, 32, 800, color);
  text("● ● ▰", 878, 34, 24, 800, color);
  if (title) text(title, 92, 116, 44, 900, color);
}
function bottomHome() {
  fillRound(414, 1870, 252, 10, 5, "#111");
}
function appScaffold(title, opts = {}) {
  clear(opts.bg || "#fff");
  statusBar("", opts.dark);
  if (opts.back) text("‹", 42, 105, 76, 600, "#111");
  text(title, opts.back ? 118 : 48, 124, 46, 900, "#111");
  bottomHome();
}
function avatar(x, y, user, r = 44, ring = false) {
  if (ring) {
    const g = ctx.createLinearGradient(x - r, y - r, x + r, y + r);
    g.addColorStop(0, "#FF0080");
    g.addColorStop(0.5, "#FF7A00");
    g.addColorStop(1, "#0095F6");
    circle(x, y, r + 8, g);
    circle(x, y, r + 3, "#fff");
  }
  circle(x, y, r, user.color);
  text(user.name.slice(0, 1), x, y - r * 0.58, r * 0.92, 900, "#fff", "center");
}
function note(x, y, content) {
  fillRound(x - 82, y - 74, 164, 52, 22, "#fff");
  strokeRound(x - 82, y - 74, 164, 52, 22, "#E4E7EC", 2);
  text(content, x, y - 62, 21, 800, "#111", "center");
}
function tab(x, y, label, active) {
  fillRound(x, y, 308, 62, 18, active ? "#E3F2FF" : "#F0F1F4");
  text(label, x + 154, y + 16, 26, 900, active ? "#0095F6" : "#111", "center");
}
function touch(t, x, y, start, end) {
  const p = seg(t, start, end);
  if (p <= 0 || p >= 1) return;
  circle(x, y, 28 + p * 34, "rgba(0,149,246," + (0.22 * (1 - p)) + ")");
  circle(x, y, 18, "rgba(0,149,246,0.78)");
}
function keyboard(y) {
  fillRound(0, y, W, H - y, 0, "#E9ECF1");
  const rows = ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"];
  for (let r = 0; r < rows.length; r++) {
    const chars = [...rows[r]];
    const startX = 32 + r * 34;
    for (let i = 0; i < chars.length; i++) {
      fillRound(startX + i * 96, y + 36 + r * 92, 76, 70, 14, "#fff");
      text(chars[i], startX + i * 96 + 38, y + 50 + r * 92, 31, 700, "#111", "center");
    }
  }
  fillRound(254, y + 318, 572, 72, 18, "#fff");
}
function signup(t) {
  const p = seg(t, 0, 8);
  clear("#fff");
  statusBar();
  text("Voice Messenger", 54, 132, 54, 900, "#111");
  text("전화번호로 빠르게 시작하세요", 54, 206, 36, 700, "#667085");
  fillRound(54, 316, 972, 98, 24, "#F5F6F8");
  text("+82 10 4821 0927", 92, 343, 42, 900, "#111");
  fillRound(54, 454, 972, 88, 28, "#0095F6");
  text("인증번호 받기", 540, 476, 34, 900, "#fff", "center");
  if (p > 0.25) {
    fillRound(54, 598, 972, 98, 24, "#F5F6F8");
    text("428913", 92, 625, 42, 900, "#111");
    text("SMS 인증 완료", 54, 724, 34, 900, "#12B76A");
  }
  if (p > 0.52) {
    fillRound(54, 792, 972, 98, 24, "#F5F6F8");
    text("민지", 92, 819, 42, 900, "#111");
    fillRound(54, 926, 972, 98, 24, "#F5F6F8");
    text("@minji.voice", 92, 953, 42, 900, "#111");
    fillRound(54, 1078, 972, 88, 28, "#111");
    text("프로필 만들기", 540, 1100, 34, 900, "#fff", "center");
  }
  if (p > 0.78) {
    fillRound(54, 1238, 972, 112, 28, "#FFF8D6");
    text("연락처 10명 동기화 완료", 100, 1268, 36, 900, "#111");
  }
  touch(t, 540, 498, 1.0, 1.6);
  touch(t, 540, 1122, 6.2, 6.9);
  bottomHome();
}
function inbox(t) {
  const p = seg(t, 8, 16);
  appScaffold("minji_voice");
  text("✎", 960, 120, 40, 900, "#111", "center");
  for (let i = 0; i < 5; i++) {
    const x = 116 + i * 210;
    note(x, 270, i === 0 ? "메모 남기기" : users[i].note);
    avatar(x, 314, users[i], 56, true);
    text(i === 0 ? "내 노트" : users[i].name, x, 386, 22, 800, "#667085", "center");
  }
  tab(38, 456, "메시지", true);
  tab(386, 456, "채널", false);
  tab(734, 456, "요청", false);
  const rows = users.map((u, i) => ({
    user: u,
    last: [
      "오늘 저녁 8시 괜찮아?",
      "음성으로 답장할게",
      "자료 확인했어",
      "회의 링크 보내줘",
      "사진 올렸어",
      "운동 끝나고 봐",
      "예약 확인 완료",
      "공항 도착했어",
      "쿠폰 보냈어",
      "자리 맡아둘게"
    ][i],
  }));
  for (let i = 0; i < 10; i++) {
    const y = 568 + i * 114 - Math.max(0, p - 0.5) * 80;
    if (y < 520 || y > 1680) continue;
    avatar(92, y + 44, rows[i].user, 45, i < 3);
    text(rows[i].user.name, 164, y + 11, 32, 900, "#111");
    text(rows[i].last + " · " + (i + 1) + "분", 164, y + 54, 26, 700, "#667085");
    if (i < 4) circle(930, y + 44, 8, "#0095F6");
    text("▢", 984, y + 24, 38, 700, "#8A94A6", "center");
  }
  touch(t, 960, 140, 12.6, 13.2);
  bottomHome();
}
function groupSelect(t) {
  const p = seg(t, 16, 23);
  appScaffold("새 그룹", {back: true});
  fillRound(48, 214, 984, 70, 22, "#F5F6F8");
  text("이름 또는 핸들 검색", 86, 232, 30, 700, "#98A2B3");
  text("10명 선택됨", 54, 324, 34, 900, "#111");
  for (let i = 0; i < users.length; i++) {
    const y = 396 + i * 118;
    avatar(94, y + 48, users[i], 44, false);
    text(users[i].name, 164, y + 12, 32, 900, "#111");
    text(users[i].handle, 164, y + 54, 26, 700, "#667085");
    const selected = p > i / 12;
    circle(972, y + 48, 28, selected ? "#0095F6" : "#EEF2F6");
    if (selected) text("✓", 972, y + 30, 30, 900, "#fff", "center");
  }
  fillRound(54, 1758, 972, 92, 30, "#0095F6");
  text("그룹 대화 시작", 540, 1782, 36, 900, "#fff", "center");
  touch(t, 540, 1802, 21.6, 22.4);
}
function bubble(x, y, w, h, mine, body, meta) {
  fillRound(x, y, w, h, 34, mine ? "#0095F6" : "#F2F4F7");
  wrapText(body, x + 32, y + 24, w - 64, 40, 30, 800, mine ? "#fff" : "#111");
  if (meta) text(meta, x + 32, y + h - 38, 22, 700, mine ? "#D7EEFF" : "#667085");
}
function composer(recording, elapsed) {
  fillRound(0, 1658, W, 262, 0, "#fff");
  strokeRound(0, 1658, W, 1, 0, "#E4E7EC", 1);
  fillRound(48, 1716, 110, 86, 30, recording ? "#FF3B4E" : "#F0F2F5");
  text(recording ? "■" : "+", 103, 1735, 36, 900, recording ? "#fff" : "#111", "center");
  fillRound(184, 1716, 682, 86, 30, "#F5F6F8");
  text(recording ? "녹음 중 " + elapsed : "메시지 입력", 226, 1740, 31, 800, recording ? "#D92D20" : "#98A2B3");
  fillRound(902, 1716, 130, 86, 30, recording ? "#111" : "#0095F6");
  text(recording ? "완료" : "마이크", 967, 1740, 29, 900, "#fff", "center");
  bottomHome();
}
function chatBase(title) {
  appScaffold(title, {back: true, bg: "#F7F8FA"});
  text("통화", 842, 128, 30, 900, "#111");
  text("정보", 950, 128, 30, 900, "#111");
  fillRound(48, 210, 984, 60, 24, "#fff");
  text("음성은 원본과 STT 텍스트를 함께 보냅니다.", 88, 226, 27, 800, "#667085");
}
function senderChat(t) {
  const p = seg(t, 23, 36);
  chatBase("보이스 그룹");
  avatar(86, 338, users[1], 38);
  bubble(142, 300, 590, 112, false, "오늘 8시 회의 괜찮아?", "지훈 · 3분 전");
  avatar(86, 486, users[2], 38);
  bubble(142, 448, 704, 112, false, "좋아요. 민지도 음성으로 답장해줘.", "서연 · 2분 전");
  if (p > 0.42) {
    bubble(302, 620, 680, 182, true, "오늘 저녁 8시에 보이스톡 가능해? 회의 자료도 보내줄게.", "원본 음성 00:36");
    fillRound(350, 735, 218, 42, 21, "#E3F2FF");
    text("▶ 음성 재생", 459, 743, 23, 900, "#0077CC", "center");
  }
  if (p > 0.72) {
    avatar(86, 870, users[1], 38);
    bubble(142, 832, 684, 136, false, "응, 나는 가능해. 회의 링크도 보내줘.", "STT 답장 · 방금");
    fillRound(190, 918, 200, 42, 21, "#fff");
    text("▶ 음성 00:18", 290, 926, 23, 900, "#0095F6", "center");
  }
  if (p < 0.32) {
    const seconds = Math.floor(8 + p * 90);
    composer(true, "00:" + String(seconds).padStart(2, "0"));
    waveform(244, 1586, 590, 54, p);
    touch(t, 967, 1758, 27.0, 27.8);
  } else if (p < 0.42) {
    composer(false, "");
    sttSheet((p - 0.32) / 0.10);
  } else {
    composer(false, "");
  }
}
function waveform(x, y, w, h, p) {
  ctx.strokeStyle = "#0095F6";
  ctx.lineWidth = 6;
  ctx.lineCap = "round";
  for (let i = 0; i < 34; i++) {
    const px = x + i * (w / 34);
    const amp = 12 + Math.abs(Math.sin(i * 0.85 + p * 18)) * h;
    ctx.beginPath();
    ctx.moveTo(px, y + h / 2 - amp / 2);
    ctx.lineTo(px, y + h / 2 + amp / 2);
    ctx.stroke();
  }
}
function sttSheet(p) {
  fillRound(0, 1130, W, 790, 54, "#fff");
  strokeRound(0, 1130, W, 1, 0, "#E4E7EC", 1);
  fillRound(448, 1162, 184, 10, 5, "#D0D5DD");
  text("음성 메시지 확인", 54, 1218, 44, 900, "#111");
  if (p < 0.45) {
    circle(106, 1324, 34, "#E3F2FF");
    text("STT 변환 중", 164, 1306, 36, 900, "#111");
    text("Deepgram이 음성을 텍스트로 바꾸고 있습니다.", 164, 1356, 28, 700, "#667085");
    waveform(94, 1468, 892, 74, p);
  } else {
    text("변환 완료", 54, 1300, 30, 900, "#12B76A");
    fillRound(54, 1362, 972, 200, 30, "#F5F6F8");
    wrapText("오늘 저녁 8시에 보이스톡 가능해? 회의 자료도 보내줄게.", 92, 1400, 898, 48, 36, 800, "#111");
    fillRound(54, 1598, 460, 82, 28, "#F0F2F5");
    text("다시 녹음", 284, 1620, 32, 900, "#111", "center");
    fillRound(548, 1598, 478, 82, 28, "#0095F6");
    text("보내기", 787, 1620, 32, 900, "#fff", "center");
  }
}
function recipientChat(t) {
  const p = seg(t, 36, 48);
  chatBase("민지");
  avatar(86, 334, users[0], 38);
  fillRound(142, 296, 760, 246, 34, "#F2F4F7");
  wrapText("오늘 저녁 8시에 보이스톡 가능해? 회의 자료도 보내줄게.", 174, 320, 696, 42, 31, 800, "#111");
  fillRound(174, 430, 244, 50, 25, "#fff");
  text("▶ 음성 00:36", 296, 440, 25, 900, "#0095F6", "center");
  text("민지 · STT 음성 · 방금", 174, 502, 23, 700, "#667085");
  if (p > 0.28) {
    bubble(318, 568, 642, 148, true, "응, 나는 가능해. 회의 링크도 보내줘.", "원본 음성 00:18");
    fillRound(366, 660, 220, 42, 21, "#E3F2FF");
    text("▶ 음성 재생", 476, 668, 23, 900, "#0077CC", "center");
  }
  if (p < 0.20) {
    composer(false, "");
    touch(t, 967, 1758, 38.2, 38.9);
  } else if (p < 0.28) {
    composer(true, "00:18");
    waveform(244, 1586, 590, 54, p);
    touch(t, 967, 1758, 40.8, 41.5);
  } else if (p < 0.38) {
    composer(false, "");
    sttSheet(1);
  } else {
    composer(false, "");
  }
}
function finalSender(t) {
  const p = seg(t, 48, 56);
  senderChat(36);
  fillRound(110, 1080, 860, 96, 30, "rgba(17,17,17," + (0.92 * p) + ")");
  text("가입부터 STT 음성 수발신까지 실제 앱 흐름으로 완료", 540, 1108, 31, 900, "rgba(255,255,255," + p + ")", "center");
  if (p > 0.45) {
    fillRound(190, 1225, 700, 72, 26, "#ECFDF3");
    text("10명 그룹 대화 · 길이 무제한 음성 · STT 텍스트", 540, 1243, 28, 900, "#067647", "center");
  }
}
function drawFrameAt(t) {
  if (t < 8) signup(t);
  else if (t < 16) inbox(t);
  else if (t < 23) groupSelect(t);
  else if (t < 36) senderChat(t);
  else if (t < 48) recipientChat(t);
  else finalSender(t);
}
async function renderUserFlowVideo() {
  drawFrameAt(0);
  const stream = canvas.captureStream(FPS);
  const mimeTypes = ["video/webm;codecs=vp8", "video/webm;codecs=vp9", "video/webm"];
  const mimeType = mimeTypes.find((type) => MediaRecorder.isTypeSupported(type)) || "";
  const recorder = new MediaRecorder(stream, mimeType ? {mimeType, videoBitsPerSecond: 6_000_000} : {videoBitsPerSecond: 6_000_000});
  const chunks = [];
  recorder.ondataavailable = (event) => {
    if (event.data.size) chunks.push(event.data);
  };
  const stopped = new Promise((resolve) => {
    recorder.onstop = resolve;
  });
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
window.renderUserFlowVideo = renderUserFlowVideo;
drawFrameAt(0);
</script>
</body>
</html>`;
}
