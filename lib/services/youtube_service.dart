import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/song.dart';
import '../models/playlist.dart';
import 'playlist_parser.dart';
import 'song_filter.dart';
import 'user_preferences.dart';

/// Metadata facade: search, related, playlists, trending.
/// NOTE: audio streams are NOT resolved here. All stream resolution,
/// ranking, downloading, and fallback live behind [MediaResolver]
/// implementations in lib/media/providers/ (YouTube/Piped/Saavn).
/// If YouTube changes InnerTube tomorrow, only YouTubeProvider changes.
class YouTubeService {
  static const _timeout = Duration(seconds: 35);
  final YoutubeExplode _yt = YoutubeExplode();
  final PlaylistParser _parser = PlaylistParser();

  Song _toSong(Video video) {
    return Song(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration ?? Duration.zero,
      videoId: video.id.value,
      channel: video.author,
    );
  }

  Future<List<Song>> search(String query, {int limit = 20}) async {
    // Uses searchContent (raw SearchResult union) instead of search():
    // search() eagerly maps every item to Video and throws away the whole
    // batch on one unparsable renderer (live/"Streamed" results crash it
    // with NoSuchMethodError inside the library). Filtering to SearchVideo
    // + per-item guards keeps one bad item from killing music search.
    try {
      final content = await _yt.search
          .searchContent(query, filter: TypeFilters.video)
          .timeout(_timeout);
      final songs = <Song>[];
      for (final item in content) {
        if (songs.length >= limit) break;
        if (item is! SearchVideo) continue;
        try {
          songs.add(songFromSearchVideo(item));
        } catch (_) {
          continue;
        }
      }
      return songs;
    } catch (e) {
      // Diagnostic only (debug builds): record the ACTUAL provider error
      // (timeout, throttling/bot-check, network) instead of collapsing it.
      // No credentials or keys exist in this call to leak.
      if (kDebugMode) {
        // ignore: avoid_print
        print('ATLAS-SEARCH fail query="${query.length > 60 ? query.substring(0, 60) : query}" '
            '${e.runtimeType}: $e');
      }
      throw Exception('Search failed: $e');
    }
  }

  /// Maps raw search results defensively. Static for unit tests.
  static Song songFromSearchVideo(SearchVideo v) {
    String thumb = 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg';
    try {
      if (v.thumbnails.isNotEmpty) {
        final best = v.thumbnails.reduce(
            (a, b) => a.width * a.height >= b.width * b.height ? a : b);
        thumb = best.url.toString();
      }
    } catch (_) {}
    return Song(
      id: v.id.value,
      title: v.title,
      artist: v.author,
      thumbnailUrl: thumb,
      duration: parseDurationString(v.duration),
      videoId: v.id.value,
      channel: v.author,
    );
  }

  /// Parses "HH:MM:SS" / "MM:SS". Anything else (live, empty) → zero.
  /// Static for unit tests.
  static Duration parseDurationString(String text) {
    try {
      final parts =
          text.split(':').map((p) => int.parse(p.trim())).toList();
      if (parts.length == 3) {
        return Duration(
            hours: parts[0], minutes: parts[1], seconds: parts[2]);
      }
      if (parts.length == 2) {
        return Duration(minutes: parts[0], seconds: parts[1]);
      }
      if (parts.length == 1) return Duration(seconds: parts[0]);
    } catch (_) {}
    return Duration.zero;
  }

  Future<List<Song>> getRelatedVideos(String videoId, {int limit = 15}) async {
    try {
      final video =
          await _yt.videos.get(VideoId(videoId)).timeout(_timeout);
      final related = await _yt.videos
          .getRelatedVideos(video)
          .timeout(_timeout);

      if (related == null) return [];
      return related.take(limit).map(_toSong).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Playlist> getPlaylist(String playlistId) async {
    // Metadata via library (still works), songs via custom parser because
    // YouTube replaced playlistVideoRenderer with lockupViewModel items.
    String name = 'Imported Playlist';
    String? description;
    try {
      final meta =
          await _yt.playlists.get(playlistId).timeout(_timeout);
      name = meta.title;
      description = meta.description;
    } catch (_) {
      // Keep defaults, songs matter most.
    }

    List<Song> songs = [];
    try {
      songs = await _parser.fetchVideos(playlistId);
    } catch (e) {
      throw Exception('Failed to read playlist songs: $e');
    }

    // GLOBAL rules: imported playlists keep only 00:45–07:00 tracks in
    // the selected language. Stored user data is filtered at display;
    // imports comply from the start.
    if (songs.isNotEmpty) {
      try {
        final lang = await UserPreferences().getLanguage();
        songs = SongFilter.apply(songs, language: lang);
      } catch (_) {}
    }

    if (songs.isEmpty) {
      throw Exception('No playable songs found in this playlist');
    }

    return Playlist(
      id: playlistId,
      name: name,
      description: description,
      thumbnailUrl: songs.first.thumbnailUrl,
      songs: songs,
      createdAt: DateTime.now(),
      source: 'youtube',
    );
  }

  Future<List<Song>> getTrending({int limit = 20}) async {
    try {
      return await search('top music hits global', limit: limit);
    } catch (e) {
      throw Exception('Failed to get trending: $e');
    }
  }

  void dispose() {
    _yt.close();
  }
}
