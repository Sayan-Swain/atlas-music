import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../../models/song.dart';
import 'media_source.dart';
import 'media_resolver.dart';
import 'resolve_failure.dart';

/// Finite provider chain: CACHE is checked by the caller, then providers
/// are tried strictly in order — P1 → P2 → … → FAIL. No recursion, no
/// re-entry: one pass, every attempt recorded in [PlaybackReport].
///
/// Cooldown rules (failure scopes):
/// - url/song failures NEVER cool a provider. A dead URL for Song A says
///   nothing about Song B; "no match" for one song says nothing about
///   the next.
/// - Only provider-scoped failures (backend unreachable, transport
///   errors) count, and only 3 CONSECUTIVE ones put a provider on
///   cooldown (2min doubling, 15min cap). Any success resets.
/// - If every provider is cooling down, cooldowns are bypassed and all
///   are attempted fresh — there is always a path to try the next song.
///   Song A's failure is never inherited as Song B's failure.
class ResolverStrategy {
  static const _validateBudget = Duration(seconds: 20);
  static const _cooldownStrikes = 3;

  final List<MediaResolver> providers;

  final Map<MediaProvider, int> _strikes = {};
  final Map<MediaProvider, DateTime> _cooldownUntil = {};

  ResolverStrategy(this.providers);

  bool isAvailable(MediaResolver p) {
    final until = _cooldownUntil[p.provider];
    return until == null || DateTime.now().isAfter(until);
  }

  String describeCooldowns() {
    final now = DateTime.now();
    final parts = <String>[];
    for (final p in providers) {
      final until = _cooldownUntil[p.provider];
      if (until != null && now.isBefore(until)) {
        parts.add(
            '${p.provider.name}: ${_strikes[p.provider] ?? 0} strikes, '
            'cools until $until');
      }
    }
    return parts.isEmpty ? 'none' : parts.join('; ');
  }

  void recordSuccess(MediaResolver p) {
    _strikes.remove(p.provider);
    _cooldownUntil.remove(p.provider);
  }

  /// Only provider-scoped failures count toward cooldown, and only the
  /// third consecutive strike activates it.
  void recordFailure(MediaResolver p, FailureScope scope) {
    if (scope != FailureScope.provider) return;
    final n = (_strikes[p.provider] ?? 0) + 1;
    _strikes[p.provider] = n;
    if (n >= _cooldownStrikes) {
      final minutes = (2 * (1 << (n - _cooldownStrikes))).clamp(2, 15);
      _cooldownUntil[p.provider] =
          DateTime.now().add(Duration(minutes: minutes));
    }
  }

  List<MediaResolver> _attemptList(PlaybackReport report) {
    final available = providers.where(isAvailable).toList();
    if (available.isNotEmpty) return available;
    // All cooling down: bypass and attempt everything fresh. A new song
    // always gets a real attempt, never an instant triple-skip.
    report.add(ResolveFailure(
      provider: null,
      stage: ResolveStage.resolution,
      scope: FailureScope.provider,
      detail: 'cooldowns bypassed for fresh attempt '
          '(${describeCooldowns()})',
      retryable: true,
    ));
    return providers.toList();
  }

