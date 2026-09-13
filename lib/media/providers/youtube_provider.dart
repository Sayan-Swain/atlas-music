import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/song.dart';
import '../media_source.dart';
import '../media_resolver.dart';
import '../resolve_failure.dart';

/// Sole owner of `youtube_explode_dart` (3.1.0, pinned) and of all
/// googlevideo range semantics. If YouTube changes InnerTube tomorrow,
/// only this file changes.
///
/// Client: VISIONOS (vendored below). Android/ANDROID clients trigger the
/// "downloaded this stream too many times" throttle that 403s googlevideo
/// after a few ranged requests — the exact failure on throttled networks.
/// VisionOS is a non-Android Apple client, no POT requirement, not subject
/// to that throttle. Same idea as the Harmony-Music fork of the library.
///
/// Ranking (deterministic, documented):
///  1. Compatible container/codec first: MP4/AAC (`mp4a`) beats Opus/WebM.
///     Reason: ExoPlayer handles both, but AAC-in-MP4 survives more
///     network stacks, proxies and download-then-play paths.
///  2. Within one codec family: highest bitrate first. (The library's
///     `sortByBitrate()` already returns highest-first despite its doc
///     comment; we keep that order, we do NOT pick `.last`.)
///  3. Streams with known non-zero content length beat unknown ones.
///  4. Absolute quality last: a reliable 48kbps AAC wins over an
///     unreliable 160kbps opus. Reliability is established by [validate].
class YouTubeProvider extends MediaResolver {
  static const _manifestTimeout = Duration(seconds: 30);

  /// Download chunk size. 1MB BY MEASUREMENT (live probe 2026-09):
  /// throttled ANDROID URLs 403 open-ended and 10MB ranges, 206 ≤1MB.
  /// Static + tested so nobody "upgrades" it back to library-style 10MB.
  static const downloadChunkBytes = 1024 * 1024;

  final YoutubeExplode _yt = YoutubeExplode();
  final http.Client _http = http.Client();

  /// Manifest cache: one InnerTube player call serves resolve, retries,
  /// downloads, and replays of the same video. Without it every retry
  /// re-hits the API and a 429 spiral takes playback down entirely.
  final Map<String, _CachedManifest> _manifests = {};
  static const _manifestTtl = Duration(minutes: 20);

  /// True when an error looks like API rate limiting (HTTP 429 family).
  /// Static for unit tests.
  static bool isRateLimited(Object e) {
    final t = e.toString().toLowerCase();
    return t.contains('429') ||
        t.contains('rate limit') ||
        t.contains('rate-limit') ||
        t.contains('too many requests') ||
        t.contains('quota exceeded');
  }

