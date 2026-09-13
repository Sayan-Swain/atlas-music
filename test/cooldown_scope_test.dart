import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_music/media/media_resolver.dart';
import 'package:atlas_music/media/media_source.dart';
import 'package:atlas_music/media/resolve_failure.dart';
import 'package:atlas_music/media/resolver_strategy.dart';
import 'package:atlas_music/models/song.dart';

/// Exact regression test for the reported bug: Song A fails on every
/// provider, then Song B must still get a fresh YouTube attempt instead
/// of an instant triple "cooling down" skip.

Song songOf(String id) => Song(
      id: id,
      title: 'Title $id',
      artist: 'Artist',
      thumbnailUrl: '',
      duration: Duration.zero,
      videoId: id,
    );

MediaSource goodOf(MediaProvider p, String tag) => MediaSource(
      provider: p,
      url: 'https://$p/$tag',
      mimeType: 'audio/mp4',
      codec: 'mp4a.40.2',
      container: 'mp4',
      resolvedAt: DateTime.now(),
    );

/// Fails song-scoped (like "video unavailable" / "no match") for the
/// configured song ids, succeeds otherwise.
class SongScopedFlaky extends MediaResolver {
  @override
  final MediaProvider provider;
  @override
  final Duration resolveBudget = const Duration(seconds: 2);
  final Set<String> deadSongs;
  int resolveCalls = 0;

  SongScopedFlaky(this.provider, {Set<String> deadSongs = const {}})
      : deadSongs = Set.of(deadSongs);

  @override
  Future<MediaSource> resolve(Song song) async {
    resolveCalls++;
    if (deadSongs.contains(song.videoId ?? song.id)) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.resolution,
        scope: FailureScope.song,
        detail: 'scripted song-level failure',
      );
    }
    return goodOf(provider, song.videoId ?? song.id);
  }

  @override
  Future<MediaSource> validate(MediaSource source) async => source;

  @override
  Future<void> download(MediaSource source, File file) async {
    await file.writeAsString('bytes');
  }
}

/// First validation of each resolve fails url-scoped (expired URL),
/// then behaves normally — models one dead URL, not a dead provider.
class OneDeadUrl extends MediaResolver {
  @override
  MediaProvider get provider => MediaProvider.youTube;
  @override
  final Duration resolveBudget = const Duration(seconds: 2);
  int resolves = 0;
  int validates = 0;

  @override
  Future<MediaSource> resolve(Song song) async {
    resolves++;
    return goodOf(provider, 'attempt-$resolves');
  }

  @override
  Future<MediaSource> validate(MediaSource source) async {
    validates++;
    if (validates == 1) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.url,
        detail: 'googlevideo rejected HEAD (throttled/expired URL)',
        httpStatus: 403,
      );
    }
    return source;
  }

  @override
  Future<void> download(MediaSource source, File file) async {
    await file.writeAsString('bytes');
  }
}

/// First resolve hangs past budget (transport stall), second succeeds.
class TimeoutOnce extends MediaResolver {
  @override
  MediaProvider get provider => MediaProvider.youTube;
  @override
  final Duration resolveBudget = const Duration(milliseconds: 100);
  int calls = 0;

  @override
  Future<MediaSource> resolve(Song song) async {
    calls++;
    if (calls == 1) {
      await Future.delayed(const Duration(seconds: 5));
    }
    return goodOf(provider, song.videoId ?? song.id);
  }

  @override
  Future<MediaSource> validate(MediaSource source) async => source;

  @override
  Future<void> download(MediaSource source, File file) async {
    await file.writeAsString('bytes');
  }
}

void main() {
  test('Song A total failure does not block Song B (the reported bug)',
      () async {
    final yt = SongScopedFlaky(MediaProvider.youTube, deadSongs: {'A'});
    final piped =
        SongScopedFlaky(MediaProvider.piped, deadSongs: {'A'});
    final saavn =
        SongScopedFlaky(MediaProvider.saavn, deadSongs: {'A'});
    final s = ResolverStrategy([yt, piped, saavn]);

    // Song A: all three fail song-scoped.
    final repA = PlaybackReport('Title A', songId: 'A');
    expect(await s.resolveFirstValid(songOf('A'), repA), isNull);
    expect(repA.attempts.length, 3);
    expect(
        repA.attempts.any((f) => f.detail.contains('cooling down')), isFalse);

    // Song B: YouTube must be attempted fresh (resolve called again),
    // and must win as first healthy provider.
    final repB = PlaybackReport('Title B', songId: 'B');
    final got = await s.resolveFirstValid(songOf('B'), repB);
    expect(got?.provider, MediaProvider.youTube);
    expect(yt.resolveCalls, 2);
    expect(
        repB.attempts.any((f) => f.detail.contains('cooling down')), isFalse);
  });

  test('song-scoped failures never cool any provider, however many',
      () async {
    final yt = SongScopedFlaky(MediaProvider.youTube,
        deadSongs: {'1', '2', '3', '4', '5'});
    final s = ResolverStrategy([yt]);
    for (final id in ['1', '2', '3', '4', '5']) {
      await s.resolveFirstValid(songOf(id), PlaybackReport('t'));
    }
    expect(yt.resolveCalls, 5);
    expect(s.isAvailable(yt), isTrue);
  });

  test('one dead URL triggers a single fresh re-resolve, no cooldown',
      () async {
    final yt = OneDeadUrl();
    final s = ResolverStrategy([yt]);
    final report = PlaybackReport('t');
    final got = await s.resolveFirstValid(songOf('B'), report);
    expect(got, isNotNull);
    expect(yt.resolves, 2); // initial + one fresh retry
    expect(s.isAvailable(yt), isTrue);
    expect(report.attempts.first.scope, FailureScope.url);
  });

  test('single transport stall gets one jittered retry, no cooldown',
      () async {
    final yt = TimeoutOnce();
    final s = ResolverStrategy([yt]);
    final report = PlaybackReport('t');
    final got = await s.resolveFirstValid(songOf('B'), report);
    expect(got, isNotNull);
    expect(yt.calls, 2);
    expect(s.isAvailable(yt), isTrue);
  });

  test('failure records carry scope + song identity', () async {
    final yt = SongScopedFlaky(MediaProvider.youTube, deadSongs: {'A'});
    final s = ResolverStrategy([yt]);
    final report = PlaybackReport('Title A', songId: 'A');
    await s.resolveFirstValid(songOf('A'), report);
    expect(report.songId, 'A');
    expect(report.attempts.single.scope, FailureScope.song);
    expect(report.toVerboseString(), contains('/song '));
  });
}
