import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../media/lyrics_model.dart';
import '../models/song.dart';

/// Synced lyrics via LRCLIB (https://lrclib.net, free, no key).
/// Fallback chain per song (memory → disk → network):
///   1. /api/get track+artist+duration     (exact, best precision)
///   2. /api/get track+artist               (exact, no duration)
///   3. /api/get track+duration             (artist drift on LRCLIB keys,
///      duration-verified so same-title wrong tracks are rejected)
///   4. /api/search?q=track artist          (fuzzy, title+artist guarded,
///      duration-verified title fallback)
/// Never throws: every failure resolves to null and the
/// sheet shows a "not found" state.
///
/// Wrong-lyrics guard: title-only matches (steps 3–4) are the classic
/// source of wrong text (same title, different song). A hit is accepted
/// only when its duration is within [_durationTolerance] of the song, or
/// its artist overlaps ours. No positive contradiction + no overlap is
/// still a miss — a miss beats wrong lyrics.
///
/// NOTE: LRCLIB /api/search ONLY accepts a single `q` param —
/// `track_name`/`artist_name` are for /api/get only. Earlier build
/// passed the wrong params to search, so the fuzzy fallback silently
/// returned nothing and coverage fell to exact-match only.
///
/// NOTE 2: YouTube titles come as "Artist - Title" as often as
/// "Title (Official Video)". [cleanTrack] keeps the FIRST segment, so
/// "Arijit Singh - Kesariya" queried as track="Arijit Singh" (404
/// forever). [trackVariants] also tries the LAST segment, which is
/// why most real-world misses now hit.
class LyricsService {
  static const _host = 'lrclib.net';
  static const _roundTimeout = Duration(seconds: 12);
  static const _netBudget = Duration(seconds: 30);
  /// Max |LRCLIB duration − song duration| for a title-only hit to count
  /// as our song. Loose on purpose: music videos often carry short
  /// intros/outros the audio entry lacks. Same-title wrong tracks
  /// usually differ by far more.
  static const _durationToleranceSec = 10;
  static const _diskTtl = Duration(days: 30);
  static const _ua =
      'AtlasMusic/1.0 (https://github.com/anomalyco/opencode)';

  final http.Client _http;
  final Directory _dir;
  final Map<String, SyncedLyrics?> _mem = {};

  LyricsService({http.Client? client, Directory? dir})
      : _http = client ?? http.Client(),
        _dir = dir ?? Directory.systemTemp;

