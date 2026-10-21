# Flutter local / production launch profiles

The Flutter `dev-luka` branch has two VS Code debug launch profiles in `.vscode/launch.json`.
Both use the same Flutter code; the selected API origin is passed at compile time via
`COLLAB_API_BASE_URL`. After switching profiles, stop the current debug session
and start the new one with F5. Hot reload does not change compile-time defines.

## Local Server

1. Run the web and backend `dev-luka` branch in Ubuntu/WSL (`npm run dev`).
   The Vite server listens on port 5173, proxies `/api` and `/socket.io`
   to Fastify on port 3000, and Fastify connects to the local PostgreSQL DB.
2. Connect **one** Android phone to Windows by USB. Enable/authorize USB debugging.
3. Select **Flutter - Local Server** in VS Code Run and Debug and press F5.
   Its `preLaunchTask` runs `adb reverse tcp:5173 tcp:5173` on Windows.
   `adb` must be on PATH. If more than one Android device is attached,
   select one or remove the others before using this task.
4. The mobile API, WebSocket and embedded spreadsheet editor use the loopback
   origin `http://127.0.0.1:5173`; USB reverse reaches the WSL Vite proxy.
   Test the tunnel by opening `http://127.0.0.1:5173/api/v1/auth/me`
   in the **phone's browser**. An unauthenticated JSON/401 response confirms
   that the local API is reachable.

The Android debug manifest permits cleartext traffic **only in debug builds**.
Spreadsheet WebView permits HTTP only on `localhost`, `127.0.0.1`, or `::1`
**in debug mode**; every other host or non-debug build still requires HTTPS.
Do not disable these production safeguards.

## USB reconnect and the Retry button

**Local Server is not an Internet-hosted endpoint.** The address
`http://127.0.0.1:5173` refers to the **Android device**, not the laptop.
The app can reach the WSL server only while an authorized ADB connection
is present **and** the port 5173 reverse mapping is active. Connecting
the phone to mobile data or ordinary Wi-Fi does not recreate that mapping.

After unplugging/replugging USB while Flutter is still open, execute in
**Windows PowerShell**:

```powershell
adb devices
adb reverse tcp:5173 tcp:5173
adb reverse --list
```

On the **phone browser**, request
`http://127.0.0.1:5173/api/v1/auth/me`. A JSON **401 response**
without credentials confirms the API is reachable and is **expected**.
A browser network error means the tunnel is not established yet; Retry
in Flutter will not repair the ADB mapping.

On **Windows PowerShell**, independently check the PC's Vite proxy:

```powershell
curl.exe -i http://127.0.0.1:5173/api/v1/auth/me
```

Check that Vite's development server and Fastify are running in WSL.
If the phone should operate without USB, use Production Server for the
Internet-accessible HTTPS deployment or set up a separately configured
wireless-ADB/local-network profile; that mode is not enabled by the
current Local Server launch profile.

## Production Server

Select **Flutter - Production Server** and press F5. It uses the HTTPS API
`https://collaboration.gtexshop.ge/api/v1`. This launch profile does **not**
deploy the backend: the remote server must be online and serve the compatible
API and the `/mobile/sheets/:id` web route for spreadsheets to work.

## Changing environments

- Log out of the previous environment before switching where possible; the
  current native app stores one shared `access_token`, so a token from one
  server cannot authenticate against the other. If necessary, sign in again.
- ADB reverse does not persist across every USB disconnect/reboot; the Local
  profile recreates it on the next launch.
- If a Local launch fails before app startup, check `adb devices` and
  `adb reverse --list` in **Windows PowerShell**. WSL's `adb` is not used.
- The backend is not started by VS Code. Keep the Ubuntu `npm run dev`
  terminal open while working with Local.
- Neither profile changes the branch; use `dev-luka` in your working tree.

## Verification

Run `flutter test test/spreadsheet_editor_url_test.dart` and
`flutter analyze` locally. Also validate sign-in, messages/realtime, and
the spreadsheet editor on a physical Android device; device-level integration
is not proven by unit tests alone.
