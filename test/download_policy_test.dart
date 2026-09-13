import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/media/media_source.dart';
import 'package:atlas_music/media/providers/youtube_provider.dart';
import 'package:atlas_music/media/resolve_failure.dart';

void main() {
  test('download chunks stay at measured 1MB (10MB/open ranges get 403)',
      () {
    expect(YouTubeProvider.downloadChunkBytes, 1024 * 1024);
  });

  test('chunk shrink halves down to 64KB then gives up', () {
    expect(YouTubeProvider.shrinkChunk(1024 * 1024), 512 * 1024);
    expect(YouTubeProvider.shrinkChunk(512 * 1024), 256 * 1024);
    expect(YouTubeProvider.shrinkChunk(128 * 1024), 64 * 1024);
    expect(YouTubeProvider.shrinkChunk(64 * 1024), isNull);
  });

  test('rate-limit detector catches 429 family, ignores the rest', () {
    expect(YouTubeProvider.isRateLimited(Exception('HTTP 429')), isTrue);
    expect(
        YouTubeProvider.isRateLimited(
            Exception('Request failed: too many requests')),
        isTrue);
    expect(
        YouTubeProvider.isRateLimited(
            Exception('Rate limit exceeded, retry later')),
        isTrue);
    expect(
        YouTubeProvider.isRateLimited(
            Exception('VideoUnavailableException: deleted')),
        isFalse);
    expect(
        YouTubeProvider.isRateLimited(
            TimeoutException('manifest', const Duration(seconds: 25))),
        isFalse);
  });

  test('user message keeps HTTP status for diagnosability', () {
    final r = PlaybackReport('T');
    r.add(ResolveFailure(
      provider: null,
      stage: ResolveStage.download,
      detail: 'chunk download rejected',
      httpStatus: 403,
    ));
    expect(r.toUserMessage(), contains('HTTP 403'));
  });

  test(
      'truncated connection with known total throws instead of committing partial',
      () async {
    // Server answers the 1MB range with a clean 100KB then EOF.
    // Old code read that short read as EOF and cached a file that
    // played seconds then stopped. Must throw so download() tries
    // the next itag instead.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = 206;
      req.response.contentLength = 100 * 1024;
      req.response.add(List.filled(100 * 1024, 0));
      await req.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('atlas_trunc_');
    final provider = YouTubeProvider();
    try {
      final file = File('${dir.path}/t.part');
      final src = MediaSource(
        provider: MediaProvider.youTube,
        url: 'http://127.0.0.1:${server.port}/v',
        mimeType: 'audio/mp4',
        codec: 'mp4a.40.2',
        container: 'mp4',
        contentLength: 3 * 1024 * 1024,
        resolvedAt: DateTime.now(),
      );
      await expectLater(
          provider.download(src, file), throwsA(isA<ResolveFailure>()));
      expect(await file.exists(), isFalse);
    } finally {
      provider.dispose();
      await server.close(force: true);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
