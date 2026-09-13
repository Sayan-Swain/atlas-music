import '../models/song.dart';
import '../models/playlist.dart';

/// Offline-safe placeholder catalogue. Home always renders instantly;
/// live YouTube results replace these sections when network returns.
class DemoLibrary {
  static List<Song> _songs(String seed, List<String> titles, String artist) {
    return List.generate(titles.length, (i) {
      return Song(
        id: 'demo-$seed-$i',
        title: titles[i],
        artist: artist,
        thumbnailUrl: 'https://picsum.photos/seed/$seed$i/300/300',
        duration: Duration(minutes: 3, seconds: 12 + i * 7),
      );
    });
  }

  static List<Song> get popular => _songs('pop', const [
        'Midnight Glass',
        'Ultraviolet',
        'Teal Horizon',
        'Neon Tide',
        'Silent Orbit',
        'Velvet Pulse',
        'Echo Bloom',
        'Night Circuit',
      ], 'Various Artists');

  static List<Song> get recommended => _songs('rec', const [
        'Liquid Dreams',
        'Obsidian Sky',
        'Soft Static',
        'Aurora Drift',
        'Deep Field',
        'Glasshouse',
        'Slow Current',
        'Morning Haze',
      ], 'Curated Mix');

  static List<Song> get recent => _songs('recent', const [
        'Afterglow',
        'Low Light',
        'Frosted',
        'Half Moon',
        'Paper Waves',
        'Still Air',
      ], 'You');

  static List<Playlist> get playlists => List.generate(4, (i) {
        final songs = popular.sublist(i, i + 4);
        return Playlist(
          id: 'demo-pl-$i',
          name: ['Night Drive', 'Focus Flow', 'Chill Evenings', 'Workout Surge'][i],
          description: 'Made for you',
          thumbnailUrl: 'https://picsum.photos/seed/pl$i/300/300',
          songs: songs,
          createdAt: DateTime.now(),
          source: 'local',
        );
      });

  static Song get featured => Song(
        id: 'demo-featured',
        title: 'Midnight Glass',
        artist: 'Ultraviolet Ensemble',
        thumbnailUrl: 'https://picsum.photos/seed/featured9/600/600',
        duration: const Duration(minutes: 4, seconds: 5),
      );
}
