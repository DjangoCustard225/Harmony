# Building Harmony

Use Xcode 27 and Swift 6.4 or later. Open `Harmony.xcodeproj`, choose a signing team, and run the Harmony scheme on an iPhone or iPad with iOS 27 or later.

Regenerate the project after adding Swift files or changing the version in `Harmony/Info.plist`:

```sh
swift Scripts/GenerateXcodeProject.swift
```

On macOS, `bash Scripts/BuildIPA.sh` builds and verifies an unsigned `dist/Harmony.ipa`.

On Linux, use xtool with a compatible iOS 27 SDK:

```sh
xtool dev build -c release --triple arm64-apple-ios27.0 --ipa
```

This writes `xtool/Harmony.ipa`. Linux uses `AppIcon.png`; Xcode uses the `HarmonyIcon.icon` source. The bundle identifier is `app.harmony.music`, separate from Gevun.

Run core tests and format checks:

```sh
swift test --package-path Core
swift format lint --strict --recursive Harmony Core/Sources Core/Tests Scripts Package.swift Core/Package.swift
```

Device validation:

1. Import tagged MP3, M4A/ALAC, FLAC, WAV, and AIFF samples from Files, including one cloud provider and an audio file reported as generic data.
2. Check title/artist/album, artwork, album order, search, and filename fallback for untagged files.
3. Relaunch, enable airplane mode, and verify playback, seeking, queue, repeat/shuffle, background audio, and lock-screen controls.
4. Verify an unsupported or damaged file reports an import error while other selected files still import.
5. Share a track, then remove its imported copy; verify the source file remains unchanged.
6. Update a library imported by build 1 or 2 and verify missing embedded artwork, artist/album tags, and lyrics are recovered without reimporting.
7. Pull down on artist pages and verify the portrait stretches to cover the top edge without a black refresh gap. Check artist rows and pages for portraits, biographies, attribution links, and offline cached photos. Disable online artist details in Settings and verify that library playback remains available.
8. Open an audio file through Files → Share → Harmony and confirm it imports.

Core tests cover FLAC comments, legacy library upgrades, LRC timestamps/offsets, grouping, disc/track ordering, persistence, search, deletion, queue behavior, playback timing, now-playing publication, and player dismissal. UI, file provider, metadata extraction, and audio output checks require a device.

The picker uses the system document picker in copy mode and permits generic files because some providers do not classify audio correctly. AVFoundation validates each selected file before adding it to the library. No iCloud container or custom document-access entitlement is required by this import path.

To compare FLAC extraction against an independent metadata oracle, run the core tests with `HARMONY_METADATA_FIXTURE` pointing to a FLAC and `HARMONY_METADATA_EXPECTED` pointing to a JSON TrackMetadata document. The real-file test is skipped when these variables are absent.

## App icon

Harmony’s icon uses a single white musical note on an indigo-to-violet gradient. It has no headphones, decorative details, pre-rounded outer mask, or baked-in highlights. The native `HarmonyIcon.icon` source keeps the musical note in its own vector layer, with system material effects and automatic dark/tinted appearances. Xcode uses that source; Linux/xtool builds use the opaque flattened `AppIcon.png`.

Keep appearance overrides inside `fill-specializations`, including the default gradient as the entry with no `appearance` key. A top-level `fill` next to `fill-specializations` takes precedence and silently disables the dark and tinted variants. Clear and tinted renderings are otherwise derived by the system; the note carries an explicit tinted fill so it stays legible.

After editing the vector layers or background colors, regenerate the PNG fallback, matching asset-catalog image, and in-app brand mark:

```sh
python3 Scripts/RenderIcon.py
```

This requires FFmpeg built with its librsvg decoder. The renderer reads geometry and colors from the Icon Composer source so the native and flattened artwork stay consistent. On a Mac, `bash Scripts/RenderIconPreviews.sh` checks the actual native default, dark, clear, and tinted renderings. Native appearance previews cannot be verified by the Linux build.

Design references: [Apple’s app icon guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons/) and [Icon Composer](https://developer.apple.com/icon-composer/).
