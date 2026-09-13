import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/media/media_resolver.dart';
import 'package:atlas_music/media/media_source.dart';
import 'package:atlas_music/media/resolve_failure.dart';
import 'package:atlas_music/media/resolver_strategy.dart';
import 'package:atlas_music/models/song.dart';

/// Scripted resolver: fails [failTimes] resolutions, then succeeds.
class FakeResolver extends MediaResolver {
  @override
  final MediaProvider provider;
  @override
  final Duration resolveBudget = const Duration(seconds: 2);
  int failTimes;
  final FailureScope failScope;
  int resolveCalls = 0;
  final MediaSource good;

  FakeResolver(this.provider, this.good,
      {this.failTimes = 0, this.failScope = FailureScope.song});

  @override
  Future<MediaSource> resolve(Song song) async {
    resolveCalls++;
    if (failTimes > 0) {
      failTimes--;
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.resolution,
        scope: failScope,
        detail: 'scripted failure',
      );
    }
    return good;
  }

  @override
  Future<MediaSource> validate(MediaSource source) async => source;

  @override
  Future<void> download(MediaSource source, File file) async {
    await file.writeAsString('bytes');
  }
}

Song get song => Song(
      id: 'v1',
      title: 'T',
      artist: 'A',
      thumbnailUrl: '',
      duration: Duration.zero,
      videoId: 'v1',
    );

MediaSource goodOf(MediaProvider p) => MediaSource(
      provider: p,
      url: 'https://$p/x',
      mimeType: 'audio/mp4',
      codec: 'mp4a.40.2',
      container: 'mp4',
      resolvedAt: DateTime.now(),
    );

void main() {
  test('first healthy provider wins, order preserved', () async {
    final a = FakeResolver(MediaProvider.youTube, goodOf(MediaProvider.youTube));
    final b = FakeResolver(MediaProvider.piped, goodOf(MediaProvider.piped));
    final s = ResolverStrategy([a, b]);
    final report = PlaybackReport('T');
    final got = await s.resolveFirstValid(song, report);
    expect(got?.provider, MediaProvider.youTube);
    expect(b.resolveCalls, 0);
    expect(report.attempts, isEmpty);
  });

  test('failure fails over to next provider with structured record', () async {
    final a = FakeResolver(MediaProvider.youTube, goodOf(MediaProvider.youTube),
        failTimes: 1);
    final b = FakeResolver(MediaProvider.piped, goodOf(MediaProvider.piped));
    final s = ResolverStrategy([a, b]);
    final report = PlaybackReport('T');
    final got = await s.resolveFirstValid(song, report);
    expect(got?.provider, MediaProvider.piped);
    expect(report.attempts.length, 1);
    expect(report.attempts.first.provider, MediaProvider.youTube);
    expect(report.attempts.first.stage, ResolveStage.resolution);
    expect(report.toUserMessage(), contains('youTube'));
  });

  test('all failing returns null and full chain', () async {
    final a = FakeResolver(MediaProvider.youTube, goodOf(MediaProvider.youTube),
        failTimes: 5);
    final b = FakeResolver(MediaProvider.piped, goodOf(MediaProvider.piped),
        failTimes: 5);
    final s = ResolverStrategy([a, b]);
    final report = PlaybackReport('T');
    expect(await s.resolveFirstValid(song, report), isNull);
    expect(report.attempts.length, 2);
    expect(report.allRetryable, isTrue);
  });

  test('repeated provider-level failures cool down, then bypass recovers',
      () async {
    final a = FakeResolver(MediaProvider.youTube, goodOf(MediaProvider.youTube),
        failTimes: 99, failScope: FailureScope.provider);
    final b = FakeResolver(MediaProvider.piped, goodOf(MediaProvider.piped),
        failTimes: 99, failScope: FailureScope.provider);
    final s = ResolverStrategy([a, b]);
    // Three passes: both fail provider-scoped each time (3 strikes).
    await s.resolveFirstValid(song, PlaybackReport('T'));
    await s.resolveFirstValid(song, PlaybackReport('T'));
    await s.resolveFirstValid(song, PlaybackReport('T'));
    expect(a.resolveCalls, 3);
    // Fourth pass: both cooling, but bypass attempts anyway — never an
    // instant triple-skip. Resolve is still called.
    final report = PlaybackReport('T');
    await s.resolveFirstValid(song, report);
    expect(a.resolveCalls, 4);
    expect(
        report.attempts.any((f) => f.detail.contains('bypassed')), isTrue);
  });

  test('resolve budget enforced per provider', () async {
    final slow = _SlowResolver();
    final fast =
        FakeResolver(MediaProvider.piped, goodOf(MediaProvider.piped));
    final s = ResolverStrategy([slow, fast]);
    final got = await s.resolveFirstValid(song, PlaybackReport('T'));
    expect(got?.provider, MediaProvider.piped);
  });
}

class _SlowResolver extends MediaResolver {
  @override
  MediaProvider get provider => MediaProvider.youTube;
  @override
  Duration get resolveBudget => const Duration(milliseconds: 50);

  @override
  Future<MediaSource> resolve(Song song) async {
    await Future.delayed(const Duration(seconds: 5));
    throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.resolution,
        detail: 'too late');
  }

  @override
  Future<MediaSource> validate(MediaSource source) async => source;

  @override
  Future<void> download(MediaSource source, File file) async {}
}
