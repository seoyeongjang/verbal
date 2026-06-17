# Local Testing

This project can be tested before Google Play registration by running the Flutter app in demo mode on web or Windows desktop.

## Web Demo

Run:

```powershell
.\scripts\run-local-web.ps1
```

Then open:

```text
http://127.0.0.1:55173
```

If that port is already in use, pass another port:

```powershell
.\scripts\run-local-web.ps1 -Port 55174
```

The script forces `VERBAL_DEMO=true`, so it does not require Firebase Auth, Firebase Storage, Cloud Functions, Deepgram API keys, or Google Play app registration.

If you need real speech-to-text instead of the fixed demo transcript, use `docs/LOCAL_STT_TESTING.md` and run:

```powershell
.\scripts\run-local-stt-web.ps1
```

If you need zero-cost speech-to-text testing, use `docs/FREE_STT_TESTING.md` and run:

```powershell
.\scripts\run-free-stt-web.ps1
```

Use this path for fast MVP checks:

- demo login
- room list
- chat screen
- text message send
- microphone permission request
- voice recording
- automatic voice send after STT succeeds
- STT recovery flow
- local audio playback

## Windows Desktop Demo

Run:

```powershell
.\scripts\run-local-windows.ps1
```

This also uses demo mode. Windows desktop builds may require Visual Studio with the Desktop development with C++ workload. If that toolchain is missing, use the web demo first.

On Windows, Flutter plugins also require Developer Mode for symlink support. If the build prints `Building with plugins requires symlink support`, open Windows Settings > System > For developers and enable Developer Mode, then rerun the script.

## Static Web Build

Run:

```powershell
.\scripts\build-local-web.ps1
```

The build output is:

```text
apps/mobile/build/web
```

To serve that built app locally:

```powershell
.\scripts\serve-built-web.ps1
```

Open:

```text
http://127.0.0.1:55173
```

## Scope

Local demo mode is for UI and UX testing before store registration. It does not validate the real Firebase backend, real phone authentication, real Cloud Functions, real Storage uploads, FCM, or Deepgram STT. Those require the remaining Firebase Blaze and API-key setup.
