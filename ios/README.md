# Mochy Music for iOS

This folder starts a native SwiftUI iOS client alongside the existing Android app.

## Current slice

The app provides a native AVPlayer playback path for a direct HTTP(S) audio URL, configures the iOS playback audio session, enables background audio, and publishes lock-screen / headset transport controls and now-playing metadata.

## Open and run

Open `MochyMusic.xcodeproj` in Xcode 15 or later, select an iPhone simulator or device, then run the `MochyMusic` scheme. Set a valid development team in Signing & Capabilities when installing on a physical device.

## Porting sequence

1. Connect catalog search and stream resolution to the existing provider APIs.
2. Add queue, lyrics, artwork, and library persistence.
3. Replace the URL entry screen with the Mochy home, search, and player flows.
4. Add account import and sync only after their service-specific callback and token-storage behavior is mapped to iOS.

Provider and playback code in the Android app is currently Android/JVM-specific; the iOS target is a native client and will port those contracts incrementally.
