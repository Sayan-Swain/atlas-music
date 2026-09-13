import '../models/song.dart';
import 'song_filter.dart';
import 'user_preferences.dart';

/// Personalized Quick Picks ranking — pure logic, no plugins, unit-tested.
///
/// What the engine can actually see on this device (no audio-feature API,
/// no backend): YouTube titles/artists/channels/durations, listening
/// stats (plays, skips + skip timestamps, recency), top artists/genres,
/// likes, recent tracks, and the player queue. There is deliberately NO
/// BPM/key/energy/valence input — nothing on device provides per-track
/// audio features. Content similarity is approximated from artist, title,
/// channel, duration proximity, genre anchors, and language; key
/// compatibility is skipped rather than faked. Rankings state this openly
/// instead of pretending to hear the audio.
///
/// Collaborative input is a supported parameter (`collaborative`: plays
/// immediately after the seed → count) but this install has no user
/// network, so it defaults to empty and the blend falls back to
/// content-first per spec (60/40 with data, 20/80 without).
class QuickPick {
  final Song song;
  final double score;
  final String reason;
  final bool stretch;
  const QuickPick({
    required this.song,
    required this.score,
    required this.reason,
    this.stretch = false,
  });
}

class QuickPicksEngine {
  /// Session profile weights for the last ≤5 tracks, most-recent-first.
  /// Seed (latest) dominates at ~50%; session outweighs long-term taste.
  static const List<double> sessionWeights = [0.5, 0.2, 0.125, 0.1, 0.075];

  static const int maxPerArtist = 2;
  static const int recentMinutesExclusion = 60;
  static const int sessionMinutes = 30;

  /// Rank [candidates] for the session led by [recent] (most-recent-first,
  /// [recent.first] is the seed). Returns at most [count] picks, strongest
  /// first with one stretch pick woven into the middle. Never throws.
  static List<QuickPick> rank({
    required List<Song> recent,
    required List<Song> candidates,
    Map<String, Map<String, dynamic>> stats = const {},
    List<String> topArtists = const [],
    List<String> topGenres = const [],
    Set<String> likedIds = const {},
    Set<String> queueIds = const {},
    MusicLanguage userLanguage = MusicLanguage.all,
    MusicLanguage? sessionLanguage,
    Map<String, int> collaborative = const {},
    List<String> searchHistory = const [],
    List<String> selectedArtists = const [],
    int count = 10,
    int seedHint = 0,
  }) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final session = recent.take(5).toList();
      final seed = session.isNotEmpty ? session.first : null;

      final recentIds = session.map((s) => s.id).toSet();
      final weights = <String, double>{};
      for (var i = 0; i < session.length; i++) {
        weights[session[i].id] =
            (weights[session[i].id] ?? 0) + sessionWeights[i];
      }

      // Session artist/title/channel token pools, weight-blended.
      final artistPool = <String, double>{};
      final titlePool = <String, double>{};
      final channelPool = <String>{};
      for (var i = 0; i < session.length; i++) {
        final w = sessionWeights[i];
        for (final t in _tokens(session[i].artist)) {
          artistPool[t] = (artistPool[t] ?? 0) + w;
        }
        for (final t in _tokens(session[i].title)) {
          titlePool[t] = (titlePool[t] ?? 0) + w;
        }
        channelPool.addAll(_tokens(session[i].channel));
      }

      final sessionLang =
          sessionLanguage ?? (seed == null ? null : SongFilter.detectLanguage(seed));
      final seedDur = seed?.duration.inSeconds ?? 0;

      // Collaborative normalization: popular tracks must not dominate.
      var collabMax = 0;
      for (final v in collaborative.values) {
        if (v > collabMax) collabMax = v;
      }
      final collabUseful =
          collaborative.values.where((v) => v > 0).length >= 50;
      final wCollab = collabUseful ? 0.6 : 0.2;
      final wContent = collabUseful ? 0.4 : 0.8;

