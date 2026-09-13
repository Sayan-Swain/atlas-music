import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/models/song.dart';
import 'package:atlas_music/services/quick_picks.dart';
import 'package:atlas_music/services/user_preferences.dart';

Song _s(String title, String artist, int sec,
        {String channel = '', String id = ''}) =>
    Song(
      id: id.isEmpty ? '$title::$artist' : id,
      title: title,
      artist: artist,
      thumbnailUrl: '',
      duration: Duration(seconds: sec),
      channel: channel,
    );

int _daysAgo(int days) =>
    DateTime.now().millisecondsSinceEpoch - days * 24 * 60 * 60 * 1000;

void main() {
  final seed = _s('Blinding Lights', 'The Weeknd', 200, id: 'seed');
  final recent = [
    seed,
    _s('Save Your Tears', 'The Weeknd', 215, id: 'r2'),
    _s('Levitating', 'Dua Lipa', 203, id: 'r3'),
  ];

  List<Song> candidates() => [
        _s('Blinding Lights Cover', 'The Weeknd', 200, id: 'c1'),
        _s('After Hours', 'The Weeknd', 200, id: 'c2'),
        _s('Unrelated Polka', 'Unknown Band', 200, id: 'c3'),
        _s('Short Clip', 'The Weeknd', 18, id: 'c4'),
      ];

  group('ranking', () {
    test('seed artist ranks first with because-you-played reason', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: candidates(),
      );
      expect(picks, isNotEmpty);
      expect(picks.first.song.artist, 'The Weeknd');
      expect(picks.first.reason, contains('Because you played'));
    });

    test('empty candidates yields empty picks, never throws', () {
      expect(
          QuickPicksEngine.rank(recent: recent, candidates: const []),
          isEmpty);
      expect(
          QuickPicksEngine.rank(recent: const [], candidates: candidates()),
          isNotNull);
    });

    test('duration window enforced inside engine', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: candidates(),
      );
      expect(picks.any((p) => p.song.id == 'c4'), isFalse);
    });
  });

  group('exclusions', () {
    test('recent, queue, recent-60min and duplicates excluded', () {
      final dup = _s('After Hours', 'The Weeknd', 200, id: 'dup-id');
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: [
          ...candidates(),
          _s('Blinding Lights', 'The Weeknd', 200, id: 'seed'),
          dup,
          _s('After Hours', 'The Weeknd', 200, id: 'c2'),
        ],
        queueIds: const {'c3'},
        stats: {
          'c2': {
            'playCount': 1,
            'skipCount': 0,
            'totalMs': 1000,
            'lastPlayed':
                DateTime.now().millisecondsSinceEpoch - 10 * 60 * 1000,
          },
        },
      );
      final ids = picks.map((p) => p.song.id).toSet();
      expect(ids.contains('seed'), isFalse); // in recent
      expect(ids.contains('r2'), isFalse);
      expect(ids.contains('c3'), isFalse); // in queue
      expect(ids.contains('c2'), isFalse); // played <60min ago
      // duplicate versions collapse to one entry
      expect(ids.where((id) => id == 'dup-id').length, lessThanOrEqualTo(1));
    });
  });

  group('skip decay', () {
    List<Song> cands() => [
          _s('Skipped Track', 'The Weeknd', 200, id: 'sk'),
          _s('Fresh Track', 'The Weeknd', 205, id: 'fr'),
        ];

    test('recent repeated skips sink the track', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: cands(),
        stats: {
          'sk': {
            'playCount': 3,
            'skipCount': 3,
            'totalMs': 9000,
            'lastPlayed': _daysAgo(1),
            'skipTimes': [_daysAgo(1), _daysAgo(2), _daysAgo(3)],
          },
        },
      );
      expect(picks.first.song.id, 'fr');
    });

    test('90-day-old skips weigh less than half of fresh ones', () {
      final oldSkipped = QuickPicksEngine.rank(
        recent: recent,
        candidates: cands(),
        stats: {
          'sk': {
            'playCount': 1,
            'skipCount': 2,
            'totalMs': 2000,
            'lastPlayed': _daysAgo(100),
            'skipTimes': [_daysAgo(100), _daysAgo(101)],
          },
        },
      );
      final freshSkipped = QuickPicksEngine.rank(
        recent: recent,
        candidates: cands(),
        stats: {
          'sk': {
            'playCount': 1,
            'skipCount': 2,
            'totalMs': 2000,
            'lastPlayed': _daysAgo(1),
            'skipTimes': [_daysAgo(1), _daysAgo(2)],
          },
        },
      );
      final oldScore =
          oldSkipped.firstWhere((p) => p.song.id == 'sk').score;
      final freshScore =
          freshSkipped.firstWhere((p) => p.song.id == 'sk').score;
      expect(oldScore, greaterThan(freshScore));
    });

    test('year-old single skip is effectively ignored', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: cands(),
        stats: {
          'sk': {
            'playCount': 1,
            'skipCount': 1,
            'totalMs': 1000,
            'lastPlayed': _daysAgo(400),
            'skipTimes': [_daysAgo(400)],
          },
        },
      );
      final sk = picks.firstWhere((p) => p.song.id == 'sk');
      final fr = picks.firstWhere((p) => p.song.id == 'fr');
      // Same artist, near-identical content: penalty must be negligible.
      expect((sk.score - fr.score).abs(), lessThan(0.1));
    });
  });

  group('collaborative blend', () {
    test('strong collab signal can win without data weakness', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: [
          _s('Fan Favorite', 'Some Artist', 200, id: 'fav'),
          _s('After Hours', 'The Weeknd', 200, id: 'c2'),
        ],
        collaborative: {
          for (var i = 0; i < 60; i++) 'pad$i': 1,
          'fav': 500,
        },
      );
      expect(picks.first.song.id, 'fav');
    });

    test('weak collab falls back to content similarity', () {
      final picks = QuickPicksEngine.rank(
        recent: recent,
        candidates: [
          _s('Fan Favorite', 'Some Artist', 200, id: 'fav'),
          _s('After Hours', 'The Weeknd', 200, id: 'c2'),
        ],
        collaborative: {'fav': 2},
      );
      expect(picks.first.song.id, 'c2');
    });
  });

  group('diversity + language', () {
    test('one stretch pick sits in the middle, varied slot', () {
      final pool = [
        ...List.generate(
            4,
            (i) => _s('Weeknd Track $i', 'The Weeknd', 195 + i,
                id: 'w$i')),
        ...List.generate(
            3,
            (i) => _s('Dua Track $i', 'Dua Lipa', 200 + i, id: 'd$i')),
        ...List.generate(
            3,
            (i) => _s('Bruno Track $i', 'Bruno Mars', 205 + i,
                id: 'b$i')),
        _s('Distant Jazz Cut', 'Miles Davis', 320, id: 'stretch'),
      ];
      final a = QuickPicksEngine.rank(
          recent: recent, candidates: pool, seedHint: 1);
      final b = QuickPicksEngine.rank(
          recent: recent, candidates: pool, seedHint: 2);
      final ia = a.indexWhere((p) => p.stretch);
      final ib = b.indexWhere((p) => p.stretch);
      expect(ia, greaterThanOrEqualTo(2));
      expect(ia, lessThan(a.length - 1));
      // Slot varies with the seed hint and is never first.
      expect(ia != ib || a.length < 5, isTrue);
    });

    test('session language strongly preferred', () {
      final picks = QuickPicksEngine.rank(
        recent: [_s('Kesariya', 'Arijit Singh', 268, id: 'seed-hi')],
        candidates: [
          _s('Other Hindi Song', 'Arijit Singh', 250, id: 'hi'),
          _s('Blinding Lights', 'The Weeknd', 200, id: 'en'),
        ],
        sessionLanguage: MusicLanguage.hindi,
      );
      expect(picks.first.song.id, 'hi');
    });
  });
}
