# Atlas Music

**Ad-free YouTube music player with smart recommendations, synced lyrics, and polished glass UI.**

Atlas Music brings a modern, distraction-free listening experience to Android. iOS version is planned for a future release but is not ready yet. Stream YouTube audio without ads, discover music with session-driven Quick Picks, and enjoy synchronized lyrics with a beautiful glassmorphism design.

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-blue?style=for-the-badge)](https://github.com/Sayan-Swain/atlas-music)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/Sayan-Swain/atlas-music)

> Stream YouTube audio without ads, with session-driven Quick Picks, personalized recommendations, and synced lyrics.

## Overview

Atlas Music is an open-source music player built with Flutter. It uses `youtube_explode_dart` to search YouTube and stream the highest quality audio directly from YouTube CDN. The app focuses on personalization, fast UI, and a clean dark glass design.

Key highlights:
- Ad-free playback with automatic quality selection
- Smart recommendations based on listening history and onboarding preferences
- Synced lyrics via LRCLIB with fallback and duration verification
- Background playback with lock-screen controls
- Local playlists and YouTube playlist import
- Optional Spotify playlist import using user-provided credentials

## Table of Contents
- [Download](#download)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [License](#license)
- [Disclaimer](#disclaimer)

## Download

Get the Android APK here: https://atlas-music-free.netlify.app/

The APK is built in release mode with R8 obfuscation enabled. iOS build is not ready yet and will come in a later version. Currently not conforming for iOS.

## Features

- **Ad-free YouTube audio streaming** with highest quality selection automatically
- **Session-driven Quick Picks** tuned to listening history, top artists, and preferences
- **Recommended for You** based on onboarding choices, listening history, and session seed
- **Recently Played rail** with language-aware filtering
- **Home screen** with Quick Picks, Recommended, Playlists, and Recently Played sections
- **Search** songs/artists via YouTube with language filter and search history
- **Library** with Liked Songs, local playlists, YouTube playlist import by URL/ID, Spotify playlist import via user-provided credentials
- **Playlist management**: create, edit, delete local playlists
- **Full-screen player** with synced lyrics via LRCLIB, dynamic artwork palette, shuffle/repeat/queue controls
- **Persistent mini player** with controls in bottom navigation
- **Background playback** with foreground audio service and lock-screen controls
- **Wake lock support** for uninterrupted playback
- **Onboarding welcome flow** with name input and preferences selection
- **Preferences** for Music Language, Genres, and Artists to personalize recommendations
- **Profile screen** with name/avatar edit, stats, Spotify credentials management
- **Content filtering**: duration window, language match, and bad-phrase/word filtering
- **Dark glassmorphism UI** with liquid background and floating navigation

## Tech Stack

| Category | Tech |
|----------|------|
| Framework | Flutter |
| Audio | just_audio, audio_service, just_audio_background |
| YouTube | youtube_explode_dart |
| State | Provider |
| Storage | SharedPreferences, path_provider |
| Lyrics | LRCLIB via http |
| UI | palette_generator, cached_network_image, shimmer, google_fonts |
| Utilities | image_picker, wakelock_plus, uuid, intl |

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Android Studio
- Android SDK and physical device or emulator

iOS support is planned for a future release and is not currently conforming.

### Installation

```bash
# Clone the repository
git clone https://github.com/Sayan-Swain/atlas-music.git

# Navigate to project
cd atlas-music

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build APK

```bash
flutter build apk --release
```

The release APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

## Project Structure

```
lib/
├── main.dart
├── app.dart
├── build_info.dart
├── data/
├── media/
├── models/
│   ├── song.dart
│   └── playlist.dart
├── services/
│   ├── audio_service.dart
│   ├── youtube_service.dart
│   ├── storage_service.dart
│   ├── lyrics_service.dart
│   ├── playlist_parser.dart
│   ├── spotify_service.dart
│   ├── user_preferences.dart
│   ├── user_prefs.dart
│   ├── song_filter.dart
│   ├── quick_picks.dart
│   └── ...
├── screens/
│   ├── home_screen.dart
│   ├── search_screen.dart
│   ├── library_screen.dart
│   ├── liked_songs_screen.dart
│   ├── playlist_detail_screen.dart
│   ├── player_screen.dart
│   ├── profile_screen.dart
│   ├── welcome_flow.dart
│   ├── onboarding_screen.dart
│   └── onboarding_preferences.dart
├── theme/
├── widgets/
│   ├── mini_player.dart
│   ├── floating_glass_nav.dart
│   ├── liquid_background.dart
│   ├── artwork.dart
│   ├── lyrics_sheet.dart
│   └── ...
└── ...
```

## How It Works

1. **YouTube Integration:** Uses `youtube_explode_dart` to search videos and extract audio streams
2. **Ad-Free:** Plays audio directly from YouTube's CDN, bypassing ads
3. **Quality:** Automatically selects highest bitrate audio stream available
4. **Lyrics:** Fetches synced lyrics from LRCLIB with fallback chain and duration verification
5. **Recommendations:** Quick Picks engine ranks candidates from listening stats, top artists/genres, search history, and session seed
6. **Background Playback:** `audio_service` + `just_audio_background` keeps playback alive with lock-screen controls

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open Pull Request

Please follow Flutter/Dart style guide and add tests where applicable.

## License

MIT License - see [LICENSE](LICENSE) file

## Disclaimer

Atlas Music is an open-source project for educational and personal-use purposes. Atlas Music does not host or distribute the underlying media. YouTube content is accessed through third-party functionality, and users are responsible for complying with applicable laws and the terms of the services they use. YouTube's Terms of Service may restrict certain forms of automated access, extraction, or playback. The project is not affiliated with or endorsed by YouTube, Google, Spotify, or LRCLIB.
