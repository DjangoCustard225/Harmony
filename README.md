# Harmony

A local music player for iPhone and iPad, adapted from [Gevun](https://github.com/DjangoCustard225/Gevun).

- Import multiple audio files from Files, iCloud Drive, or another file provider.
- Keep local copies for offline listening, without an account or music server.
- Browse albums, artists, and songs; search titles, albums, and artists.
- Sort songs by title, artist, album, import date, or duration, in either direction. Song sorting is remembered between launches.
- View real artist portraits and biographies from Deezer, with TheAudioDB fallback. Loaded profiles and photos remain available offline.
- Read embedded titles, artists, album names, cover art, and lyrics, with filenames as a fallback.
- Enjoy Gevun’s artwork-based dark interface, mini player, full player, queue, shuffle, and repeat.
- Listen in the background with lock-screen controls.
- Share audio files or remove imported copies without changing the originals.

Requires iOS 27 or later. Playback uses the device’s native audio support, including MP3, AAC/M4A, ALAC, FLAC, WAV, and AIFF where supported. DRM-protected files are not supported.

Open Harmony and tap **Import music** in Settings. Selected files are copied into Harmony’s Documents/Music folder and indexed in a persistent local library. Files opened with Harmony are imported too. Cloud files must first be available from their provider; imported copies then play offline. Use **Refresh library** to index audio files already placed in Harmony’s Music folder.

The app reads embedded metadata, including native FLAC tags and PICTURE blocks, and the metadata exposed by AVFoundation for MP3/M4A and other playable formats. Existing imports are refreshed automatically after updating; use **Settings → Refresh metadata** to rescan manually. Files without tags appear under Unknown artist / Unknown album. Embedded track and disc numbers determine album ordering when available. Embedded plain lyrics and LRC timestamps are supported, including synced highlighting and seeking. Open a song’s menu → **Track info** for audio properties and all extracted text tags, such as composers, label, copyright, and identifiers. External lyrics lookup and server features are not included.

## Build

Open `Harmony.xcodeproj` in Xcode 27, choose your signing team, and run the Harmony scheme. Or build an unsigned IPA on macOS:

```sh
bash Scripts/BuildIPA.sh
```

Linux with xtool and an iOS 27 SDK:

```sh
xtool dev build -c release --triple arm64-apple-ios27.0 --ipa
```

The Linux output is `xtool/Harmony.ipa`. Sign the unsigned IPA with your sideloading tool before installing.

Core checks:

```sh
swift test --package-path Core
```

See [building instructions](docs/BUILDING.md). No ads, analytics, or credentials. Optional artist lookups send artist names to Deezer and TheAudioDB; audio files stay local. Disable lookups in Settings. Licensed under the [MIT License](LICENSE); original Gevun attribution is retained.

## Artist information sources

[Deezer](https://www.deezer.com/) is the primary source for artist photos and biographies. Harmony uses its public artist search and anonymous biography endpoint, following the approach used by [Navidrome](https://www.navidrome.org/docs/usage/external-integrations/). No user account or developer key is required. Exact artist-name matches are ranked by popularity to distinguish namesakes; when data is missing or the service is unavailable, Harmony tries TheAudioDB for the missing fields.

[TheAudioDB](https://www.theaudiodb.com/free_music_api) supplies fallback artist photos and biographies through its documented free development API. It permits up to 30 requests per minute; Harmony paces requests and caches responses. Its [terms](https://www.theaudiodb.com/docs_terms_of_use.php) require a paid subscription for App Store publication. This sideloaded development build uses the public key.

Artist pages show a two-line biography preview; tap it to open the complete biography in a native sheet. Sources are recorded with cached profiles, with attribution documented here rather than displayed in Settings. Provider responses can have gaps; Harmony uses a person placeholder when no matching artist photo is available. Music import, tags, lyrics, and playback continue to work offline.
