/// Which backend produced a [MediaSource]. UI/player never branches on this;
/// it exists for diagnostics, ranking, and health tracking only.
enum MediaProvider { youTube, piped, saavn }

/// A normalized, playable-or-downloadable audio stream.
/// Providers return this; [AudioPlayerService] only understands this.
class MediaSource {
  final MediaProvider provider;

  /// Direct (or proxied) playable URL.
  final String url;

  /// e.g. 'audio/mp4', 'audio/webm', 'audio/mpeg'.
  final String? mimeType;

  /// Codec string, e.g. 'mp4a.40.2', 'opus'.
  final String? codec;

  /// Container, e.g. 'mp4', 'webm', 'mp3'.
  final String? container;

  /// Bits per second, if known.
  final int? bitrate;

  /// Full content length in bytes, if known.
  final int? contentLength;

  /// True when the URL is a proxy (Piped/Saavn CDN), i.e. plain-GET
  /// semantics instead of googlevideo range semantics.
  final bool isProxy;

  /// When the URL is known to stop working (googlevideo `expire` param).
  final DateTime? expiresAt;

  /// Opaque provider-side identifier for re-resolution (e.g. YouTube
  /// video ID). Lets a provider fetch alternate URLs without new API.
  final String? mediaId;

  final DateTime resolvedAt;

  const MediaSource({
    required this.provider,
    required this.url,
    this.mimeType,
    this.codec,
    this.container,
    this.bitrate,
    this.contentLength,
    this.isProxy = false,
    this.expiresAt,
    this.mediaId,
    required this.resolvedAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// ExoPlayer on Android reliably handles MP4/AAC and WebM/Opus audio,
  /// plus plain MP3. Anything else is rejected before playback.
  bool get hasCompatibleContainer {
    final c = (container ?? '').toLowerCase();
    final m = (mimeType ?? '').toLowerCase();
    if (c.contains('mp4') || c.contains('m4a') || c.contains('mp3')) {
      return true;
    }
    if (c.contains('webm') || m.contains('webm') || m.contains('opus')) {
      return true;
    }
    if (m.contains('audio/mp4') || m.contains('audio/mpeg')) return true;
    // Unknown container: allow only if codec is a known-good audio codec.
    final k = (codec ?? '').toLowerCase();
    return k.contains('mp4a') || k == 'opus' || k.contains('mp3');
  }

  @override
  String toString() =>
      'MediaSource($provider, $container/$codec, ${bitrate ?? '?'}bps, '
      'len=${contentLength ?? '?'}, proxy=$isProxy)';
}
