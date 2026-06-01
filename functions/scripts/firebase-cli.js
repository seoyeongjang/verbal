const fs = require("node:fs");
const path = require("node:path");
const {spawn} = require("node:child_process");

const rootDir = path.resolve(__dirname, "..", "..");
const firebaseBin = path.resolve(
  __dirname,
  "..",
  "node_modules",
  "firebase-tools",
  "lib",
  "bin",
  "firebase.js",
);

const jdkHome = findJdk21();
const env = {...process.env};
if (jdkHome) {
  const currentPath = process.env.Path || process.env.PATH || "";
  env.JAVA_HOME = jdkHome;
  env.Path = `${path.join(jdkHome, "bin")}${path.delimiter}${currentPath}`;
  env.PATH = env.Path;
}

const args = process.argv.slice(2);
const projectId = findProjectId(args);
if (projectId) {
  env.GOOGLE_CLOUD_QUOTA_PROJECT = projectId;
  env.CLOUDSDK_CORE_PROJECT = projectId;
}
const child = spawn(process.execPath, [firebaseBin, ...args], {
  cwd: rootDir,
  env,
  shell: false,
  stdio: "inherit",
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});

function findJdk21() {
  const candidates = [
    process.env.JAVA_HOME,
    "C:\\Program Files\\Microsoft\\jdk-21.0.10.7-hotspot",
    "C:\\Program Files\\Microsoft\\jdk-21",
    "C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.10.7-hotspot",
    "C:\\Program Files\\Eclipse Adoptium\\jdk-21",
  ].filter(Boolean);

  for (const candidate of candidates) {
    const javaExe = path.join(candidate, "bin", process.platform === "win32" ? "java.exe" : "java");
    if (fs.existsSync(javaExe) && candidate.includes("21")) {
      return candidate;
    }
  }

  return process.env.JAVA_HOME || "";
}

function findProjectId(args) {
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--project" && args[index + 1]) {
      return args[index + 1];
    }
    if (arg.startsWith("--project=")) {
      return arg.slice("--project=".length);
    }
  }
  return "voice-messenger-jangs-260522";
}
