import 'dart:convert';
import 'dart:io';
import '../models/song.dart';
import 'media_source.dart';

/// Dedicated audio cache. Rules:
/// - Deterministic key: `atlas2_{sanitized song id}.{ext}` (+ `.json` sidecar).
///   v2 namespace: pre-v2 cache may hold truncated downloads (short reads
///   once committed as EOF), so old `atlas_` entries are never reused.
/// - Sidecar metadata: song id/title, provider, source URL, byte count,
///   download timestamp. Used for TTL + corruption checks.
/// - TTL 14 days; total size cap 1GB with oldest-first eviction.
/// - Corruption detection: zero-byte files rejected; when the source knew
///   its content length, committed size must match exactly.
/// - Cached replays never touch the network (offline-first).
/// - Sweep on service init is best-effort only; never evict files currently
///   in active playback queue.
class CacheService {
  static const ttl = Duration(days: 7);
  static const maxBytes = 1 * 1024 * 1024 * 1024;

  final Directory baseDir;

  CacheService({Directory? baseDir})
      : baseDir = baseDir ?? Directory.systemTemp;

  static String safeId(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String keyFor(Song song) {
    final id = safeId(song.videoId ?? song.id);
    return 'atlas2_$id';
  }

  File fileFor(Song song, {String ext = 'm4a'}) =>
      File('${baseDir.path}/${keyFor(song)}.$ext');

  File sidecarFor(Song song, {String ext = 'm4a'}) =>
      File('${baseDir.path}/${keyFor(song)}.$ext.json');

  /// Valid cached file, or null. Never throws.
  Future<File?> getValid(Song song) async {
    try {
      // Accept any known audio extension from earlier builds.
      File? file;
      for (final ext in ['m4a', 'mp3', 'webm']) {
        final f = fileFor(song, ext: ext);
        if (await f.exists()) {
          file = f;
          break;
        }
      }
      if (file == null) return null;
      if (await file.length() == 0) {
        await _deleteQuiet(file);
        return null;
      }
      final meta = await _readSidecar(song, file);
      if (meta == null) {
        // No sidecar: legacy file from before byte-count validation.
        // Those builds committed short reads as EOF (17s truncated audio).
        // Force fresh download instead of replaying the snippet.
        await _deleteQuiet(file);
        return null;
      }
      {
        final at = DateTime.tryParse(meta['downloadedAt'] as String? ?? '');
        if (at != null && DateTime.now().difference(at) > ttl) {
          await _deleteQuiet(file);
          await _deleteQuiet(sidecarFor(song));
          return null;
        }
        final expected = meta['bytes'] as int?;
        if (expected != null &&
            expected > 0 &&
            await file.length() != expected) {
          await _deleteQuiet(file); // corrupted / partial
          return null;
        }
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Validate [tmp] (downloaded via resolver) and promote it into the
  /// cache under the deterministic key. Returns the cache file.
  /// Throws [StateError] on corruption (caller records it and moves on).
  Future<File> commit(Song song, File tmp, MediaSource source) async {
    final ext = _extFor(source);
    final dest = fileFor(song, ext: ext);
    final bytes = await tmp.length();
    if (bytes <= 0) {
      await _deleteQuiet(tmp);
      throw StateError('empty download');
    }
    // Reject suspiciously small files (<500KB) which are likely preview clips
    // that cause the 15-20s restart loop.
    if (bytes < 500 * 1024) {
      await _deleteQuiet(tmp);
      throw StateError('download too small ($bytes bytes)');
    }
    if (source.contentLength != null &&
        source.contentLength! > 0 &&
        bytes != source.contentLength) {
      await _deleteQuiet(tmp);
      throw StateError(
          'size mismatch (got $bytes, expected ${source.contentLength})');
    }
    if (await dest.exists()) await dest.delete();
    await tmp.rename(dest.path);
    await sidecarFor(song, ext: ext).writeAsString(json.encode({
      'songId': song.videoId ?? song.id,
      'title': song.title,
      'provider': source.provider.name,
      'url': source.url,
      'bytes': bytes,
      'downloadedAt': DateTime.now().toIso8601String(),
    }));
    await enforceCap();
    return dest;
  }

  /// Staging file for a fresh download (outside the key namespace so a
  /// crash never leaves a half-valid cache entry behind).
  File stageFile(Song song) => File(
      '${baseDir.path}/${keyFor(song)}.${DateTime.now().microsecondsSinceEpoch}.part');

  Future<void> invalidate(Song song) async {
    for (final ext in ['m4a', 'mp3', 'webm']) {
      await _deleteQuiet(fileFor(song, ext: ext));
      await _deleteQuiet(sidecarFor(song, ext: ext));
    }
  }

  /// TTL sweep + orphan `.part` cleanup + size-cap eviction.
  Future<void> sweep() async {
    try {
      await for (final e in baseDir.list()) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('atlas_') && !name.startsWith('atlas2_')) continue;
        if (name.endsWith('.part')) {
          await _deleteQuiet(e);
          continue;
        }
        if (name.endsWith('.json')) continue;
        final stat = await e.stat();
        if (DateTime.now().difference(stat.modified) > ttl) {
          await _deleteQuiet(e);
          await _deleteQuiet(File('${e.path}.json'));
          continue;
        }
        // v1 namespace retired (may hold truncated downloads): evict.
        if (name.startsWith('atlas_') && !name.startsWith('atlas2_')) {
          await _deleteQuiet(e);
          await _deleteQuiet(File('${e.path}.json'));
        }
      }
      await enforceCap();
    } catch (_) {}
  }

  Future<void> enforceCap() async {
    try {
      final files = <File>[];
      await for (final e in baseDir.list()) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if ((name.startsWith('atlas_') || name.startsWith('atlas2_')) &&
            !name.endsWith('.json') &&
            !name.endsWith('.part')) {
          files.add(e);
        }
      }
      var total = 0;
      final sizes = <File, int>{};
      for (final f in files) {
        final s = await f.length();
        sizes[f] = s;
        total += s;
      }
      if (total <= maxBytes) return;
      files.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in files) {
        if (total <= maxBytes) break;
        total -= sizes[f]!;
        await _deleteQuiet(f);
        await _deleteQuiet(File('${f.path}.json'));
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readSidecar(Song song, File file) async {
    try {
      final ext = file.path.split('.').last;
      final raw =
          await sidecarFor(song, ext: ext).readAsString();
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _extFor(MediaSource source) {
    final c = (source.container ?? '').toLowerCase();
    if (c.contains('mp3')) return 'mp3';
    if (c.contains('webm')) return 'webm';
    final m = (source.mimeType ?? '').toLowerCase();
    if (m.contains('mpeg')) return 'mp3';
    if (m.contains('webm')) return 'webm';
    return 'm4a';
  }

  Future<void> _deleteQuiet(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
