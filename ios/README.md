# Mochy Music for iOS

Native SwiftUI client, minimum iOS 17.0. Open `MochyMusic.xcodeproj` and select the `MochyMusic` scheme.

## Included in 0.2

- Search and AAC/MP4 playback with the same successful client configuration as the initial playback fix.
- Editable persistent queue, play next, previous/next, shuffle without repeats within an order, repeat off/all/one, and automatic advance.
- Local favorites, named playlists, playlist editing/reordering, playback history and search history.
- Atomic JSON persistence, explicit backup/restore, and preservation of unreadable library files.
- Headset and lock-screen controls/artwork, interruption handling, pause on route disconnect, bounded stream refresh/retry, recovery after connectivity returns, and startup/stall timeouts.
- Guest YouTube Music discovery plus artist exploration based on local listening history.
- Lyrics from LRCLIB with timed LRC highlighting/seeking where available; YouTube Music plain lyrics fallback. Lyrics availability depends on the song and provider.
- Optional Google OAuth authorization using the system authentication browser, PKCE/state validation, Keychain tokens, token refresh, logout, cloud playlist import, and explicit playlist upload.

Google login is unavailable until the repository owner configures an iOS OAuth client. See [ACCOUNT_SETUP.md](ACCOUNT_SETUP.md). No Google credentials are included in the source or IPA. YouTube Music account-only recommendations and every category of its private library are not exposed by the official YouTube Data API; cloud sync covers the playlists that API makes accessible.

## Build and checks

`.github/workflows/ios-build.yml` runs stream-selection regression checks, queue/library/lyrics/catalog checks, OAuth configuration checks, an iOS Simulator build, and a Release iPhone build. The iPhone artifact contains an unsigned IPA that needs signing before installation. Build success does not verify real-world YouTube access, Google account authorization, or physical-device interruptions.

No pull request to the upstream repository is needed. All development is on the owner's `codex/ios-native-foundation` branch.

## Physical-device checks

1. Play a song beyond five minutes; seek, pause/resume, and advance a multi-song queue.
2. Test shuffle, repeat one/all, reorder and deletion of the active queue item.
3. Lock the phone, use headset controls, disconnect the headset, and receive/end a call. Resume after a call only when iOS allows it.
4. Disable/re-enable networking. Recovery retries are capped at two per failure sequence; user pause cancels recovery.
5. Relaunch the app and confirm favorites/playlists/history/queue survive. Export and restore a backup.
6. Try lyrics with and without timestamps. Tap a timed line to seek.
7. After OAuth configuration, authenticate with a test account, import playlists, explicitly upload a private playlist, then sign out.

Local library backups include listening/search history. Google tokens are stored only in Keychain, never in those backups. Lyrics lookup sends track title, artist and optional duration to LRCLIB, with provider attribution in the app.
