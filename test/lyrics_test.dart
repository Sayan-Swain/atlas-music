import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:atlas_music/media/lyrics_model.dart';
import 'package:atlas_music/models/song.dart';
import 'package:atlas_music/services/lyrics_service.dart';

Song _song({String title = 'Blinding Lights', String artist = 'The Weeknd', int sec = 200}) {
  return Song(
    id: 'x',
    title: title,
    artist: artist,
    thumbnailUrl: '',
    duration: Duration(seconds: sec),
  );
}

LyricsService _svc(MockClient mock) => LyricsService(
      client: mock,
      dir: Directory.systemTemp.createTempSync('lyrtest_'),
    );

void main() {
  group('parseLrc', () {
    test('parses basic lines with centiseconds', () {
      final lines = parseLrc('[00:12.34] Hello\n[00:15.00] World');
      expect(lines.length, 2);
      expect(lines[0].text, 'Hello');
      expect(lines[0].start, const Duration(milliseconds: 12340));
      expect(lines[1].start, const Duration(seconds: 15));
    });

    test('expands multiple timestamps on one line', () {
      final lines = parseLrc('[00:10.00][00:20.00] Chorus');
      expect(lines.length, 2);
      expect(lines[0].start, const Duration(seconds: 10));
      expect(lines[1].start, const Duration(seconds: 20));
    });

    test('sorts unsorted input', () {
      final lines = parseLrc('[00:20.00] B\n[00:10.00] A');
      expect(lines[0].text, 'A');
      expect(lines[1].text, 'B');
    });

    test('ignores metadata and empty bodies', () {
      final lines = parseLrc('[ti:Title]\n[ar:Artist]\n[00:10.00]\n[00:12.00] Real');
      expect(lines.length, 1);
      expect(lines[0].text, 'Real');
    });
  });

  group('indexFor', () {
    test('picks last line at or before position', () {
      const l = SyncedLyrics(
        track: 't',
        artist: 'a',
        lines: [
          LyricLine(start: Duration(seconds: 0), text: 'a'),
          LyricLine(start: Duration(seconds: 10), text: 'b'),
          LyricLine(start: Duration(seconds: 20), text: 'c'),
        ],
        isSynced: true,
      );
      expect(l.indexFor(const Duration(seconds: 0)), 0);
      expect(l.indexFor(const Duration(seconds: 15)), 1);
      expect(l.indexFor(const Duration(seconds: 99)), 2);
    });
  });

  group('cleaning', () {
    test('cleanTrack strips video junk and dash suffix', () {
      expect(
        LyricsService.cleanTrack('Blinding Lights (Official Video)'),
        'Blinding Lights',
      );
      expect(
        LyricsService.cleanTrack('Blinding Lights - Lyrics'),
        'Blinding Lights',
      );
      expect(
        LyricsService.cleanTrack('Duniyaa [From Luka Chuppi]'),
        'Duniyaa',
      );
    });

    test('cleanArtist keeps first artist and drops Topic', () {
      expect(
        LyricsService.cleanArtist('The Weeknd, Daft Punk'),
        'The Weeknd',
      );
      expect(
        LyricsService.cleanArtist('Alan Walker - Topic'),
        'Alan Walker',
      );
    });

    test('trackVariants keeps last segment of Artist - Title', () {
      final v = LyricsService.trackVariants(
          'Arijit Singh - Kesariya (Official Video)');
      expect(v.first, 'Arijit Singh');
      expect(v, contains('Kesariya'));
    });

    test('trackVariants keeps first segment of Title | junk', () {
      final v = LyricsService.trackVariants(
          'Kesariya | Brahmastra | Arijit Singh');
      expect(v.first, 'Kesariya');
    });

    test('trackVariants drops junk last segments', () {
      final v =
          LyricsService.trackVariants('Kesariya (Official Video) - Live');
      expect(v, isNot(contains('Live')));
      expect(v, contains('Kesariya'));
    });

    test('trackVariants leaves plain titles alone', () {
      expect(
        LyricsService.trackVariants('Blinding Lights'),
        ['Blinding Lights'],
      );
    });
  });

  group('LyricsService.fetch', () {
    test('returns synced lyrics from /api/get', () async {
      final mock = MockClient((http.BaseRequest req) async {
        expect(req.url.path, '/api/get');
        return http.Response(
          json.encode({
            'trackName': 'Blinding Lights',
            'artistName': 'The Weeknd',
            'syncedLyrics': '[00:10.00] Hello\n[00:15.00] World',
            'plainLyrics': 'Hello\nWorld',
            'instrumental': false,
          }),
          200,
        );
      });
      final svc = _svc(mock);
      final out = await svc.fetch(_song());
      expect(out, isNotNull);
      expect(out!.isSynced, true);
      expect(out.lines.length, 2);
      expect(out.lines[0].text, 'Hello');
    });

    test('falls back to search when get 404s', () async {
      final paths = <String>[];
      final mock = MockClient((http.BaseRequest req) async {
        paths.add('${req.method} ${req.url.path}');
        if (req.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        // search: assert correct q= param is used, not track_name/artist_name
        expect(req.url.queryParameters, containsPair('q', 'Blinding Lights The Weeknd'));
        return http.Response(
          json.encode([
            {
              'trackName': 'Blinding Lights',
              'artistName': 'The Weeknd',
              'syncedLyrics': '[00:05.00] Yo',
              'plainLyrics': 'Yo',
              'instrumental': false,
            }
          ]),
          200,
        );
      });
      final svc = _svc(mock);
      final out = await svc.fetch(_song());
      expect(out, isNotNull);
      expect(out!.lines.single.text, 'Yo');
      // exact gets (dur + no-dur + title-only) + raw skipped + search
      expect(paths.where((p) => p == 'GET /api/get').length, greaterThanOrEqualTo(3));
      expect(paths.where((p) => p == 'GET /api/search').length, 1);
    });

    test('title-only get is tried when artist drifts on LRCLIB', () async {
      // artist_name missing on first two /api/get calls → null, then a
      // title-only /api/get (no artist_name) succeeds.
      int getCalls = 0;
      final mock = MockClient((http.BaseRequest req) async {
        if (req.url.path == '/api/get') {
          getCalls++;
          if (req.url.queryParameters.containsKey('artist_name')) {
            return http.Response('not found', 404);
          }
          return http.Response(
            json.encode({
              'trackName': 'Deva Deva',
              'artistName': 'Pritam',
              'syncedLyrics': '[00:10.00] Om\n[00:20.00] Shanti',
              'plainLyrics': 'Om\nShanti',
              'instrumental': false,
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      final svc = _svc(mock);
      final out = await svc.fetch(_song(title: 'Deva Deva', artist: 'Arijit Singh'));
      expect(out, isNotNull);
      expect(out!.lines.length, 2);
      expect(getCalls, greaterThanOrEqualTo(3));
    });

    test('returns null when nothing found', () async {
      final mock = MockClient((_) async => http.Response('no', 404));
      final svc = _svc(mock);
      // duration 0 skips first get, second get 404, search 404 -> null
      expect(await svc.fetch(_song(sec: 0)), isNull);
    });

    test('marks instrumental', () async {      final mock = MockClient((_) async => http.Response(
            json.encode({
              'trackName': 'Intro',
              'artistName': 'X',
              'instrumental': true,
            }),
            200,
          ));
      final svc = _svc(mock);
      final out = await svc.fetch(_song(title: 'Intro', artist: 'X'));
      expect(out, isNotNull);
      expect(out!.instrumental, true);
    });

    test('Artist - Title finds lyrics via last-segment variant', () async {
      // Regression: cleanTrack("Arijit Singh - Kesariya") kept the
      // artist half as the title, so every /api/get 404d and search
      // returned the wrong song. Last segment must be tried.
      final mock = MockClient((http.BaseRequest req) async {
        if (req.url.path == '/api/get') {
          final t = req.url.queryParameters['track_name'] ?? '';
          final a = req.url.queryParameters['artist_name'] ?? '';
          if (t == 'Kesariya' && a == 'Arijit Singh') {
            return http.Response(
              json.encode({
                'trackName': 'Kesariya',
                'artistName': 'Arijit Singh',
                'syncedLyrics': '[00:10.00] Hi',
                'plainLyrics': 'Hi',
                'instrumental': false,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }
        return http.Response('[]', 200);
      });
      final svc = _svc(mock);
      final out = await svc.fetch(_song(
        title: 'Arijit Singh - Kesariya (Official Video)',
        artist: 'Arijit Singh',
        sec: 268,
      ));
      expect(out, isNotNull);
      expect(out!.isSynced, true);
      expect(out.lines.single.text, 'Hi');
    });

    test('title-only get rejects duration contradiction', () async {
      // Same title, artist drift, but LRCLIB duration is minutes off:
      // must be a different track, not our lyrics.
      final mock = MockClient((http.BaseRequest req) async {
        if (req.url.path == '/api/get') {
          if (req.url.queryParameters.containsKey('artist_name')) {
            return http.Response('not found', 404);
          }
          return http.Response(
            json.encode({
              'trackName': 'Deva Deva',
              'artistName': 'Some Other Artist',
              'duration': 90,
              'syncedLyrics': '[00:10.00] Wrong\n[00:20.00] Text',
              'plainLyrics': 'Wrong\nText',
              'instrumental': false,
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      final svc = _svc(mock);
      expect(
          await svc.fetch(
              _song(title: 'Deva Deva', artist: 'Arijit Singh', sec: 268)),
          isNull);
    });

    test('search skips duration-clashing title picks', () async {
      final mock = MockClient((http.BaseRequest req) async {
        if (req.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        return http.Response(
          json.encode([
            {
              // Same title, channel-style artist, far-off duration.
              'trackName': 'Blinding Lights',
              'artistName': 'Random Uploads',
              'duration': 37,
              'syncedLyrics': '[00:05.00] Wrong',
              'plainLyrics': 'Wrong',
              'instrumental': false,
            },
            {
              // Same title, right artist and matching duration.
              'trackName': 'Blinding Lights',
              'artistName': 'The Weeknd',
              'duration': 202,
              'syncedLyrics': '[00:05.00] Right',
              'plainLyrics': 'Right',
              'instrumental': false,
            }
          ]),
          200,
        );
      });
      final svc = _svc(mock);
      final out = await svc.fetch(_song(sec: 200));
      expect(out, isNotNull);
      expect(out!.lines.single.text, 'Right');
    });

    test('search rejects same-artist wrong-track hits', () async {
      final mock = MockClient((http.BaseRequest req) async {
        if (req.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        return http.Response(
          json.encode([
            {
              'trackName': 'Totally Different Song',
              'artistName': 'The Weeknd',
              'syncedLyrics': '[00:05.00] Wrong',
              'plainLyrics': 'Wrong',
              'instrumental': false,
            }
          ]),
          200,
        );
      });
      final svc = _svc(mock);
      expect(await svc.fetch(_song()), isNull);
    });
  });
}
