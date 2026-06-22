const assert = require("node:assert/strict");
const {
  pluginMessageCardInput,
  pluginPlatform,
  renderPluginMessageCard,
} = require("../lib/plugin-platform.js");

{
  assert.equal(pluginPlatform("Slack"), "slack");
  assert.equal(pluginPlatform("unknown"), "generic");
}

{
  const card = renderPluginMessageCard(
    pluginMessageCardInput({
      platform: "slack",
      transcript: "Can we talk at 8 PM?",
      audioUrl: "https://example.com/audio",
      senderName: "Minji",
    }),
  );
  assert.equal(card.platform, "slack");
  assert.match(card.plainText, /Can we talk/);
  assert.equal(card.richCard.blocks[0].type, "section");
  assert.equal(card.richCard.blocks[1].type, "actions");
}

{
  const card = renderPluginMessageCard(
    pluginMessageCardInput({
      platform: "kakao",
      transcript: "오늘 저녁 8시에 통화 가능합니까?",
      audioUrl: "https://example.com/audio",
    }),
  );
  assert.equal(card.platform, "kakao");
  assert.equal(card.richCard.object_type, "text");
  assert.equal(card.richCard.button_title, "Open voice");
}

{
  const card = renderPluginMessageCard(
    pluginMessageCardInput({
      platform: "teams",
      transcript: "Launch review",
      calendarTitle: "Demo review",
      calendarStartAt: "2026-07-03T05:00:00.000Z",
    }),
  );
  assert.equal(card.platform, "teams");
  assert.equal(card.richCard.type, "AdaptiveCard");
  assert.match(card.plainText, /Calendar: Demo review/);
}

console.log("plugin-platform-ok");
