# Production authentication — Flutter dev-luka

## Deployment contract

- Single backend: deployed `U-riani/internal-collaboration-app` **prod**.
- API: `https://collaboration.gtexshop.ge/api/v1` (fixed HTTPS).
- Flutter is developed and tested on the **dev-luka** mobile branch.
- No WSL, local Node API, ADB reverse mapping or Flutter API launch override is required.
- Existing backend endpoints: `POST /auth/login`, `POST /auth/refresh`,
  `POST /auth/logout`, `GET /auth/me`. **No backend branch change.**

## Native session lifecycle

The prod login and refresh endpoints return a short-lived access token in JSON
and a rotating `collab_refresh_token` in their `Set-Cookie` response header.
A native Dio HTTP client does not automatically persist that browser cookie.
Flutter extracts only this first-party refresh-cookie value, keeps it in
`flutter_secure_storage`, and sends it back in the `Cookie` header only on
`/auth/refresh` and `/auth/logout`. It is never put in query strings, logs,
WebViews or ordinary app preferences. All requests use HTTPS.

Concurrent access-token expiry results in a single refresh request, replaying
the failed request only once. When connectivity is lost, the existing credentials
are retained and startup offers Retry. Definitive refresh-token revocation
triggers the single session-expired dialog, followed by login.

**Migration:** A refresh credential from the previous, non-production native
endpoint cannot be exchanged against prod. Existing installs may require **one
new login**. Old mobile refresh credentials are removed on sign-out/new login.

Logout invalidates the prod server session if reachable and always clears native
credentials. If offline, server revocation is not guaranteed until the existing
session expires.

## WebView spreadsheets

The prod frontend supports `/drive/sheets/:id`, **not** the newer
`/mobile/sheets/:id` bridge. The mobile editor therefore opens the existing
HTTPS desktop web page in a WebView with its **own browser session**.
The first use may require a second web login inside the editor; a successful
web sign-in redirects to the requested sheet. Browser and native credentials
are never exchanged in JavaScript. Users should save using the web editor's
Save button before closing; mobile-first layout/automatic shared login will
require compatible future prod frontend/backend changes.

## Validation

```sh
flutter pub get
flutter analyze
flutter test test/auth_session_test.dart test/auth_reconnect_test.dart
flutter test test/spreadsheet_editor_url_test.dart
flutter test
```

Test login/relogin, one access-token lifetime, offline/reconnect Retry, native
logout and browser spreadsheet opening on a physical Android device.
The GitHub Actions workflow runs targeted auth tests on dev-luka updates.
