import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/models/song.dart';
import 'package:atlas_music/screens/home_screen.dart';

Song _s(String title, String artist, int sec, [String channel = '']) => Song(
      id: '$title$artist',
      title: title,
      artist: artist,
      thumbnailUrl: '',
      duration: Duration(seconds: sec),
      channel: channel,
    );

void main() {
  test('drops clips, unknown lengths, and movies (>10 min)', () {
    final out = filterRecommendedSongs([
      _s('Short Clip', 'A', 18),
      _s('Mystery Stream', 'A', 0),
      _s('Movie Scene', 'A', 720),
      _s('Full Song', 'A', 210),
    ]);
    expect(out.map((s) => s.title), ['Full Song']);
  });

  test('popular filter drops clips and movies, keeps browse tracks', () {
    final out = filterPopularSongs([
      _s('Short TikTok', 'A', 25),
      _s('Movie Soundtrack', 'A', 900),
      _s('Normal Song', 'A', 200),
      _s('Unknown Length', 'A', 0),
    ]);
    expect(out.map((s) => s.title), ['Normal Song']);
  });

  test('drops remix/edit/slowed/reverb variants', () {
    final out = filterRecommendedSongs([
      _s('Kesariya (Slowed + Reverb)', 'Arijit Singh', 200),
      _s('Kesariya - DJ Edit', 'Arijit Singh', 200),
      _s('Kesariya Remix', 'DJ X', 200),
      _s('Kesariya', 'Arijit Singh', 268),
    ]);
    expect(out.length, 1);
    expect(out.single.title, 'Kesariya');
  });

  test('word boundary: credit survives edit rule', () {
    final out = filterRecommendedSongs([
      _s('Credit Song', 'Accredited Band', 200),
    ]);
    expect(out.length, 1);
  });

  test('canonical artist gate kills loose-search mismatch', () {
    final out = filterRecommendedSongs(
      [
        _s('Kesariya', 'Arijit Singh', 268),
        _s('Random Song', 'Unknown Band', 200),
      ],
      canonicalArtist: 'Arijit Singh',
    );
    expect(out.map((s) => s.title), ['Kesariya']);
  });

  test('alien uploader channel rejected, official allowed', () {
    final songs = [
      _s('Kesariya', 'Arijit Singh', 268, 'coyote clipz'),
      _s('Kesariya', 'Arijit Singh', 268, 'Arijit Singh'),
      _s('Kesariya', 'Arijit Singh', 268, 'SonyMusicIndiaVEVO'),
      _s('Kesariya', 'Arijit Singh', 268, 'Arijit Singh - Topic'),
      _s('Kesariya', 'Arijit Singh', 268, ''),
    ];
    final out = filterRecommendedSongs(songs,
        canonicalArtist: 'Arijit Singh');
    expect(out.map((s) => s.channel), [
      'Arijit Singh',
      'SonyMusicIndiaVEVO',
      'Arijit Singh - Topic',
      '',
    ]);
  });
}
