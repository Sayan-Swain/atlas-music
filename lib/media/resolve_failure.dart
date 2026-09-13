import 'media_source.dart';

/// Pipeline stage where a failure happened. Never guesses: the provider
/// that hit the error reports the stage it was in.
enum ResolveStage {
  resolution,
  validation,
  stream,
  download,
  playback,
}

/// Scope of a failure. Cooldowns key off this:
/// - url: one specific stream URL (expired/throttled) → discard URL, retry.
/// - song: this song/provider combination (no match, unavailable) →
///   never cools the provider; next song attempts fresh.
/// - instance: one Piped backend host → skip that host, try siblings.
/// - provider: the backend itself is unreachable → counts toward cooldown.
enum FailureScope { url, song, instance, provider }

/// Structured failure. Original error text is preserved verbatim in
/// [detail]; nothing is swallowed or summarized away.
class ResolveFailure {
  final MediaProvider? provider;
  final ResolveStage stage;
  final FailureScope scope;
  final String detail;
  final int? httpStatus;
  final bool retryable;
  final String? backend;
  final DateTime timestamp;

  ResolveFailure({
    required this.provider,
    required this.stage,
    required this.detail,
    this.scope = FailureScope.song,
    this.httpStatus,
    this.retryable = true,
    this.backend,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final who = provider != null ? provider!.name : 'app';
    final where = backend != null ? ' $backend' : '';
    final http = httpStatus != null ? ' HTTP $httpStatus' : '';
    return '[$who/${scope.name} ${stage.name}$http$where] $detail';
  }
}

/// Collects every provider attempt of one user-visible play operation and
/// renders a single human-readable error that keeps the full chain.
class PlaybackReport {
  final String songTitle;
  final String? songId;
  final List<ResolveFailure> attempts = [];

  PlaybackReport(this.songTitle, {this.songId});

  void add(ResolveFailure f) => attempts.add(f);

  bool get allRetryable =>
      attempts.isNotEmpty && attempts.every((a) => a.retryable);

  /// Full chain for logs / bug reports.
  String toVerboseString() =>
      attempts.map((a) => a.toString()).join(' | ');

  /// Compact message for the error dialog. Keeps HTTP statuses — a
  /// "rejected" without its status code is undiagnosable.
  String toUserMessage() {
    if (attempts.isEmpty) return 'No providers attempted for "$songTitle".';
    final parts = attempts
        .map((a) {
          var d = a.detail.replaceAll(RegExp(r'\s+'), ' ');
          if (d.length > 200) d = '${d.substring(0, 200)}…';
          final http = a.httpStatus != null ? ' HTTP ${a.httpStatus}' : '';
          return '${a.provider?.name ?? '?'}: $d$http';
        })
        .join(' | ');
    return 'Could not play "$songTitle". $parts';
  }
}