  Future<StreamManifest> _fetchManifest(String videoId) async {
    final hit = _manifests[videoId];
    if (hit != null &&
        DateTime.now().difference(hit.at) < _manifestTtl) {
      return hit.manifest;
    }
    // Rate limits are worth waiting out (short backoff); anything else
    // fails fast so one bad video never stalls playback for seconds.
    const waits = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)];
    Object? last;
    for (var attempt = 0; attempt < waits.length; attempt++) {
      if (attempt > 0) await Future.delayed(waits[attempt]);
      try {
        final m = await _yt.videos.streamsClient
            .getManifest(VideoId(videoId),
                ytClients: const [_visionosClient])
            .timeout(_manifestTimeout);
        _manifests[videoId] = _CachedManifest(m, DateTime.now());
        if (_manifests.length > 60) {
          _manifests.remove(_manifests.keys.first);
        }
        return m;
      } catch (e) {
        last = e;
        if (!isRateLimited(e)) rethrow;
      }
    }
    throw last!;
  }

  /// VisionOS YouTube client (from the Harmony-Music fork of
  /// youtube_explode_dart). Non-Android Apple client: no androidSdkVersion,
  /// no POT requirement, and crucially NOT subject to the Android "you
  /// downloaded this stream too many times" throttle that 403s ANDROID
  /// URLs after a few ranged requests. Publicly constructible in the pinned
  /// 3.1.0 library, so we vendor the payload instead of depending on a fork.
  static const _visionosClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  @override
  MediaProvider get provider => MediaProvider.youTube;

  @override
  Duration get resolveBudget => const Duration(seconds: 60);

  @override
  Future<MediaSource> resolve(Song song) async {
    final videoId = song.videoId ?? song.id;
    StreamManifest manifest;
    try {
      manifest = await _fetchManifest(videoId);
    } catch (e) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.resolution,
        scope: _scopeFor(e),
        detail: 'manifest failed for $videoId: $e',
        retryable: true,
      );
    }
    final ranked = rankAudio(manifest);
    if (ranked.isEmpty) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.resolution,
        scope: FailureScope.song,
        detail: 'no audio streams for $videoId',
        retryable: true,
      );
    }
    // Probe top candidates: one expired/throttled URL must not burn the
    // whole provider. First passing HEAD wins; per-URL misses are
    // url-scoped and recorded in the detail line.
    final misses = <String>[];
    var sawNetworkError = false;
    for (final info in ranked.take(3)) {
      final src = _toSource(info, videoId);
      try {
        await _head(src.url);
        return src;
      } on ResolveFailure catch (e) {
        if (e.scope == FailureScope.provider) sawNetworkError = true;
        misses.add('${info.tag}: ${e.detail}');
      }
    }
    throw ResolveFailure(
      provider: provider,
      stage: ResolveStage.validation,
      scope: sawNetworkError && misses.isNotEmpty
          ? FailureScope.provider
          : FailureScope.song,
      detail: 'top ${misses.length} URLs unusable for $videoId '
          '(${misses.join('; ')})',
      retryable: true,
    );
  }

  /// Unplayable-video errors are song-level (other songs may resolve fine);
  /// transport errors are provider-level (count toward cooldown).
  FailureScope _scopeFor(Object e) {
    if (e is VideoUnavailableException ||
        e is VideoUnplayableException ||
        e is VideoRequiresPurchaseException) {
      return FailureScope.song;
    }
    return FailureScope.provider;
  }

  /// Player-style probe: ranged GET of the first byte with a browser UA.
  /// A bare HEAD is rejected (403) even for healthy URLs, so HEAD proves
  /// nothing. 200/206 here means ExoPlayer (which sends the same headers)
  /// can open the stream. 403/404/empty = url-scoped (that URL is dead);
  /// transport failure = provider-scoped.
  static const _probeUa =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  Future<int> _head(String url) async {
    final baseUri = Uri.parse(url);
    final bool isAndroid = baseUri.queryParameters['c'] == 'ANDROID';
    http.StreamedResponse resp;
    try {
      if (isAndroid) {
        final req = http.Request('GET', baseUri)
          ..headers.addAll({
            'User-Agent': _probeUa,
            'Range': 'bytes=0-1023',
          });
        resp = await _http.send(req).timeout(const Duration(seconds: 8));
      } else {
        final uri = baseUri.replace(queryParameters: {
          ...baseUri.queryParameters,
          'range': '0-1023',
        });
        final req = http.Request('GET', uri)
          ..headers.addAll({'User-Agent': _probeUa});
        resp = await _http.send(req).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.provider,
        detail: 'stream probe unreachable: $e',
        retryable: true,
      );
    }
    try {
      await resp.stream.drain().timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (resp.statusCode == 403 || resp.statusCode == 404) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.url,
        detail: 'googlevideo rejected probe (throttled/expired URL)',
        httpStatus: resp.statusCode,
        retryable: true,
      );
    }
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.url,
        detail: 'unexpected probe status',
        httpStatus: resp.statusCode,
        retryable: true,
      );
    }
    final len = int.tryParse(resp.headers['content-length'] ?? '');
    if (len != null && len <= 0) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.url,
        detail: 'zero content length',
        retryable: true,
      );
    }
    return len ?? -1;
  }

  /// Pure ranking over manifest audio streams. Static for unit tests.
  static List<AudioOnlyStreamInfo> rankAudio(StreamManifest manifest) {
    final audio = manifest.audioOnly.sortByBitrate().toList();
    final knownSize =
        audio.where((s) => s.size.totalBytes > 0).toList();
    final unknownSize =
        audio.where((s) => s.size.totalBytes <= 0).toList();
    List<AudioOnlyStreamInfo> rank(List<AudioOnlyStreamInfo> list) {
      final mp4a =
          list.where((s) => s.codec.toString().contains('mp4a')).toList();
      final rest =
          list.where((s) => !s.codec.toString().contains('mp4a')).toList();
      return [...mp4a, ...rest];
    }
    return [...rank(knownSize), ...rank(unknownSize)];
  }

  MediaSource _toSource(AudioOnlyStreamInfo s, String videoId) {
    DateTime? expiry;
    try {
      final exp = s.url.queryParameters['expire'];
      if (exp != null) {
        expiry = DateTime.fromMillisecondsSinceEpoch(
            int.parse(exp) * 1000,
            isUtc: true);
      }
    } catch (_) {}
    return MediaSource(
      provider: provider,
      url: s.url.toString(),
      mimeType: 'audio/${s.container.name}',
      codec: s.audioCodec,
      container: s.container.name,
      bitrate: s.bitrate.bitsPerSecond.toInt(),
      contentLength:
          s.size.totalBytes > 0 ? s.size.totalBytes : null,
      isProxy: false,
      expiresAt: expiry,
      mediaId: videoId,
      resolvedAt: DateTime.now(),
    );
  }

  @override
  Future<MediaSource> validate(MediaSource source) async {
    checkCompatible(source);
    // resolve() already probed this exact URL seconds earlier. Re-probing
    // doubles per-URL requests, and throttled ANDROID URLs start 403ing
    // after a handful of hits (short clips survive, full songs don't).
    // Trust a fresh probe; re-probe only stale sources.
    if (source.contentLength != null &&
        source.contentLength! > 0 &&
        DateTime.now().difference(source.resolvedAt) <
            const Duration(seconds: 60)) {
      return source;
    }
    final advertised = await _head(source.url);
    // Preview guard: YouTube may serve short preview clips with full-length metadata.
    // If HEAD advertises far fewer bytes than the manifest total, reject as preview.
    if (source.contentLength != null &&
        source.contentLength! > 0 &&
        advertised > 0) {
      // advertised for a range request is the range size; for full request it is total.
      // If we received a full length, compare directly. If range size, skip comparison.
      // Simple heuristic: if advertised is small (<1MB) and expected is large, treat as preview.
      if (advertised < source.contentLength! * 0.7 && advertised < 2 * 1024 * 1024) {
        throw ResolveFailure(
          provider: provider,
          stage: ResolveStage.validation,
          scope: FailureScope.url,
          detail: 'YouTube preview-length stream ($advertised of ${source.contentLength} bytes)',
          retryable: true,
        );
      }
    }
    // Keep the manifest's total length: the probe only fetches 1KB, so its
    // own content-length must never overwrite it (cache size checks rely
    // on the real total).
    return MediaSource(
      provider: source.provider,
      url: source.url,
      mimeType: source.mimeType,
      codec: source.codec,
      container: source.container,
      bitrate: source.bitrate,
      contentLength: source.contentLength,
      isProxy: source.isProxy,
      expiresAt: source.expiresAt,
      mediaId: source.mediaId,
      resolvedAt: source.resolvedAt,
    );
  }

  /// Minimum download chunk. Below this, shrinking stops and the
  /// download fails instead of hammering a throttled URL forever.
  static const minChunkBytes = 64 * 1024;

  /// Next chunk size after a rejection, or null when exhausted.
  /// Pure for unit tests.
  static int? shrinkChunk(int current) {
    final next = current ~/ 2;
    return next >= minChunkBytes ? next : null;
  }

  @override
  Future<void> download(MediaSource source, File file) async {
    // One dead URL must not kill the download: throttle counters appear
    // per-URL (short clips download in 1 request; full songs die after a
    // few hits on the same URL). So try the passed URL, then up to 2
    // freshly-resolved alternates (different itags = different counters).
    final tried = <String>{};
    ResolveFailure? last;
    MediaSource? current = source;
    for (var attempt = 0; attempt < 3 && current != null; attempt++) {
      if (!tried.add(current.url)) break;
      try {
        await _downloadUrl(current.url, file, current.contentLength);
        return;
      } on ResolveFailure catch (e) {
        last = e;
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        current = await _nextCandidate(current, tried);
      }
    }
    throw last ??
        ResolveFailure(
          provider: provider,
          stage: ResolveStage.download,
          detail: 'no downloadable URL',
          retryable: true,
        );
  }

  /// Fresh manifest, first ranked untried URL, probed. Null when
  /// nothing new is available.
  Future<MediaSource?> _nextCandidate(
      MediaSource failed, Set<String> tried) async {
    final videoId = failed.mediaId;
    if (videoId == null || videoId.isEmpty) return null;
    try {
      final manifest = await _fetchManifest(videoId);
      for (final info in rankAudio(manifest)) {
        final src = _toSource(info, videoId);
        if (tried.contains(src.url)) continue;
        try {
          await _head(src.url);
          return src;
        } catch (_) {
          tried.add(src.url);
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Chunked fetch of one URL with adaptive shrink (1MB → 64KB).
  /// Range semantics: visionos URLs return 200 (not 206) with the exact
  /// ranged body, and 416 past EOF. So completion is decided by byte
  /// accounting against [contentLength] when known, not by status code.
  Future<void> _downloadUrl(String url, File file, int? contentLength) async {
    var chunk = downloadChunkBytes;
    final baseUri = Uri.parse(url);
    final isAndroid = baseUri.queryParameters['c'] == 'ANDROID';
    final total = contentLength ?? int.tryParse(baseUri.queryParameters['clen'] ?? '');
    int start = 0;
    final sink = file.openWrite();
    try {
      while (total == null || start < total) {
        final end = start + chunk - 1;
        final http.Request req;
        if (isAndroid) {
          req = http.Request('GET', baseUri)
            ..headers.addAll({
              'Range': 'bytes=$start-$end',
              'Connection': 'keep-alive',
            });
        } else {
          final uri = baseUri.replace(queryParameters: {
            ...baseUri.queryParameters,
            'range': '$start-$end',
          });
          req = http.Request('GET', uri)
            ..headers.addAll({'Connection': 'keep-alive'});
        }
        final resp = await _http
            .send(req)
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode == 416) break; // past EOF
        if (resp.statusCode == 403 || resp.statusCode == 400) {
          try {
            await resp.stream.drain();
          } catch (_) {}
          final next = shrinkChunk(chunk);
          if (next == null) {
            throw ResolveFailure(
              provider: provider,
              stage: ResolveStage.download,
              detail: 'chunk download rejected down to 64KB',
              httpStatus: resp.statusCode,
              retryable: true,
            );
          }
          chunk = next;
          continue; // retry same byte range, smaller window
        }
        if (resp.statusCode != 200 && resp.statusCode != 206) {
          throw ResolveFailure(
            provider: provider,
            stage: ResolveStage.download,
            detail: 'chunk download rejected',
            httpStatus: resp.statusCode,
            retryable: true,
          );
        }
        var got = 0;
        await for (final data in resp.stream) {
          got += data.length;
          sink.add(data);
        }
        start += got;
        if (got < chunk) break; // short read = EOF
        if (total == null && resp.statusCode == 200) break; // single-shot full file
      }
    } on ResolveFailure {
      rethrow;
    } catch (e) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.download,
        detail: 'download failed: $e',
        retryable: true,
      );
    } finally {
      await sink.close();
    }
    if (!await file.exists() || await file.length() == 0) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.download,
        detail: 'download produced empty file',
        retryable: true,
      );
    }
    // A short read (got < chunk) ends the loop, but on flaky networks the
    // connection can drop mid-file with no error. Against a known total
    // that is truncation, not EOF: fail so download() retries a fresh
    // itag instead of caching a file that plays seconds then stops.
    if (total != null && start < total) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.download,
        detail: 'incomplete download (got $start of $total bytes)',
        retryable: true,
      );
    }
  }

  void dispose() {
    _manifests.clear();
    _http.close();
    _yt.close();
  }
}

/// In-memory manifest entry. URLs carry their own expiry; the TTL only
/// bounds reuse so retries and replays share one InnerTube call.
class _CachedManifest {
  final StreamManifest manifest;
  final DateTime at;
  _CachedManifest(this.manifest, this.at);
}
