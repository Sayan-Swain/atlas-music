# Atlas Music

Open-source music player with YouTube integration. Stream music ad-free with high quality audio.

## Download

Get the Android APK here: https://atlas-music-free.netlify.app/

## Features

- Stream music from YouTube without ads
- Auto-selects highest quality audio (up to 256kbps AAC)
- Create and manage playlists
- Import YouTube Music playlists via link
- Spotify playlist import (coming soon)
- Auto-play related music when queue ends
- Home screen with curated categories
- Search songs, artists, albums
- Like/favorite songs
- Recently played history
- Background playback
- Mini player with controls
- Beautiful dark theme UI

## Tech Stack

- **Framework:** Flutter (cross-platform iOS/Android)
- **Audio:** just_audio
- **YouTube:** youtube_explode_dart
- **State:** Provider
- **Storage:** SharedPreferences (local)

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Android Studio / Xcode

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

### Build iOS

```bash
flutter build ios --release
```

## Project Structure

```
lib/
├── main.dart              # Entry point
├── app.dart               # MaterialApp + navigation
├── models/
│   ├── song.dart          # Song data model
│   └── playlist.dart      # Playlist data model
├── services/
│   ├── youtube_service.dart    # YouTube API integration
│   ├── audio_service.dart      # Audio playback
│   └── storage_service.dart    # Local storage
├── screens/
│   ├── home_screen.dart        # Home with categories
│   ├── search_screen.dart      # Search functionality
│   ├── library_screen.dart     # User library
│   ├── player_screen.dart      # Full player
│   └── playlist_detail_screen.dart
└── widgets/
    ├── song_card.dart          # Song card for grid
    ├── song_tile.dart          # Song list item
    ├── playlist_tile.dart      # Playlist list item
    └── mini_player.dart        # Persistent mini player
```

## How It Works

1. **YouTube Integration:** Uses `youtube_explode_dart` to search videos and extract audio streams
2. **Ad-Free:** Plays audio directly from YouTube's CDN, bypassing ads
3. **Quality:** Automatically selects highest bitrate audio stream available
4. **Auto-Play:** When queue ends, fetches related videos and continues playing

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open Pull Request

## License

MIT License - see [LICENSE](LICENSE) file

## Disclaimer

This app is for educational purposes. YouTube's Terms of Service may restrict direct audio extraction. Use responsibly.
