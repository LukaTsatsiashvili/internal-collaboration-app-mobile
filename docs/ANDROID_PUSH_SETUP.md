
# Android FCM push setup — dev-luka

Firebase project: `gtex-collaboration`. Android applicationId: `ge.gtexshop.collaboration`.
The existing Kotlin namespace remains `com.example.gtex_collab_app` to retain the current MainActivity and native download channel. Application ID (the value Firebase matches) is changed independently.

## After pulling
1. Install Flutter SDK matching pubspec (Dart >= 3.13.5); run `flutter pub get`. Commit the regenerated `pubspec.lock` once dependency resolution succeeds.
2. `flutter analyze` and `flutter test`.
3. `flutter run` on a physical Android phone with Google Play services. Android 13+ requires granting the notification permission.
4. Your Production API must have `/api/v1/mobile-push` routes and the Firebase sender enabled. Backend instructions: `docs/ANDROID_NATIVE_PUSH.md` in the web/backend repository.
5. Sign in; Native FCM token is registered for that account/session and renewed automatically. Background/terminated alert taps use the existing NotificationsScreen deep-link flow; Android foreground screen retains existing real-time Socket.IO UX.

The shipped `android/app/google-services.json` is the Firebase **public client config**, not the admin service-account secret. Never place a Firebase service-account private key in the Flutter app or repository.

No iOS setup is performed. Current iOS files remain for potential future support, but only Android is initialized. Native push on Android is independent of existing website Web Push.
