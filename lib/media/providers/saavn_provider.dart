import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../media_source.dart';
import '../media_resolver.dart';
import '../resolve_failure.dart';

/// JioSaavn backend via JioSaavn's OWN public JSON API — no third-party
/// proxy. Two official endpoints:
///   autocomplete.get  → top songs for a query (gives perma-url token)
///   webapi.get        → full song detail incl. clear preview MP3 (vlink)
/// The vlink is a plain-HTTPS MP3 on c.saavncdn / jiotunepreview — a
/// plain-GET proxy-style source, no range semantics, streamed straight
/// to ExoPlayer or downloaded for offline.
///
/// Reachability note (2026-09): public *proxy* hosts (saavn.dev, *.harsh-
/// patel.vercel.app, saavn.sumitkr.in, saavn.me…) are dead or
/// persistently 429/500 from throttled India networks. JioSaavn's own
/// API stays up and its CDN is not googlevideo, so it survives the
/// network rules that kill YouTube. Same [MediaResolver] contract as
/// every provider: downstream never knows JioSaavn exists.
class SaavnProvider extends MediaResolver {
  static const String _api = 'https://www.jiosaavn.com/api.php';
  static const Duration _roundTimeout = Duration(seconds: 12);

  final http.Client _http;

  SaavnProvider({http.Client? client}) : _http = client ?? http.Client();

  @override
  MediaProvider get provider => MediaProvider.saavn;

  @override
  Duration get resolveBudget => const Duration(seconds: 60);

