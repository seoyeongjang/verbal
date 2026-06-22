# Verbal Plugin SDK

Verbal Plugin Platform Core API를 호출하기 위한 JavaScript wrapper입니다.

## 사용 예시

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

## 테스트

```powershell
npm test
```
