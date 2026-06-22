const assert = require("node:assert/strict");
const { VerbalPluginClient, bufferToBase64 } = require("../index");

async function main() {
  const calls = [];
  const client = new VerbalPluginClient({
    coreApiBase: "https://example.com/pluginCoreApi/",
    partnerId: "partner",
    keyId: "key",
    apiKey: "secret",
    fetch: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        status: 200,
        async json() {
          return { ok: true };
        },
      };
    },
  });

  await client.renderMessageCard({
    platform: "slack",
    transcript: "hello",
  });

  assert.equal(calls[0].url, "https://example.com/pluginCoreApi/v1/message-cards");
  assert.equal(calls[0].options.headers["x-verbal-partner-id"], "partner");
  assert.equal(calls[0].options.headers["x-verbal-key-id"], "key");
  assert.equal(calls[0].options.headers["x-verbal-api-key"], "secret");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    platform: "slack",
    transcript: "hello",
  });
  assert.equal(client.audioUrl("audio 1"), "https://example.com/pluginCoreApi/v1/audio/audio%201");
  assert.equal(bufferToBase64(Buffer.from("abc")), "YWJj");

  const failing = new VerbalPluginClient({
    coreApiBase: "https://example.com/pluginCoreApi",
    partnerId: "partner",
    keyId: "key",
    apiKey: "secret",
    fetch: async () => ({
      ok: false,
      status: 401,
      async json() {
        return { error: { message: "bad key" } };
      },
    }),
  });
  await assert.rejects(
    () => failing.transcribeAudio({ audioBase64: "AA==" }),
    /bad key/,
  );

  console.log("verbal-plugin-sdk-ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
