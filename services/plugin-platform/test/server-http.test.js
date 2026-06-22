process.env.VERBAL_CONNECTOR_DEV_MODE = "true";

const assert = require("node:assert/strict");
const { server } = require("../server");

async function main() {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;

  const health = await fetch(`${baseUrl}/healthz`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { ok: true });

  const composer = await fetch(`${baseUrl}/composer/`);
  assert.equal(composer.status, 200);
  assert.match(await composer.text(), /Verbal Voice Composer/);

  const slack = await fetch(`${baseUrl}/connectors/slack/command`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: "team_id=T1&channel_id=C1&user_id=U1",
  });
  assert.equal(slack.status, 200);
  const payload = await slack.json();
  assert.equal(payload.response_type, "ephemeral");
  assert.match(payload.blocks[1].elements[0].url, /platform=slack/);

  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
  console.log("plugin-server-http-ok");
}

main().catch(async (error) => {
  try {
    await new Promise((resolve) => server.close(resolve));
  } catch {
    // ignore cleanup failures in test error path
  }
  console.error(error);
  process.exit(1);
});
