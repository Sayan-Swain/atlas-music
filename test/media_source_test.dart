import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/media/media_source.dart';

MediaSource src({
  String container = 'mp4',
  String codec = 'mp4a.40.2',
  String mime = 'audio/mp4',
  String url = 'https://x/y',
  DateTime? expiresAt,
}) =>
    MediaSource(
      provider: MediaProvider.youTube,
      url: url,
      mimeType: mime,
      codec: codec,
      container: container,
      resolvedAt: DateTime.now(),
      expiresAt: expiresAt,
    );

void main() {
  test('mp4/aac accepted', () {
    expect(src().hasCompatibleContainer, isTrue);
  });

  test('webm/opus accepted', () {
    expect(
        src(container: 'webm', codec: 'opus', mime: 'audio/webm')
            .hasCompatibleContainer,
        isTrue);
  });

  test('mp3 accepted', () {
    expect(
        src(container: 'mp3', codec: 'mp3', mime: 'audio/mpeg')
            .hasCompatibleContainer,
        isTrue);
  });

  test('unknown container+codec rejected before playback', () {
    expect(
        src(container: 'avi', codec: 'h264', mime: 'video/avi')
            .hasCompatibleContainer,
        isFalse);
  });

  test('expired URL detected', () {
    final expired = src(
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)));
    expect(expired.isExpired, isTrue);
    final fresh = src(
        expiresAt: DateTime.now().add(const Duration(hours: 5)));
    expect(fresh.isExpired, isFalse);
  });
}
