const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  buildComposerUrl,
  buildSlackOpenComposerResponse,
  parseSlackFormBody,
  verifySlackSignature,
} = require("../src/slack-connector");

const secret = "signing-secret";
const rawBody = "team_id=T1&channel_id=C1&user_id=U1";
const timestamp = "1781677000";
const signature = `v0=${crypto
  .createHmac("sha256", secret)
  .update(`v0:${timestamp}:${rawBody}`)
  .digest("hex")}`;

assert.equal(
  verifySlackSignature({
    rawBody,
    timestamp,
    signature,
    signingSecret: secret,
    nowMs: 1781677000 * 1000,
  }),
  true,
);
assert.equal(
  verifySlackSignature({
    rawBody,
    timestamp,
    signature: "v0=bad",
    signingSecret: secret,
    nowMs: 1781677000 * 1000,
  }),
  false,
);

const parsed = parseSlackFormBody(rawBody);
assert.equal(parsed.team_id, "T1");
assert.equal(parsed.channel_id, "C1");
assert.equal(parsed.user_id, "U1");

const composerUrl = buildComposerUrl({
  baseUrl: "https://plugin.verbal.example",
  teamId: "T1",
  channelId: "C1",
  userId: "U1",
});
assert.match(composerUrl, /\/composer\//);
assert.match(composerUrl, /platform=slack/);

const response = buildSlackOpenComposerResponse({ composerUrl });
assert.equal(response.response_type, "ephemeral");
assert.equal(response.blocks[1].elements[0].url, composerUrl);

console.log("slack-connector-ok");
