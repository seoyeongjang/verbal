const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {
  buildComposerUrl,
  buildSlackOpenComposerResponse,
  parseSlackFormBody,
  verifySlackSignature,
} = require("./src/slack-connector");

const publicDir = path.join(__dirname, "public");
const port = Number(process.env.PORT || 8787);
const publicBaseUrl =
  process.env.VERBAL_PLUGIN_PUBLIC_URL || `http://127.0.0.1:${port}`;
const slackSigningSecret = process.env.SLACK_SIGNING_SECRET || "";
const connectorDevMode =
  String(process.env.VERBAL_CONNECTOR_DEV_MODE || "false").toLowerCase() ===
  "true";

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", publicBaseUrl);
    if (request.method === "GET" && url.pathname === "/healthz") {
      sendJson(response, 200, { ok: true });
      return;
    }
    if (request.method === "GET" && url.pathname === "/") {
      response.writeHead(302, { location: "/composer/" });
      response.end();
      return;
    }
    if (
      request.method === "POST" &&
      (url.pathname === "/connectors/slack/command" ||
        url.pathname === "/connectors/slack/interactive")
    ) {
      await handleSlackRequest(request, response);
      return;
    }
    if (request.method === "GET") {
      serveStatic(url.pathname, response);
      return;
    }
    sendJson(response, 405, {
      error: { code: "method_not_allowed", message: "Method not allowed." },
    });
  } catch (error) {
    sendJson(response, 500, {
      error: {
        code: "internal",
        message: error instanceof Error ? error.message : "Request failed.",
      },
    });
  }
});

if (require.main === module) {
  server.listen(port, () => {
    console.log(`Verbal plugin platform listening on ${publicBaseUrl}`);
  });
}

async function handleSlackRequest(request, response) {
  const rawBody = await readRequestBody(request);
  const signature = request.headers["x-slack-signature"];
  const timestamp = request.headers["x-slack-request-timestamp"];
  const verified =
    connectorDevMode ||
    verifySlackSignature({
      rawBody,
      timestamp,
      signature,
      signingSecret: slackSigningSecret,
    });
  if (!verified) {
    sendJson(response, 401, {
      error: {
        code: "invalid_slack_signature",
        message: "Slack request signature verification failed.",
      },
    });
    return;
  }
  const payload = parseSlackFormBody(rawBody);
  const teamId = payload.team_id || payload.team?.id || "";
  const channelId = payload.channel_id || payload.channel?.id || "";
  const userId = payload.user_id || payload.user?.id || "";
  const composerUrl = buildComposerUrl({
    baseUrl: publicBaseUrl,
    teamId,
    channelId,
    userId,
  });
  sendJson(response, 200, buildSlackOpenComposerResponse({ composerUrl }));
}

function serveStatic(urlPath, response) {
  const normalized = decodeURIComponent(urlPath).replace(/\\/g, "/");
  const relativePath =
    normalized.endsWith("/") || normalized === ""
      ? `${normalized}index.html`
      : normalized;
  const filePath = path.normalize(path.join(publicDir, relativePath));
  if (filePath !== publicDir && !filePath.startsWith(`${publicDir}${path.sep}`)) {
    sendJson(response, 403, {
      error: { code: "forbidden", message: "Forbidden path." },
    });
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      sendJson(response, 404, {
        error: { code: "not_found", message: "File not found." },
      });
      return;
    }
    response.writeHead(200, {
      "content-type": contentTypeForPath(filePath),
      "cache-control": "no-store",
    });
    response.end(data);
  });
}

function contentTypeForPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".html") {
    return "text/html; charset=utf-8";
  }
  if (ext === ".js") {
    return "text/javascript; charset=utf-8";
  }
  if (ext === ".css") {
    return "text/css; charset=utf-8";
  }
  if (ext === ".json") {
    return "application/json; charset=utf-8";
  }
  return "application/octet-stream";
}

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

module.exports = { server };
