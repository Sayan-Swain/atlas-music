import 'dart:io';
import '../models/song.dart';
import 'media_source.dart';
import 'resolve_failure.dart';

/// Contract every music backend implements. AudioService programs against
/// this interface only and never imports provider-specific packages.
///
/// Flow per provider: [resolve] → [validate] → hand to ExoPlayer, or
/// [download] for the offline path. All errors are [ResolveFailure]
/// (structured); anything else thrown is a bug.
abstract class MediaResolver {
  MediaProvider get provider;

  /// Wall-clock budget for [resolve]. Strategy enforces it.
  Duration get resolveBudget;

  /// Turn a [Song] into a candidate [MediaSource].
  /// Throws [ResolveFailure] with stage [ResolveStage.resolution].
  Future<MediaSource> resolve(Song song);

  /// Prove a candidate is actually playable: HTTP reachability,
  /// non-zero length, unexpired, compatible container.
  /// Returns the (possibly enriched) source or throws [ResolveFailure]
  /// with stage [ResolveStage.validation].
  Future<MediaSource> validate(MediaSource source);

  /// Fetch [source] to [file] for offline playback. Same abstraction as
  /// streaming: no duplicated provider logic in the caller.
  /// Throws [ResolveFailure] with stage [ResolveStage.download].
  Future<void> download(MediaSource source, File file);

  /// Shared guard used by all providers before returning a source.
  /// Expired URLs are url-scoped (a fresh resolve fixes them);
  /// incompatible/empty sources are song-scoped and never retryable.
  void checkCompatible(MediaSource source) {
    if (source.url.isEmpty) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.song,
        detail: 'empty URL',
        retryable: false,
      );
    }
    if (source.isExpired) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.url,
        detail: 'URL expired at ${source.expiresAt}',
        retryable: true,
      );
    }
    if (!source.hasCompatibleContainer) {
      throw ResolveFailure(
        provider: provider,
        stage: ResolveStage.validation,
        scope: FailureScope.song,
        detail: 'incompatible container/codec '
            '(container=${source.container}, codec=${source.codec}, '
            'mime=${source.mimeType})',
        retryable: false,
      );
    }
  }
}
