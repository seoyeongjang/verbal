const crypto = require("node:crypto");

const MAX_TIMESTAMP_DRIFT_SECONDS = 60 * 5;

function verifySlackSignature({
  rawBody,
  timestamp,
  signature,
  signingSecret,
  nowMs = Date.now(),
}) {
  if (!signingSecret) {
    return false;
  }
  const timestampSeconds = Number(timestamp);
  if (!Number.isFinite(timestampSeconds)) {
    return false;
  }
  const nowSeconds = Math.floor(nowMs / 1000);
  if (Math.abs(nowSeconds - timestampSeconds) > MAX_TIMESTAMP_DRIFT_SECONDS) {
    return false;
  }
  const base = `v0:${timestamp}:${rawBody}`;
  const expected = `v0=${crypto
    .createHmac("sha256", signingSecret)
    .update(base)
    .digest("hex")}`;
  return timingSafeEqual(expected, signature || "");
}

function parseSlackFormBody(rawBody) {
  const params = new URLSearchParams(rawBody);
  if (params.has("payload")) {
    return JSON.parse(params.get("payload"));
  }
  return Object.fromEntries(params.entries());
}

function buildComposerUrl({ baseUrl, teamId, channelId, userId }) {
  const url = new URL("/composer/", baseUrl);
  if (teamId) {
    url.searchParams.set("team", teamId);
  }
  if (channelId) {
    url.searchParams.set("channel", channelId);
  }
  if (userId) {
    url.searchParams.set("user", userId);
  }
  url.searchParams.set("platform", "slack");
  return url.toString();
}

function buildSlackOpenComposerResponse({ composerUrl }) {
  return {
    response_type: "ephemeral",
    text: `Open Verbal voice composer: ${composerUrl}`,
    blocks: [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Verbal Voice Composer*\nRecord a voice message, convert it to text, then paste or send the generated Slack card.",
        },
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: "Open composer",
            },
            url: composerUrl,
            action_id: "open_verbal_composer",
          },
        ],
      },
    ],
  };
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

module.exports = {
  buildComposerUrl,
  buildSlackOpenComposerResponse,
  parseSlackFormBody,
  verifySlackSignature,
};