  String _sanitizeQuery(String q) {
    var s = q.trim();
    s = s.replaceAll(RegExp(r'\.{2,}'), '');
    s = s.replaceAll(RegExp(r'/\s*|\s*\/\s*'), ' ');
    // Bracketed credits ("(Official Music Video)", "[4K]") and @handles
    // ("Prod. @AliSoomroMusic") poison autocomplete: the core
    // "Artist - Title" is what matches.
    s = s.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), ' ');
    s = s.replaceAll(RegExp(r'\s*@[\w.]+'), '');
    s = s.replaceAll(RegExp(r'\s*\bprod\.?\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\s+(official\s+)?(video|music\s+video|full\s+song|lyrics?)\b', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\b(yt|youtube|spotify|soundcloud|jio|saavn|gaana|wynk)\b', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return s;
  }

  @override
  Future<MediaSource> resolve(Song song) async {
    final rawTitle = _sanitizeQuery(song.title);
    final rawArtist = _sanitizeQuery(song.artist);
    final target =
        (rawTitle.isEmpty ? '' : rawTitle) + (rawArtist.isEmpty ? '' : ' ${rawArtist}');

    final candidates = <String>{
      target.trim(),
      rawTitle,
    }.where((q) => q.isNotEmpty).toList();

    ResolveFailure? last;
    for (final q in candidates) {
      try {
        final src = await _resolveQuery(q);
        if (src != null) return src;
      } on ResolveFailure catch (e) {
        last = e;
      }
    }
    throw last ??
        ResolveFailure(
          provider: provider,
          stage: ResolveStage.resolution,
          scope: FailureScope.song,
          detail:
              'no match for "${song.title} / ${song.artist}" on JioSaavn',
          retryable: true,
        );
  }

  Future<MediaSource?> _resolveQuery(String query) async {
    final results = await _callSearch(query);
    if (results.isEmpty) return null;
    final best = bestSong(results,
        normalizedQuery: normalize(query.trim()));
    if (best == null) return null;
    final token = tokenOf(best);
    final detail = await _callSongDetail(best);
    final vlink = detail?.vlink;
    if (vlink == null || vlink.isEmpty) return null;
    return MediaSource(
      provider: provider,
      url: vlink,
      mimeType: 'audio/mpeg',
      codec: 'mp3',
      container: 'mp3',
      bitrate: detail?.bitrate ?? 128000,
      contentLength: detail?.contentLength,
      isProxy: true,
      mediaId: token,
      resolvedAt: DateTime.now(),
    );
  }

  /// JioSaavn song token from any autocomplete shape: url (perma_url)
  /// last path segment, else bare id. Both feed webapi.get.
  static String tokenOf(Map<String, dynamic> song) {
    final url = (song['url'] as String?) ?? '';
    final fromUrl = url.split('/').last;
    if (fromUrl.isNotEmpty) return fromUrl;
    return (song['id'] as String?) ?? '';
  }

  Future<List<Map<String, dynamic>>> _callSearch(String query) async {
    final uri = Uri.parse(_api).replace(queryParameters: {
      '__call': 'autocomplete.get',
      '_format': 'json',
      'cc': 'in',
      '_marker': '0',
      'query': query,
    });
    try {
      final resp = await _http
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(_roundTimeout);
      if (resp.statusCode != 200) return const [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final songs = data['songs']?['data'];
      if (songs is List) {
        return songs.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Pick the canonical film version, not a remix. Ranking:
  /// 1. exact normalized-title match
  /// 2. shorter title (drops the "(Lofi …)" suffix variants)
  /// 3. stable: keep first
  static Map<String, dynamic>? bestSong(
    List<Map<String, dynamic>> results, {
    String? normalizedQuery,
  }) {
    if (results.isEmpty) return null;
    final q = normalizedQuery ?? '';
    Map<String, dynamic>? best;
    int bestScore = -(1 << 62);
    for (final s in results) {
      final t = (s['title'] as String? ?? '').toLowerCase().trim();
      if (t.isEmpty) continue;
      if (q.isNotEmpty && normalize(t) == q) {
        return s; // exact match always wins
      }
      final score = -t.length; // shorter title = fewer parentheticals
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best ?? results.first;
  }
  static String normalize(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[\.\|/\\]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  Future<_SongDetail?> _callSongDetail(Map<String, dynamic> song) async {
    final uid = tokenOf(song); // e.g. LxAOQS1aZVg
    if (uid.isEmpty) return null;
    return _detailFromToken(uid);
  }

  Future<_SongDetail?> _detailFromToken(String token) async {
    final uri = Uri.parse(_api).replace(queryParameters: {
      '__call': 'webapi.get',
      '_format': 'json',
      'token': token,
      'type': 'song',
      'cc': 'in',
      'api_version': '4',
      '_marker': '0',
    });
    try {
      final resp = await _http
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(_roundTimeout);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      final entries = data.values.whereType<Map<String, dynamic>>();
      for (final e in entries) {
        final mi = e['more_info'];
        if (mi is! Map<String, dynamic>) continue;
        final vlink = (mi['vlink'] as String?) ?? '';
        if (vlink.isEmpty) continue;
        String? mediaUrl;
        final mu = (e['media_url'] as String?) ?? '';
        if (mu.isNotEmpty && mu.contains('http')) mediaUrl = mu;
        final bitrate =
            _bitrateFrom((e['more_info']?['320kbps'] as String?));
        return _SongDetail(
          vlink: vlink,
          mediaUrl: mediaUrl,
          bitrate: bitrate,
          contentLength:
              _lengthFrom(e['more_info']?['duration'], bitrate),
        );
      }
    } catch (_) {}
    return null;
  }

  int _bitrateFrom(String? b) {
    if (b == null) return 128000;
    // '320kbps' → 320000; true string.
    return (b.toLowerCase() == 'true' ||
            b.toLowerCase().contains('320'))
        ? 320000
        : 128000;
  }

  int? _lengthFrom(String? seconds, int bitrate) {
    if (seconds == null) return null;
    final s = int.tryParse(seconds);
    // Estimated full-track bytes at the ACTUAL bitrate (the API never
    // surfaces content length). Must match the real bitrate — the
    // truncation guards compare against this, and a 320kbps assumption
    // would falsely reject genuine 128kbps streams as previews.
    if (s == null || s <= 0 || bitrate <= 0) return null;
    return (s * bitrate) ~/ 8;
  }

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  @override
  Future<MediaSource> validate(MediaSource source) async {
    checkCompatible(source);
    try {
      final resp = await _http
          .head(Uri.parse(source.url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw ResolveFailure(
          provider: provider,
          stage: ResolveStage.validation,
          scope: FailureScope.url,
          detail: 'JioSaavn CDN HEAD rejected',
          httpStatus: resp.statusCode,
          retryable: true,
        );
      }
      // Preview guard: vlink is a short preview clip, not the full song.
      // [contentLength] estimates the FULL track, so a HEAD advertising
      // far fewer bytes proves this URL would play a ~15s snippet and
      // then stop. Reject it instead of serving a snippet as a song.
      final advertised = int.tryParse(resp.headers['content-length'] ?? '');
      final expected = source.contentLength;
      if (advertised != null &&
          advertised > 0 &&
          expected != null &&
          expected > 0 &&
          advertised < (expected * 0.7).round()) {
        throw ResolveFailure(
          provider: provider,
          stage: ResolveStage.validation,
          scope: FailureScope.url,
          detail:
              'JioSaavn preview-length file ($advertised of $expected bytes)',
          retryable: true,
        );
      }
      return source;
    } catch (e) {
      if (e is ResolveFailure) rethrow;
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.provider,
        detail: 'JioSaavn CDN unreachable: $e',
        retryable: true,
      );
    }
  }

  @override
  Future<void> download(MediaSource source, File file) async {
    try {
      final req = http.Request('GET', Uri.parse(source.url));
      final resp = await _http.send(req).timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw ResolveFailure(
          provider: provider,
          stage: ResolveStage.download,
          detail: 'JioSaavn CDN download rejected',
          httpStatus: resp.statusCode,
          retryable: true,
        );
      }
      final sink = file.openWrite();
      try {
        await resp.stream.pipe(sink).timeout(const Duration(seconds: 120));
      } finally {
        await sink.close();
      }
      if (await file.length() == 0) {
        throw ResolveFailure(
          provider: provider,
          stage: ResolveStage.download,
          detail: 'JioSaavn CDN download produced empty file',
          retryable: true,
        );
      }
    } on ResolveFailure {
      rethrow;
    } catch (e) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.download,
        detail: 'JioSaavn CDN download failed: $e',
        retryable: true,
      );
    }
  }

  void dispose() => _http.close();
}

class _SongDetail {
  final String vlink;
  final String? mediaUrl;
  final int bitrate;
  final int? contentLength;

  const _SongDetail({
    required this.vlink,
    this.mediaUrl,
    required this.bitrate,
    this.contentLength,
  });
}