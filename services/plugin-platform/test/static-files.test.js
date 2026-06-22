const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const publicDir = path.join(__dirname, "..", "public");

const composerHtml = read("composer/index.html");
const composerJs = read("composer/app.js");
const adminHtml = read("admin/index.html");
const adminJs = read("admin/app.js");

assert.match(composerHtml, /Verbal Voice Composer/);
assert.match(composerHtml, /id="recordButton"/);
assert.match(composerHtml, /id="coreApiBase"/);
assert.match(composerJs, /\/v1\/transcriptions/);
assert.match(composerJs, /\/v1\/message-cards/);
assert.match(adminHtml, /Verbal Partner Admin/);
assert.match(adminHtml, /id="generateButton"/);
assert.match(adminJs, /SHA-256/);
assert.match(adminJs, /pluginPartners/);

console.log("plugin-static-files-ok");

function read(relativePath) {
  return fs.readFileSync(path.join(publicDir, relativePath), "utf8");
}
