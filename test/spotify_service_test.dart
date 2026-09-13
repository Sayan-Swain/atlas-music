import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/services/spotify_service.dart';

void main() {
  group('parsePlaylistId', () {
    test('open.spotify.com link with query', () {
      expect(
          SpotifyService.parsePlaylistId(
              'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123'),
          '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('spotify URI', () {
      expect(
          SpotifyService.parsePlaylistId(
              'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
          '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('bare ID', () {
      expect(SpotifyService.parsePlaylistId('37i9dQZF1DXcBWIGoYBM5M'),
          '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('garbage throws', () {
      expect(() => SpotifyService.parsePlaylistId('not a link!!'),
          throwsException);
    });
  });

  group('parseTrackList', () {
    test('dash lines split title/artist', () {
      final out = SpotifyService.parseTrackList(
          'Blinding Lights - The Weeknd\nLevitating - Dua Lipa');
      expect(out.map((s) => s.title), ['Blinding Lights', 'Levitating']);
      expect(out.map((s) => s.artist), ['The Weeknd', 'Dua Lipa']);
    });

    test('spotify desktop block keeps title + artist', () {
      final out = SpotifyService.parseTrackList(
          'Kesariya\nArijit Singh\nBrahmastra\n4:28\nPasoori\n');
      expect(out.first.title, 'Kesariya');
      expect(out.first.artist, 'Arijit Singh');
      expect(out.map((s) => s.title), contains('Pasoori'));
    });

    test('dedupes + drops empties, empty text throws nothing', () {
      final out = SpotifyService.parseTrackList(
          'Same - Artist\nSame - Artist\n\n');
      expect(out, hasLength(1));
      expect(SpotifyService.parseTrackList('   \n  '), isEmpty);
    });
  });

  group('friendlyError', () {
    test('403 guides to public playlist + quota mode', () {
      final m = SpotifyService.friendlyError(403);
      expect(m, contains('PUBLIC'));
      expect(m, contains('Quota'));
    });

    test('404 means bad link', () {
      expect(SpotifyService.friendlyError(404), contains('not found'));
    });
  });
}
