# Spreadsheet access with Production Web

Flutter `dev-luka` uses the existing Production web app at
`https://collaboration.gtexshop.ge`. No alternate backend branch is deployed.

Production exposes `/drive/sheets/:id`. The mobile WebView now opens that
HTTPS route. The web spreadsheet handles its normal `/api/v1/drive/sheets/:id`
read/save API calls and conflict detection.

**Important limitation:** The prod website has no dedicated Flutter WebView
authentication bridge (`/mobile/sheets/:id` and
`/auth/mobile-webview-session` are not in prod). The embedded website has
an independent HttpOnly-cookie session. On first use, it may prompt for a web
login even if the Flutter app is already signed in. Once logged in, it returns
to the selected spreadsheet. This is a secure compatibility fallback rather
than full mobile spreadsheet parity. The desktop site's responsive usability
should be verified on a real phone.

Before closing, save in the embedded spreadsheet editor using its Save
button. Native Back shows a confirmation so unsaved changes are not silently
discarded. The app does not inject any native token into WebView JavaScript.

Regression checks:
- Open an existing spreadsheet from Flutter Drive; log in in the WebView if
  prompted; return to the sheet
- Save and re-open data from Flutter and from the desktop site
- Confirm edit vs view-only permissions and version conflict behavior
- Test offline loading and the close confirmation

Full seamless WebView login would require an intentionally designed,
server-supported session exchange; do not expose a native refresh cookie to
JavaScript or change production behavior without a separate review.