  /// Shared resolve→validate for one provider. On a url-scoped validation
  /// failure (expired/throttled URL), discards the URL, resolves fresh
  /// once, and retries validation once — without touching cooldowns.
  /// Transport timeouts get one jittered retry: a single slow response
  /// is not a dead backend.
  Future<MediaSource?> _resolveValidated(
    MediaResolver p,
    Song song,
    PlaybackReport report,
  ) async {
    MediaSource candidate;
    try {
      candidate = await p.resolve(song).timeout(p.resolveBudget);
    } on ResolveFailure catch (e) {
      report.add(e);
      recordFailure(p, e.scope);
      return null;
    } on TimeoutException catch (e) {
      // One retry after 0.5–1.5s jitter. Thundering-herd avoidance for
      // throttled networks; still bounded and fast.
      await Future.delayed(
          Duration(milliseconds: 500 + Random().nextInt(1000)));
      try {
        candidate = await p.resolve(song).timeout(p.resolveBudget);
        report.add(ResolveFailure(
          provider: p.provider,
          stage: ResolveStage.resolution,
          scope: FailureScope.provider,
          detail: 'first attempt timed out, retrying once',
          retryable: true,
        ));
      } on ResolveFailure catch (e2) {
        report.add(e2);
        recordFailure(p, e2.scope);
        return null;
      } on TimeoutException catch (e2) {
        final f = ResolveFailure(
          provider: p.provider,
          stage: ResolveStage.resolution,
          scope: FailureScope.provider,
          detail: 'resolve exceeded ${p.resolveBudget.inSeconds}s twice: $e2',
          retryable: true,
        );
        report.add(f);
        recordFailure(p, f.scope);
        return null;
      } catch (e2) {
        final f = ResolveFailure(
          provider: p.provider,
          stage: ResolveStage.resolution,
          scope: FailureScope.provider,
          detail: 'retry unexpected: $e2 (first: $e)',
          retryable: false,
        );
        report.add(f);
        recordFailure(p, f.scope);
        return null;
      }
    } catch (e) {
      final f = ResolveFailure(
        provider: p.provider,
        stage: ResolveStage.resolution,
        scope: FailureScope.provider,
        detail: 'unexpected: $e',
        retryable: false,
      );
      report.add(f);
      recordFailure(p, f.scope);
      return null;
    }
    try {
      final valid =
          await p.validate(candidate).timeout(_validateBudget);
      recordSuccess(p);
      return valid;
    } on ResolveFailure catch (e) {
      report.add(e);
      if (e.scope == FailureScope.url) {
        // One expired URL ≠ dead provider. Fresh resolve, one retry.
        try {
          final fresh =
              await p.resolve(song).timeout(p.resolveBudget);
          final valid =
              await p.validate(fresh).timeout(_validateBudget);
          recordSuccess(p);
          return valid;
        } on ResolveFailure catch (e2) {
          report.add(e2);
          recordFailure(p, e2.scope);
        } catch (e2) {
          final f = ResolveFailure(
            provider: p.provider,
            stage: ResolveStage.validation,
            scope: FailureScope.provider,
            detail: 'fresh-retry unexpected: $e2',
            retryable: false,
          );
          report.add(f);
          recordFailure(p, f.scope);
        }
        return null;
      }
      recordFailure(p, e.scope);
      return null;
    } on TimeoutException catch (e) {
      final f = ResolveFailure(
        provider: p.provider,
        stage: ResolveStage.validation,
        scope: FailureScope.provider,
        detail: 'validation exceeded 20s: $e',
        retryable: true,
      );
      report.add(f);
      recordFailure(p, f.scope);
      return null;
    } catch (e) {
      final f = ResolveFailure(
        provider: p.provider,
        stage: ResolveStage.validation,
        scope: FailureScope.provider,
        detail: 'unexpected: $e',
        retryable: false,
      );
      report.add(f);
      recordFailure(p, f.scope);
      return null;
    }
  }

  /// First resolve()+validate() success in provider order, or null.
  /// Every failure lands in [report] with provider + stage + scope.
  Future<MediaSource?> resolveFirstValid(
      Song song, PlaybackReport report) async {
    for (final p in _attemptList(report)) {
      final got = await _resolveValidated(p, song, report);
      if (got != null) return got;
    }
    return null;
  }

  /// Resolve-then-download through the same provider order into [file].
  /// Returns the source that produced the file, or null (see [report]).
  Future<MediaSource?> downloadFirstValid(
    Song song,
    File file,
    PlaybackReport report, {
    Duration budget = const Duration(seconds: 150),
  }) async {
    for (final p in _attemptList(report)) {
      final candidate = await _resolveValidated(p, song, report);
      if (candidate == null) continue;
      try {
        await p.download(candidate, file).timeout(budget);
        if (await file.exists() && await file.length() > 0) {
          recordSuccess(p);
          return candidate;
        }
        report.add(ResolveFailure(
          provider: p.provider,
          stage: ResolveStage.download,
          scope: FailureScope.url,
          detail: 'download produced empty file',
          retryable: true,
        ));
      } on ResolveFailure catch (e) {
        report.add(e);
        recordFailure(p, e.scope);
      } catch (e) {
        final f = ResolveFailure(
          provider: p.provider,
          stage: ResolveStage.download,
          scope: FailureScope.provider,
          detail: 'unexpected: $e',
          retryable: false,
        );
        report.add(f);
        recordFailure(p, f.scope);
      }
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    return null;
  }
}
