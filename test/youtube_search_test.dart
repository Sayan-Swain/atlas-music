import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

SearchVideo vid({
  String duration = '3:45',
  List<Thumbnail> thumbs = const [],
}) =>
    SearchVideo(
      VideoId('CUj2AWEJnwQ'),
      'Barbie World',
      'Nicki Minaj',
      'desc',
      duration,
      100,
      thumbs,
      '2 years ago',
      false,
      'channel1',
    );

void main() {
  test('duration parsing: mm:ss, hh:mm:ss, live/empty garbage', () {
    expect(YouTubeService.parseDurationString('3:45'),
        const Duration(minutes: 3, seconds: 45));
    expect(YouTubeService.parseDurationString('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(YouTubeService.parseDurationString('LIVE'), Duration.zero);
    expect(YouTubeService.parseDurationString(''), Duration.zero);
    expect(
        YouTubeService.parseDurationString('Streamed 2 hours ago'),
        Duration.zero);
  });

  test('mapper fills fields, falls back to ytimg thumbnail', () {
    final s = YouTubeService.songFromSearchVideo(vid());
    expect(s.id, 'CUj2AWEJnwQ');
    expect(s.videoId, 'CUj2AWEJnwQ');
    expect(s.title, 'Barbie World');
    expect(s.thumbnailUrl, contains('i.ytimg.com'));
    expect(s.duration, const Duration(minutes: 3, seconds: 45));
  });

  test('mapper never throws on hostile items', () {
    expect(
        () => YouTubeService.songFromSearchVideo(vid(duration: 'LIVE')),
        returnsNormally);
    expect(
        () => YouTubeService.songFromSearchVideo(vid(duration: '')),
        returnsNormally);
  });
}
