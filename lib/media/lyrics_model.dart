/// Synced-lyrics value objects. Pure Dart, fully unit-tested.
/// LRC format: `[mm:ss.xx] text`, one or more tags per line.
class LyricLine {
  final Duration start;
  final String text;

  const LyricLine({required this.start, required this.text});
}

class SyncedLyrics {
  final String track;
  final String artist;
  final List<LyricLine> lines;
  final bool isSynced;
  final bool instrumental;
  final String? plain;

  const SyncedLyrics({
    required this.track,
    required this.artist,
    required this.lines,
    required this.isSynced,
    this.instrumental = false,
    this.plain,
  });

  /// Index of the last line whose start is at or before [position].
  /// Returns 0 when empty so callers never clamp.
  int indexFor(Duration position) {
    if (lines.isEmpty) return 0;
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].start <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }
}

/// Parses an LRC string into sorted lines. Ignores metadata tags
/// ([ti:]/[ar:]/[al:]/[length:]/[by:]), expands multiple timestamps
/// on one line into separate entries, drops empty texts.
List<LyricLine> parseLrc(String lrc) {
  final out = <LyricLine>[];
  final tag = RegExp(r'\[(\d+):(\d+(?:[.:]\d+)?)\]');
  for (final raw in lrc.split('\n')) {
    final matches = tag.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    var text = raw.replaceAll(tag, '').trim();
    // Skip metadata lines like "[ti:Title]" (non-numeric handled
    // by regex already) and empty lyric bodies.
    if (text.isEmpty) continue;
    // Strip inline metadata remnants.
    if (text.startsWith('ti:') ||
        text.startsWith('ar:') ||
        text.startsWith('al:') ||
        text.startsWith('length:') ||
        text.startsWith('by:')) {
      continue;
    }
    for (final m in matches) {
      final min = int.tryParse(m.group(1) ?? '') ?? 0;
      final secRaw = (m.group(2) ?? '0').replaceAll('.', ':');
      double sec = 0;
      if (secRaw.contains(':')) {
        final parts = secRaw.split(':');
        sec = (double.tryParse(parts[0]) ?? 0) +
            (double.tryParse('0.${parts.length > 1 ? parts[1] : 0}') ?? 0);
      } else {
        sec = double.tryParse(secRaw) ?? 0;
      }
      final ms = ((min * 60 + sec) * 1000).round();
      if (ms < 0) continue;
      out.add(LyricLine(
        start: Duration(milliseconds: ms),
        text: text,
      ));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
