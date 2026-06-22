# Verbal Plugin SDK

JavaScript wrapper for Verbal Plugin Platform Core API.

## Usage

```js
const { VerbalPluginClient, bufferToBase64 } = require("@verbal/plugin-sdk");

const client = new VerbalPluginClient({
  coreApiBase: "https://YOUR_FUNCTION_URL/pluginCoreApi",
  partnerId: "demoPartner",
  keyId: "default",
  apiKey: process.env.VERBAL_PLUGIN_API_KEY,
});

const result = await client.transcribeAudio({
  audioBase64: bufferToBase64(audioBuffer),
  contentType: "audio/mp4",
  language: "ko",
  storeAudio: true,
});

const card = await client.renderMessageCard({
  platform: "slack",
  transcript: result.transcript,
  audioUrl: result.audioUrl,
});
```

## Test

```powershell
npm test
```
