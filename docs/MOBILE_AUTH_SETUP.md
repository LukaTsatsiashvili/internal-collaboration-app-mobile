# Native mobile authentication — dev-luka

The Flutter native app and the web app have **different refresh credential transports**
but use the **same PostgreSQL-backed revocable Session records**.

## Deployment order (required)

1. Update and restart the **backend** from
   `U-riani/internal-collaboration-app`, branch `dev-luka`.
   The new API must expose:
   - `POST /api/v1/auth/mobile/login`
   - `POST /api/v1/auth/mobile/refresh`
   - `POST /api/v1/auth/mobile/logout`
2. Verify backend routes using the API tests:
   `npm --prefix apps/api test` (requires a test PostgreSQL database).
3. Pull `LukaTsatsiashvili/internal-collaboration-app-mobile` `dev-luka`,
   run `flutter pub get` and `flutter test test/auth_session_test.dart`.
4. Use **Flutter - Local Server** for local validation and only then select
   **Flutter - Production Server** when that server has the updated backend.
   The production launch profile does **not** deploy the API.

An older backend without `/auth/mobile/*` is **not compatible** with this
version of the Flutter client. Do not distribute the updated app before the
matching backend has been deployed.

## Session behavior

- Native login returns an access token and a rotating refresh token in JSON,
  over HTTPS (or ADB/loopback debug HTTP). Both are held in
  `flutter_secure_storage`. Never log the credentials or put them in URLs.
- All API services share one Dio client. When an access token expires, only
  **one** refresh request is attempted for concurrent 401 responses; the
  original request is retried once with the new access token.
- A refresh 401/403 means the native session is no longer valid. Tokens are
  erased; the user sees the unified modal then goes to Login.
- A transient error (offline, timeout, 429, 5xx) **does not sign out** the user.
  On cold start the splash screen offers Retry or a deliberate account switch.
- Native logout revokes that native session on the backend when reachable and
  erases both local credentials in all cases. Offline logout cannot guarantee
  remote revocation before server session expiry; avoid sharing the device.
- The web app retains its original HttpOnly refresh-cookie endpoints. The
  separate Flutter Spreadsheet WebView session remains managed by the web
  route and its existing cookie-based authentication.
- Existing installs have only a legacy access token without a refresh token;
  they will require **one new sign-in** after upgrading to this mechanism.

## Offline/reconnect verification (current regression)

- Flutter-side reconnect fix only: **no Web/Backend code changes are required**
  for this patch. The backend must already support the native mobile API
  endpoints introduced in the earlier authorization phase.
- Run `flutter test test/auth_reconnect_test.dart` and
  `flutter test test/auth_session_test.dart` before device verification.
- Disconnect mobile Internet while signed in, restart the app and confirm
  that Retry remains available without deleting saved credentials.
- Restore Internet **without terminating the app**, select Retry, and verify
  entry into Dashboard. Then repeat with an expired access token.
- Choose "სხვა ანგარიშით შესვლა" when offline, re-enable Internet and
  sign in using the same valid credentials. The login must not reuse stale
  Authorization headers.
- If Login displays the local transport warning, verify the running
  `npm run dev` terminal, `adb devices`, and `adb reverse --list`.
  ADB reverse is required for the Local Server debug profile.
- If Login says the mobile API is not installed, update and restart the
  selected backend branch before retrying. Do not misdiagnose a 404 as
  incorrect credentials.
- Login POSTs and refresh-token rotation POSTs must **not** be automatically
  repeated after a network timeout; automatically retrying these requests
  risks duplicated sessions or consuming an already-rotated credential.

## Manual regression checklist

- Login with a valid and an invalid password.
- Stay signed in for more than 15 minutes. Open Tasks, Approvals and Drive.
- Kill/relaunch the app after the access token expires; user stays signed in.
- Issue simultaneous requests after token expiry; only one mobile refresh
  request should occur.
- Disconnect network; force-close and open the app. Confirm Retry screen
  rather than an unexpected Login. Reconnect and retry successfully.
- Revoke a session (or change account password) on the backend; confirm the
  non-dismissible overlay explanation and Login navigation.
- Logout and verify `/auth/me` rejects the old access token (server reached).
- Use both Local and Production launch profiles, ensuring API origins match.
- Verify spreadsheet opening and web-side session behavior separately.
- Confirm Messages and Notifications realtime after 15 minutes;
  **Socket.IO token reauthentication is addressed in the next dedicated
  realtime stabilization phase**, not by this REST auth change.

Do not assume that source-level and unit tests prove device-level behavior.
Validate on physical Android/iOS hardware before broad rollout.
