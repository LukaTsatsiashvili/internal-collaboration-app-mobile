# Flutter Drive → Univer Spreadsheet

This documents the first working integration on **dev-luka**. The Flutter
Drive screen creates and opens the *same* virtual Univer spreadsheet records
as the web application. No alternate spreadsheet storage format is introduced.

## Repositories and deployment dependency

- Mobile: `LukaTsatsiashvili/internal-collaboration-app-mobile`, `dev-luka`
- Backend/Web: `U-riani/internal-collaboration-app`, `dev-luka`

**The web and API changes must be deployed at
`https://collaboration.gtexshop.ge` before opening a sheet on a device.**
The mobile application explicitly opens
`https://collaboration.gtexshop.ge/mobile/sheets/:id`.
Updating only the Flutter app while the server still runs the old web code
will not provide this route.

The mobile app requires the new `webview_flutter` dependency. Run
`flutter pub get` (and commit the regenerated `pubspec.lock` in your
Flutter environment) before `flutter run`.

## Current single-server developer test setup

The developer currently runs **web/backend `dev-luka` instead of `prod`**
from the existing server checkout at `https://collaboration.gtexshop.ge`.
No new staging host, Cloudflare Tunnel or separate database is required.

**Both** the web frontend build and backend service must run the `dev-luka`
code: the web editor requires the `/mobile/sheets/:id` route and the backend
requires `POST /api/v1/auth/mobile-webview-session`.

On the server, ensure local changes are clean or backed up before switching:

```bash
cd ~/apps/internal-collaboration-app
git status
git fetch origin
git switch dev-luka
git pull --ff-only origin dev-luka
npm --prefix apps/web run build
sudo systemctl restart collaboration-api
sudo systemctl status collaboration-api --no-pager
```

Verify Nginx actually serves the freshly built `apps/web/dist`. The above
commands match the currently described systemd deployment, not the optional
Docker Compose production template. Do not perform `git merge` into `prod`
just to run this test.

On the Flutter development laptop:

```bash
git switch dev-luka
git pull --ff-only origin dev-luka
flutter pub get
flutter test test/drive_import_and_folder_test.dart
flutter test test/spreadsheet_editor_url_test.dart
flutter run
```

The Flutter API and WebView editor use the **same HTTPS origin automatically**,
derived from `ApiClient.baseUrl`, which defaults to
`https://collaboration.gtexshop.ge/api/v1`. An optional
`COLLAB_API_BASE_URL` override is supported for future isolated environments,
but is not needed for this single-server setup. Do not set `COLLAB_ORIGIN`.

To revert the deployed web/backend **without rewriting either GitHub branch**,
switch the server checkout back to `prod`, rebuild web, and restart its
backend. As always, make a database backup before experimental operations.

## Implementation

1. Drive → New Spreadsheet opens the existing app-styled name dialog.
2. `DriveService.createSpreadsheet` posts to `/api/v1/drive/sheets`,
   preserving the currently selected `spaceId` and `parentId`.
3. A new or existing spreadsheet opens a Flutter WebView route.
4. The WebView bridge delivers the current access token from
   `flutter_secure_storage` to the *first-party* web origin in JS memory.
   **No tokens are put into links or persisted in browser localStorage.**
5. The web app exchanges this authenticated token for a dedicated
   HttpOnly refresh-cookie session via `POST /api/v1/auth/mobile-webview-session`,
   then uses the existing React Univer editor.
6. Sheets are fetched and saved through the existing
   `/api/v1/drive/sheets/:id` endpoints. Web and Flutter use the same
   snapshot, versioning, permission and merge-conflict rules.

The route must remain same-origin. The Flutter NavigationDelegate rejects
main-frame navigation away from this HTTPS editor route.

## First-release limitations

- This version embeds the existing **Univer 1.0.2 desktop preset** in a
  full-height mobile WebView. The experimental official mobile UI plugins
  have **not** been validated or enabled yet. Formula and sheet behavior
  comes from the existing web engine, while advanced mobile touch ergonomics
  remain a follow-up.
- The JavaScript editor still downloads SDK modules/styles from external
  CDNs. Before broad production rollout, pin and self-host them and test a
  restrictive CSP.
- Large workbooks, keyboard behavior, clipboard, pinch zoom, offline saving
  and rapid application close/resume need testing on real Android/iOS devices.
- Android/iOS builds and live backend integration **have not been executed**
  in the ChatGPT environment; verify before promoting to production.
- Authentication/logout behavior between native sessions and temporary
  WebView sessions warrants device-level lifecycle testing.

## Manual acceptance checks

1. Sign in, open Personal → New Spreadsheet and enter a name.
2. Confirm that it appears in Drive, opens in the editor, and is also
   present/editable in the existing web Drive.
3. Repeat creation in a nested Shared folder; verify the location.
4. Edit cells/formulas, close and reopen, and confirm persistence.
5. Import XLSX using the existing mobile Import Excel action, then tap the
   created sheet to edit it.
6. Check VIEWER versus EDITOR and EDITOR_DELETE accounts. Only authorized
   editors may save.
7. Open the same sheet in web and mobile, edit different cells, save both,
   and verify merge; then edit the same cell and verify conflict UI.
8. Test access expiry, network loss, Android system Back/navigation gestures,
   save conflicts and keyboard behavior.

The desktop web spreadsheet route `/drive/sheets/:id` remains unchanged
except for the permission alignment for `EDITOR_DELETE`.