  /// Strips YouTube junk so "Blinding Lights (Official Video)"
  /// queries as "Blinding Lights". Public + static for tests.
  static String cleanTrack(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\.{3,}'), '');
    s = s.replaceAll(RegExp(r'\.{2,}'), '');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\([^)]*(official|video|audio|lyric|visualizer|remix|cover|live|mv|m\/v)[^)]*\)', caseSensitive: false), ' ');
    // Drop "(From ...)" / "(Feat ...)" suffixes, keep core title.
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    for (final sep in [' - ', ' | ', ' ~ ', ' // ']) {
      if (s.contains(sep)) {
        s = s.split(sep).first;
      }
    }
    s = s.replaceAll(RegExp(r'\s+(feat\.?|ft\.?)\s+.*$', caseSensitive: false), ' ');
    return _collapse(s);
  }

  /// Keeps the first artist: "A, B & C feat D" → "A".
  /// Drops YouTube's " - Topic" suffix. Public + static for tests.
  static String cleanArtist(String raw) {
    var s = raw.replaceAll(RegExp(r'\s*-\s*Topic\s*$', caseSensitive: false), ' ');
    for (final sep in [',', '&', ' x ', ' X ', ' feat', ' FEAT', ' ft', ' FT']) {
      if (s.contains(sep)) {
        s = s.split(sep).first;
      }
    }
    return _collapse(s);
  }

  static String _collapse(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Ordered title candidates for one raw song title.
  /// [cleanTrack] alone keeps the FIRST " - "-separated segment, which is
  /// the artist half of YouTube's "Artist - Title" format. The last
  /// segment is usually the real title there ("Pritam - Kesariya" →
  /// "Kesariya"), while first-wins cases ("Kesariya - Live") still hit
  /// on candidate one. Junk last segments ("Live", "Remix") are dropped.
  /// Public + static for tests.
  static List<String> trackVariants(String raw) {
    final out = <String>[];
    void add(String v) {
      v = _collapse(v);
      if (v.length > 1 && !out.contains(v)) out.add(v);
    }

    add(cleanTrack(raw));
    add(_lastSegment(raw));
    add(cleanSoft(raw));
    return out;
  }

  static String _lastSegment(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(
        RegExp(
            r'\([^)]*(official|video|audio|lyric|visualizer|remix|cover|live|mv|m\/v)[^)]*\)',
            caseSensitive: false),
        ' ');
    var parts = <String>[s];
    for (final sep in [' - ', ' | ', ' ~ ', ' // ', ' : ', ':', '—', '–']) {
      final next = <String>[];
      for (final p in parts) {
        next.addAll(p.split(sep));
      }
      parts = next;
    }
    final cands =
        parts.map(_collapse).where((p) => p.isNotEmpty).toList();
    if (cands.length < 2) return '';
    var last = cands.last.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    last = _collapse(last);
    if (last.length < 2 || _junkSegment.contains(last.toLowerCase())) {
      return '';
    }
    return last;
  }

  /// Last-segment values that are section labels, not titles.
  static const _junkSegment = {
    'live',
    'lyrics',
    'lyric',
    'audio',
    'video',
    'official',
    'mv',
    'm/v',
    'cover',
    'remix',
    'acoustic',
    'instrumental',
    'karaoke',
    'visualizer',
    'version',
    'full',
    'song',
    'music',
    'slowed',
    'reverb',
    'sped up',
    'speed up',
    'tiktok',
    'shorts',
    'hd',
    'hq',
    '4k',
    '8d',
    '1 hour',
    '10 hours',
    'loop',
    'looped',
    'extended',
  };

  /// True when two titles share a real word. Guards fuzzy search picks:
  /// a result titled nothing like the query is never our song, even if
  /// the artist overlaps (compilations, same-artist wrong track).
  static bool _trackOverlaps(String a, String b) {
    final ta = _wordTokens(a);
    final tb = _wordTokens(b);
    for (final t in ta) {
      if (tb.contains(t)) return true;
    }
    return false;
  }

  static Set<String> _wordTokens(String s) {
    return s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00c0-\u024f\u1e00-\u1eff\u0900-\u097f]+'))
        .where((t) => t.length > 1)
        .toSet();
  }
  /// keep everything else intact (title parentheticals, artist combos).
  /// Gentle clean: strip only trailing "(Official Video)" style junk,
  /// keep everything else intact (title parentheticals, artist combos).
  static String cleanSoft(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\.{3,}'), '');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\([^)]*(official|video|audio|subject|ytc[^)]*|visualizer)[^)]*\)', caseSensitive: false), ' ');
    return _collapse(s);
  }

  /// True when LRCLIB's artist string shares at least one token with the
  /// song's artist → guards a title-only /api/get against a wrong song
  /// and ranks search hits. Token-splits on , & x / feat.
  static bool _artistOverlaps(String a, String b) {
    final ta = _artistTokens(a);
    final tb = _artistTokens(b);
    for (final t in ta) {
      if (tb.contains(t)) return true;
    }
    return false;
  }

  static Set<String> _artistTokens(String s) {
    var v = s.toLowerCase()
        .replaceAll(RegExp(r'\bfeat\.?\b|\bft\.?\b|\band\b|\bx\b'), ' ');
    for (final sep in [',', '&', ';', '/', '|']) {
      v = v.replaceAll(sep, ' ');
    }
    return v.split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toSet();
  }

  static String safeKey(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _cacheKey(Song song) {
    final t = cleanTrack(song.title).toLowerCase();
    final a = cleanArtist(song.artist).toLowerCase();
    return 'lyrics_${safeKey(a)}__${safeKey(t)}';
  }

  Future<SyncedLyrics?> fetch(Song song) async {
    final key = _cacheKey(song);
    if (_mem.containsKey(key)) return _mem[key];

    final disk = await _readDisk(key);
    if (disk != null) {
      _mem[key] = disk;
      return disk;
    }

    final tracks = trackVariants(song.title);
    final artist = cleanArtist(song.artist);
    final artists = <String>[
      if (artist.isNotEmpty) artist,
      if (cleanSoft(song.artist).isNotEmpty &&
          cleanSoft(song.artist) != artist)
        cleanSoft(song.artist),
    ];
    if (tracks.isEmpty) {
      _mem[key] = null;
      return null;
    }

    // Whole network phase shares one budget: true misses must resolve
    // to "not found" in seconds, not after every round times out.
    SyncedLyrics? found;
    try {
      found = await _fetchNetwork(song, tracks, artists)
          .timeout(_netBudget, onTimeout: () => null);
    } catch (_) {
      found = null;
    }

    // Negative result (found==null) is still cached so repeat opens
    // are instant, but only for this session — no disk write for miss.
    _mem[key] = found;
    if (found != null) await _writeDisk(key, found);
    return found;
  }

  Future<SyncedLyrics?> _fetchNetwork(
    Song song,
    List<String> tracks,
    List<String> artists,
  ) async {
    final primary = artists.isNotEmpty ? artists.first : '';
    SyncedLyrics? found;
    // 1. Exact get with duration (best precision).
    if (song.duration.inSeconds > 0) {
      for (final t in tracks) {
        found = await _get(
          track: t,
          artist: primary,
          duration: song.duration.inSeconds,
          labelTrack: song.title,
          labelArtist: song.artist,
        );
        if (found != null) return found;
      }
    }
    // 2. Exact get without duration, primary then secondary artist.
    for (final a in artists) {
      for (final t in tracks) {
        found = await _get(
          track: t,
          artist: a,
          labelTrack: song.title,
          labelArtist: song.artist,
        );
        if (found != null) return found;
      }
    }
    // 3. Title + duration (artist on LRCLIB may be composer, not
    // singer). Duration goes along so the server disambiguates, and
    // _get additionally rejects duration contradictions.
    final withDuration = song.duration.inSeconds > 0
        ? song.duration.inSeconds
        : null;
    for (final t in tracks) {
      found = await _get(
        track: t,
        artist: null,
        duration: withDuration,
        labelTrack: song.title,
        labelArtist: song.artist,
      );
      if (found != null) return found;
    }
    // 4. Fuzzy search, title-guarded so same-artist wrong tracks lose.
    final queries = <_Query>[];
    void addQuery(String q, String track) {
      if (q.trim().length > 1 &&
          !queries.any((e) => e.q == q)) {
        queries.add(_Query(q, track));
      }
    }

    for (final t in tracks) {
      for (final a in artists) {
        addQuery('$t $a', t);
      }
    }
    for (final t in tracks) {
      addQuery(t, t);
    }
    final rawTrack = cleanSoft(song.title);
    final rawArtist = cleanSoft(song.artist);
    if (rawTrack.isNotEmpty && rawArtist.isNotEmpty) {
      addQuery('$rawTrack $rawArtist', rawTrack);
    }
    for (final q in queries.take(5)) {
      found = await _searchOnce(
        q.q,
        queryTrack: q.track,
        labelArtist: song.artist,
        labelDuration: song.duration.inSeconds,
      );
      if (found != null) return found;
    }
    return null;
  }

  Future<SyncedLyrics?> _get({
    required String track,
    String? artist,
    int? duration,
    required String labelTrack,
    required String labelArtist,
  }) async {
    try {
      final params = <String, String>{
        'track_name': track,
      };
      if (artist != null && artist.isNotEmpty) {
        params['artist_name'] = artist;
      }
      if (duration != null) params['duration'] = '$duration';
      final uri = Uri.https(_host, '/api/get', params);
      final resp = await _http
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(_roundTimeout);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      // Ignore a hit that clearly belongs to a different song.
      final srcArtist = (data['artistName'] as String?)?.trim() ?? '';
      if (artist != null && artist.isNotEmpty) {
        if (srcArtist.isNotEmpty &&
            !_artistOverlaps(artist, srcArtist)) {
          return null;
        }
      } else {
        // Title-only hit: no artist to check, so the duration must not
        // contradict (same title, different song). Missing duration info
        // on either side is not a contradiction — accept and let the
        // artist-overlap bonus below decide nothing.
        final srcDur = (data['duration'] as num?)?.toDouble();
        if (duration != null &&
            duration > 0 &&
            srcDur != null &&
            (srcDur - duration).abs() > _durationToleranceSec) {
          return null;
        }
      }
      return _fromJson(data, fallbackTrack: labelTrack, fallbackArtist: labelArtist);
    } catch (_) {
      return null;
    }
  }

  Future<SyncedLyrics?> _searchOnce(
    String q, {
    required String queryTrack,
    required String labelArtist,
    required int labelDuration,
  }) async {
    try {
      // LRCLIB /api/search takes a single 'q' param only.
      final uri = Uri.https(_host, '/api/search', {'q': q});
      final resp = await _http
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(_roundTimeout);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! List || data.isEmpty) return null;
      final items = data.whereType<Map<String, dynamic>>().toList();
      if (items.isEmpty) return null;
      // Title must overlap the query track AND artist must overlap
      // (or artist unknown). First synced dual-match wins. No blind
      // items.first fallback: it returned unrelated songs.
      // Title-only fallback additionally requires no duration
      // contradiction, so same-title wrong tracks lose.
      Map<String, dynamic>? overlapPick;
      Map<String, dynamic>? titlePick;
      for (final it in items) {
        final synced = (it['syncedLyrics'] as String?) ?? '';
        if (synced.trim().isEmpty) continue;
        final srcTrack = (it['trackName'] as String?)?.trim() ?? '';
        if (!_trackOverlaps(queryTrack, srcTrack)) continue;
        final srcDur = (it['duration'] as num?)?.toDouble();
        final durClash = labelDuration > 0 &&
            srcDur != null &&
            (srcDur - labelDuration).abs() > _durationToleranceSec;
        if (!durClash) titlePick ??= it;
        final srcArtist = (it['artistName'] as String?)?.trim() ?? '';
        if (labelArtist.trim().isEmpty ||
            _artistOverlaps(labelArtist, srcArtist)) {
          overlapPick = it;
          break;
        }
      }
      final pick = overlapPick ?? titlePick;
      if (pick == null) return null;
      return _fromJson(pick,
          fallbackTrack: queryTrack, fallbackArtist: labelArtist);
    } catch (_) {
      return null;
    }
  }

  SyncedLyrics? _fromJson(    Map<String, dynamic> data, {
    required String fallbackTrack,
    required String fallbackArtist,
  }) {
    final instrumental = data['instrumental'] == true;
    final track = (data['trackName'] as String?)?.trim();
    final artist = (data['artistName'] as String?)?.trim();
    final synced = (data['syncedLyrics'] as String?) ?? '';
    final plain = (data['plainLyrics'] as String?) ?? '';
    if (instrumental) {
      return SyncedLyrics(
        track: (track?.isNotEmpty ?? false) ? track! : fallbackTrack,
        artist: (artist?.isNotEmpty ?? false) ? artist! : fallbackArtist,
        lines: const [],
        isSynced: false,
        instrumental: true,
      );
    }
    final lines = synced.trim().isEmpty ? <LyricLine>[] : parseLrc(synced);
    if (lines.isNotEmpty) {
      return SyncedLyrics(
        track: (track?.isNotEmpty ?? false) ? track! : fallbackTrack,
        artist: (artist?.isNotEmpty ?? false) ? artist! : fallbackArtist,
        lines: lines,
        isSynced: true,
      );
    }
    if (plain.trim().isNotEmpty) {
      return SyncedLyrics(
        track: (track?.isNotEmpty ?? false) ? track! : fallbackTrack,
        artist: (artist?.isNotEmpty ?? false) ? artist! : fallbackArtist,
        lines: const [],
        isSynced: false,
        plain: plain.trim(),
      );
    }
    return null;
  }

  Future<SyncedLyrics?> _readDisk(String key) async {
    try {
      final f = File('${_dir.path}/$key.json');
      if (!await f.exists()) return null;
      final raw = json.decode(await f.readAsString());
      if (raw is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(raw['fetchedAt'] as String? ?? '');
      if (at == null || DateTime.now().difference(at) > _diskTtl) {
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }
      if (raw['instrumental'] == true) {
        return SyncedLyrics(
          track: (raw['track'] as String?) ?? '',
          artist: (raw['artist'] as String?) ?? '',
          lines: const [],
          isSynced: false,
          instrumental: true,
        );
      }
      final isSynced = raw['isSynced'] == true;
      if (isSynced) {
        final list = (raw['lines'] as List?) ?? [];
        final lines = <LyricLine>[];
        for (final e in list) {
          if (e is! List || e.length < 2) continue;
          final ms = e[0] is int ? e[0] as int : int.tryParse('${e[0]}') ?? 0;
          lines.add(LyricLine(
            start: Duration(milliseconds: ms),
            text: '${e[1]}',
          ));
        }
        if (lines.isEmpty) return null;
        return SyncedLyrics(
          track: (raw['track'] as String?) ?? '',
          artist: (raw['artist'] as String?) ?? '',
          lines: lines,
          isSynced: true,
        );
      }
      final plain = (raw['plain'] as String?) ?? '';
      if (plain.trim().isEmpty) return null;
      return SyncedLyrics(
        track: (raw['track'] as String?) ?? '',
        artist: (raw['artist'] as String?) ?? '',
        lines: const [],
        isSynced: false,
        plain: plain,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String key, SyncedLyrics lyrics) async {
    try {
      final f = File('${_dir.path}/$key.json');
      await f.writeAsString(json.encode({
        'track': lyrics.track,
        'artist': lyrics.artist,
        'isSynced': lyrics.isSynced,
        'instrumental': lyrics.instrumental,
        'plain': lyrics.plain ?? '',
        'lines': lyrics.lines
            .map((l) => [l.start.inMilliseconds, l.text])
            .toList(),
        'fetchedAt': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }
}

/// Search query paired with the title variant it came from, so picks
/// can require title overlap with the query (not just artist).
class _Query {
  final String q;
  final String track;
  _Query(this.q, this.track);
}