      final seenVideo = <String>{};
      final seenTrack = <String>{};
      final scored = <_Scored>[];
      for (final c in candidates) {
        final vid = c.videoId ?? c.id;
        if (!seenVideo.add(vid)) continue; // duplicate uploads
        final sig =
            '${_normTitle(c.title)}|${_normTitle(c.artist)}';
        if (!seenTrack.add(sig)) continue; // duplicate versions
        if (recentIds.contains(c.id)) continue; // already in session
        if (queueIds.contains(c.id) || queueIds.contains(vid)) continue;
        // GLOBAL rules hold inside the engine too, never just upstream.
        if (!SongFilter.inDurationWindow(c)) continue;
        if (!SongFilter.matchesLanguage(c, userLanguage)) continue;

        final st = stats[c.id];
        if (st != null) {
          final last = (st['lastPlayed'] as int?) ?? 0;
          if (last > 0 &&
              now - last <
                  recentMinutesExclusion * 60 * 1000) {
            continue; // played within the last 60 minutes
          }
        }

        final content = _contentScore(
          c,
          artistPool: artistPool,
          titlePool: titlePool,
          channelPool: channelPool,
          sessionLang: sessionLang,
          seedDur: seedDur,
        );
        var collab = 0.0;
        if (collabMax > 0) {
          collab = ((collaborative[c.id] ?? 0) / collabMax).clamp(0.0, 1.0);
        }
        var score = wCollab * collab + wContent * content;

        // Long-term taste + behavior: small capped boosts, never
        // override session. Meaningful listens (high totalMs vs duration),
        // replays, likes, selected prefs, and search history all count.
        var boost = 0.0;
        if (_artistInList(c.artist, topArtists)) boost += 0.06;
        if (_artistInList(c.artist, selectedArtists)) boost += 0.05;
        if (_genreHit(c, topGenres)) boost += 0.04;
        if (likedIds.contains(c.id)) boost += 0.05; // saved
        final plays = (st?['playCount'] as int?) ?? 0;
        final totalMs = (st?['totalMs'] as int?) ?? 0;
        final durMs = c.duration.inMilliseconds;
        // Replayed AND actually listened (not replayed-and-skipped).
        if (plays >= 3 && durMs > 0 && totalMs >= durMs) {
          boost += 0.05; // replayed often
        }
        if (totalMs > 0 && durMs > 0) {
          // Listened well past one full play-through: genuine favorite.
          final ratio = totalMs / durMs;
          if (ratio >= 2.0) {
            boost += 0.06;
          } else if (ratio >= 1.0) {
            boost += 0.03;
          }
        }
        boost += _searchBoost(c, searchHistory);
        score = (score + boost).clamp(0.0, 1.0);

        // Session feedback: time-decayed skip penalty. Recent repeated
        // skips bite; >90d less than half; >1yr effectively ignored.
        // One skip never blacklists (capped well below top scores).
        score = (score - _skipPenalty(st)).clamp(0.0, 1.0);

        scored.add(_Scored(c, score, content));
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      if (scored.isEmpty) return const [];

      // Diversity: cap repeats per artist, then weave one stretch pick
      // (lower similarity, same language family) into the middle at a
      // slot that varies with the seed — never first, never fixed.
      final perArtist = <String, int>{};
      final main = <_Scored>[];
      final spare = <_Scored>[];
      for (final s in scored) {
        final key = s.song.artist.toLowerCase().trim();
        final n = perArtist[key] ?? 0;
        if (n < maxPerArtist && main.length < count) {
          perArtist[key] = n + 1;
          main.add(s);
        } else {
          spare.add(s);
        }
        if (main.length >= count && spare.length >= 4) break;
      }
      _Scored? stretchObj;
      if (main.length > 3 && spare.isNotEmpty) {
        final median = main[main.length ~/ 2].content;
        for (final s in spare) {
          if (s.content < median &&
              s.song.artist.toLowerCase().trim() !=
                  main.first.song.artist.toLowerCase().trim()) {
            stretchObj = s;
            break;
          }
        }
        stretchObj ??= spare.first;
        final slot =
            (2 + (seedHint.abs() % 2)).clamp(2, main.length - 1);
        main.insert(slot, stretchObj);
      }
      final picks = main.take(count).toList();

      return picks
          .map((s) => QuickPick(
                song: s.song,
                score: s.score,
                reason: _reasonFor(
                  s.song,
                  seed: seed,
                  session: session,
                  topArtists: topArtists,
                  stretch: identical(s, stretchObj),
                ),
                stretch: identical(s, stretchObj),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static double _contentScore(
    Song c, {
    required Map<String, double> artistPool,
    required Map<String, double> titlePool,
    required Set<String> channelPool,
    required MusicLanguage? sessionLang,
    required int seedDur,
  }) {
    final aToks = _tokens(c.artist);
    var artist = 0.0;
    if (aToks.isNotEmpty) {
      var hit = 0.0;
      for (final t in aToks) {
        hit += artistPool[t] ?? 0;
      }
      artist = (hit / aToks.length).clamp(0.0, 1.0);
    }
    final tToks = _tokens(c.title);
    var title = 0.0;
    if (tToks.isNotEmpty) {
      var hit = 0.0;
      for (final t in tToks) {
        hit += titlePool[t] ?? 0;
      }
      title = (hit / tToks.length).clamp(0.0, 1.0);
    }
    var channel = 0.0;
    for (final t in _tokens(c.channel)) {
      if (channelPool.contains(t)) {
        channel = 1.0;
        break;
      }
    }
    var duration = 0.0;
    if (seedDur > 0 && c.duration.inSeconds > 0) {
      duration = (1 -
              (c.duration.inSeconds - seedDur).abs() / 120)
          .clamp(0.0, 1.0);
    }
    var language = 1.0;
    if (sessionLang != null && sessionLang != MusicLanguage.all) {
      final candLang = SongFilter.detectLanguage(c);
      language = (candLang == null || candLang == sessionLang) ? 1.0 : 0.2;
    }
    return 0.38 * artist +
        0.22 * title +
        0.10 * channel +
        0.10 * duration +
        0.20 * language;
  }

  static double _skipPenalty(Map<String, dynamic>? st) {
    if (st == null) return 0.0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 24 * 60 * 60 * 1000;
    double decayed = 0;
    final times = (st['skipTimes'] as List?)?.whereType<int>().toList();
    if (times != null && times.isNotEmpty) {
      for (final t in times) {
        final age = now - t;
        if (age < 7 * day) {
          decayed += 1.0;
        } else if (age < 30 * day) {
          decayed += 0.7;
        } else if (age < 90 * day) {
          decayed += 0.5;
        } else if (age < 365 * day) {
          decayed += 0.25;
        } else {
          decayed += 0.05;
        }
      }
    } else {
      // Legacy entries predate timestamps: treat as old data.
      decayed = ((st['skipCount'] as int?) ?? 0) * 0.3;
    }
    var penalty = (0.25 * decayed).clamp(0.0, 0.6);
    // Repeatedly skipped lately (3+ skips, latest within a week): sink
    // hard so it stops resurfacing, but never a full blacklist — the
    // track stays listed in case taste changes.
    final skipCount = (st['skipCount'] as int?) ?? times?.length ?? 0;
    if (skipCount >= 3 && times != null && times.isNotEmpty) {
      final latest = times.reduce((a, b) => a > b ? a : b);
      if (now - latest < 7 * day) penalty = (penalty + 0.25).clamp(0.0, 0.8);
    }
    // Consistently abandoned with barely any real listening: extra dip.
    final totalMs = (st['totalMs'] as int?) ?? 0;
    final plays = (st['playCount'] as int?) ?? 0;
    if (skipCount >= 2 && plays > 0 && totalMs < plays * 30000) {
      penalty = (penalty + 0.1).clamp(0.0, 0.8);
    }
    return penalty;
  }

  /// Recent search terms overlapping title/artist: user is actively
  /// looking for this. Capped so it informs, never dominates session.
  static double _searchBoost(Song c, List<String> searchHistory) {
    if (searchHistory.isEmpty) return 0.0;
    final hay = '${c.title} ${c.artist}'.toLowerCase();
    var hits = 0;
    for (final q in searchHistory.take(10)) {
      for (final tok in q
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.length > 2)) {
        if (RegExp('\\b${RegExp.escape(tok)}\\b').hasMatch(hay)) {
          hits++;
          break;
        }
      }
      if (hits >= 2) break;
    }
    if (hits >= 2) return 0.05;
    if (hits == 1) return 0.03;
    return 0.0;
  }

  static bool _artistInList(String artist, List<String> list) {
    final a = artist.toLowerCase().trim();
    if (a.isEmpty) return false;
    for (final e in list) {
      final t = e.toLowerCase().trim();
      if (t.isEmpty) continue;
      if (a.contains(t) || t.contains(a)) return true;
    }
    return false;
  }

  static bool _genreHit(Song c, List<String> genres) {
    if (genres.isEmpty) return false;
    final hay = '${c.title} ${c.artist}'.toLowerCase();
    for (final g in genres) {
      for (final tok in g
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.length > 2)) {
        if (RegExp('\\b${RegExp.escape(tok)}\\b').hasMatch(hay)) {
          return true;
        }
      }
    }
    return false;
  }

  static String _reasonFor(
    Song c, {
    required Song? seed,
    required List<Song> session,
    required List<String> topArtists,
    required bool stretch,
  }) {
    if (stretch) return 'Picked for you';
    if (seed != null) {
      final seedArtists = _tokens(seed.artist);
      if (seedArtists.isNotEmpty &&
          _tokens(c.artist).any(seedArtists.contains)) {
        return 'Because you played ${seed.title}';
      }
    }
    for (final s in session.skip(1)) {
      if (_tokens(s.artist).any(_tokens(c.artist).contains)) {
        return 'Similar to your recent music';
      }
    }
    if (_artistInList(c.artist, topArtists)) {
      return 'Popular with listeners of ${c.artist}';
    }
    return 'Picked for you';
  }

  static Set<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u00c0-\u024f\u0900-\u097f]+'))
      .where((t) => t.length > 1)
      .toSet();

  static String _normTitle(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _Scored {
  final Song song;
  final double score;
  final double content;
  _Scored(this.song, this.score, this.content);
}
