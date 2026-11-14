# Optional Google / YouTube account configuration

The iOS client uses Google's native OAuth flow in `ASWebAuthenticationSession`, not an embedded form that collects passwords. Authorization uses PKCE and a random state; refresh/access tokens are stored in the iOS Keychain with a device-only accessibility class.

Without an OAuth client ID, local playback/library/discovery/lyrics work and Settings clearly marks Google sign-in as unconfigured.

## Configure your project

1. In your own Google Cloud project, enable **YouTube Data API v3**.
2. Configure the OAuth consent screen. When the app is in testing mode, add the Google accounts you want to test with. The requested scope is `https://www.googleapis.com/auth/youtube.force-ssl` because importing reads playlists and explicit uploads add songs.
3. Create an OAuth client with application type **iOS**. Register the actual bundle identifier of the signed app (the source default is `app.mochy.music.ios`; some sideloading tools change it). Follow any verification requirements Google displays.
4. In **your fork**, go to Settings → Secrets and variables → Actions → Variables. Add `GOOGLE_OAUTH_CLIENT_ID` with the iOS client ID ending in `.apps.googleusercontent.com`. A client ID is configuration, not an account password. Do not add an Apple ID password, Google password, client secret, access token or refresh token.
5. Run the iOS Build workflow against `codex/ios-native-foundation`, or push an iOS change. `ios/Scripts/configure_oauth.py` injects the client ID and its reversed URL scheme into the build's Info.plist. Sign/install that newly generated IPA.
6. In the app, Settings → 登录 Google / YouTube. Complete Google's authorization on the phone. Actual sign-in needs to be verified with your configured project and account.

For a local Xcode build, run `GOOGLE_OAUTH_CLIENT_ID=your-ios-client-id python3 ios/Scripts/configure_oauth.py` before building, or add `GoogleOAuthClientID` and the matching reversed-client-ID URL scheme to your local Info.plist. Do not commit a developer's account tokens.

## Sync behavior

- **Import:** reads all pages of the signed-in account's API-accessible playlists and their songs, then updates local playlists by stable remote playlist ID. Local-only playlists and favorites remain local. Importing again replaces the contents of previously imported remote playlists with the latest remote contents.
- **Upload:** invoked explicitly from a local playlist's menu. Creates a **private** YouTube playlist when it has no remote ID, then appends songs not already present. Retrying after a partial upload avoids adding the same video again. It does not delete remote songs or rewrite their order.
- OAuth does not grant access to every YouTube Music-specific feature. The Data API may omit Music-only/private categories. Guest homepage recommendations remain guest recommendations; local history supplies a separate artist-exploration section.
- Sign-out cancels account operations and removes local Keychain tokens. Revoking the app's grant on Google's account permissions page is a separate user action.

Google API quotas, consent-screen testing restrictions, account permissions and authorization verification may limit sync. Failures are shown in Settings and do not report success or silently delete local playlists.

References:
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developers.google.com/youtube/v3/docs/playlists/list
- https://developers.google.com/youtube/v3/docs/playlistItems/insert
