import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'song_filter.dart';
import 'user_preferences.dart';

class StorageService extends ChangeNotifier {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();
  factory StorageService() => instance;
  static const String _playlistsKey = 'playlists';
  static const String _likedSongsKey = 'liked_songs';
  static const String _recentlyPlayedKey = 'recently_played';
  static const String _listeningStatsKey = 'listening_stats';
  static const String _topArtistsKey = 'top_artists';
  static const String _topGenresKey = 'top_genres';
  static const String _searchHistoryKey = 'search_history';
  static const String _downloadedSongsKey = 'downloaded_songs';
  static const String downloadedPlaylistId = 'downloaded_music';

  // ── Playlists ──

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_playlistsKey);
    if (jsonString == null) return [];
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => Playlist.fromJson(j)).toList();
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlist.id);
    if (index >= 0) {
      playlists[index] = playlist;
    } else {
      playlists.add(playlist);
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonList = playlists.map((p) => p.toJson()).toList();
    await prefs.setString(_playlistsKey, json.encode(jsonList));
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    final playlists = await getPlaylists();
    Playlist? target;
    for (final p in playlists) {
      if (p.id == playlistId) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    // System Downloaded Music is managed via deleteDownloadedPlaylist().
    if (target.id == downloadedPlaylistId) return;
    // Protected while it still holds offline content. Must be cleared via
    // Offline Content first. Once downloadedSongIds is empty and
    // isDownloaded is false, it behaves normally again (deletable), even
    // if a stale isSystemManaged flag lingered from an older build.
    if (target.isDownloaded || target.downloadedSongIds.isNotEmpty) return;
    playlists.removeWhere((p) => p.id == playlistId);
    final prefs = await SharedPreferences.getInstance();
    final jsonList = playlists.map((p) => p.toJson()).toList();
    await prefs.setString(_playlistsKey, json.encode(jsonList));
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    // GLOBAL rules: violating songs (out-of-window or wrong language)
    // cannot be added to stored playlists — strict, no exceptions.
    try {
      final lang = await UserPreferences().getLanguage();
      if (!SongFilter.inDurationWindow(song) ||
          !SongFilter.matchesLanguage(song, lang)) {
        return;
      }
    } catch (_) {}
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final p = playlists[idx];
    // Downloaded/protected playlists are read-only; manage via Offline Content.
    if (p.id == downloadedPlaylistId) return;
    if (p.isDownloaded || p.downloadedSongIds.isNotEmpty) return;
    if (p.isSystemManaged) return;
    if (p.songs.any((s) => s.id == song.id)) return;
    playlists[idx] = Playlist(
      id: p.id,
      name: p.name,
      description: p.description,
      thumbnailUrl: p.thumbnailUrl,
      coverPath: p.coverPath,
      songs: [...p.songs, song],
      createdAt: p.createdAt,
      source: p.source,
      isDownloaded: p.isDownloaded,
      downloadedSongIds: p.downloadedSongIds,
      isSystemManaged: p.isSystemManaged,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey,
      json.encode(playlists.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> removeSongFromPlaylist(
      String playlistId, String songId) async {
    // System Downloaded Music has its own removal path that also cleans
    // the global downloaded list.
    if (playlistId == downloadedPlaylistId) {
      await removeSongFromDownloadedPlaylist(songId);
      return;
    }
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final p = playlists[idx];
    // Downloaded songs must be removed via Offline Content so cache +
    // flags stay in sync. Online-only songs can be removed directly.
    // Once all offline content is gone the playlist is normal again.
    if (p.isDownloaded && p.downloadedSongIds.contains(songId)) return;
    if (p.downloadedSongIds.contains(songId)) return;
    if (p.isSystemManaged && p.downloadedSongIds.isNotEmpty) return;
    playlists[idx] = Playlist(
      id: p.id,
      name: p.name,
      description: p.description,
      thumbnailUrl: p.thumbnailUrl,
      coverPath: p.coverPath,
      songs: p.songs.where((s) => s.id != songId).toList(),
      createdAt: p.createdAt,
      source: p.source,
      isSystemManaged: p.isSystemManaged,
      isDownloaded: p.isDownloaded,
      downloadedSongIds: p.downloadedSongIds,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey,
      json.encode(playlists.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> updateCover(String playlistId, String? path) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    playlists[index] = playlists[index].withCover(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey,
      json.encode(playlists.map((p) => p.toJson()).toList()),
    );
  }

  // ── Liked songs ──

  Future<List<Song>> getLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_likedSongsKey);
    if (jsonString == null) return [];
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => Song.fromJson(j)).toList();
  }

  Future<void> toggleLikedSong(Song song) async {
    final likedSongs = await getLikedSongs();
    final index = likedSongs.indexWhere((s) => s.id == song.id);
    if (index >= 0) {
      likedSongs.removeAt(index);
    } else {
      likedSongs.add(song);
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonList = likedSongs.map((s) => s.toJson()).toList();
    await prefs.setString(_likedSongsKey, json.encode(jsonList));
    // Realtime: library liked rail + profile counts listen to storage.
    notifyListeners();
  }

  Future<bool> isSongLiked(String songId) async {
    final likedSongs = await getLikedSongs();
    return likedSongs.any((s) => s.id == songId);
  }

  // ── Recently played ──

  Future<List<Song>> getRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentlyPlayedKey);
    if (jsonString == null) return [];
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => Song.fromJson(j)).toList();
  }

  Future<void> addToRecentlyPlayed(Song song) async {
    final recentlyPlayed = await getRecentlyPlayed();
    recentlyPlayed.removeWhere((s) => s.id == song.id);
    recentlyPlayed.insert(0, song);
    if (recentlyPlayed.length > 50) {
      recentlyPlayed.removeRange(50, recentlyPlayed.length);
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonList = recentlyPlayed.map((s) => s.toJson()).toList();
    await prefs.setString(_recentlyPlayedKey, json.encode(jsonList));
    // Realtime: home rail, counts, and profile stats refresh on each play.
    notifyListeners();
  }

  // ── Listening stats (for personalized recommendations) ──

  Future<Map<String, Map<String, dynamic>>> _getStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listeningStatsKey);
    if (raw == null) return {};
    final Map<String, dynamic> decoded = json.decode(raw);
    return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
  }

  Future<void> _saveStats(Map<String, Map<String, dynamic>> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listeningStatsKey, json.encode(stats));
  }

  /// Full listening stats for recommenders (Quick Picks): per song id →
  /// {playCount, skipCount, totalMs, lastPlayed, skipTimes?}.
  /// Public read-only snapshot; never mutated by callers.
  Future<Map<String, Map<String, dynamic>>> getListeningStats() async {
    return _getStats();
  }

  Future<void> recordListen(Song song,
      {required int listenedMs, required bool skipped}) async {
    final stats = await _getStats();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = stats[song.id] ??
        {
          'playCount': 0,
          'skipCount': 0,
          'totalMs': 0,
          'lastPlayed': 0,
        };
    entry['playCount'] = (entry['playCount'] as int) + 1;
    entry['totalMs'] = (entry['totalMs'] as int) + listenedMs;
    entry['lastPlayed'] = now;
    if (skipped) {
      entry['skipCount'] = (entry['skipCount'] as int) + 1;
      // Skip timestamps power time-decayed skip penalties (Quick Picks):
      // recent repeated skips weigh strongly, >90d less than half, >1yr
      // effectively ignored. Capped so the blob never grows.
      final times = ((entry['skipTimes'] as List?) ?? [])
          .whereType<int>()
          .toList();
      times.add(now);
      entry['skipTimes'] =
          times.length > 20 ? times.sublist(times.length - 20) : times;
    }
    stats[song.id] = entry;
    await _saveStats(stats);

    if (song.artist.isNotEmpty) {
      final artists = await _getTopArtists();
      artists[song.artist] = (artists[song.artist] ?? 0) + 1;
      await _saveTopArtists(artists);
    }
  }

  Future<Map<String, int>> _getTopArtists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_topArtistsKey);
    if (raw == null) return {};
    return Map<String, int>.from(json.decode(raw));
  }

  Future<void> _saveTopArtists(Map<String, int> artists) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = artists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = Map.fromEntries(sorted.take(30));
    await prefs.setString(_topArtistsKey, json.encode(top));
  }

  Future<List<String>> getTopArtists({int limit = 5}) async {
    final artists = await _getTopArtists();
    final sorted = artists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  Future<Map<String, int>> _getTopGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_topGenresKey);
    if (raw == null) return {};
    return Map<String, int>.from(json.decode(raw));
  }

  Future<void> recordGenre(String genre) async {
    if (genre.isEmpty) return;
    final genres = await _getTopGenres();
    genres[genre] = (genres[genre] ?? 0) + 1;
    final prefs = await SharedPreferences.getInstance();
    final sorted = genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = Map.fromEntries(sorted.take(10));
    await prefs.setString(_topGenresKey, json.encode(top));
  }

  Future<List<String>> getTopGenres({int limit = 3}) async {
    final genres = await _getTopGenres();
    final sorted = genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  Future<bool> hasEnoughHistory() async {
    final stats = await _getStats();
    int totalMs = 0;
    for (final v in stats.values) {
      totalMs += (v['totalMs'] as int? ?? 0);
    }
    return totalMs >= 5000;
  }

  Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_searchHistoryKey);
    return list ?? [];
  }

  Future<void> addSearchQuery(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_searchHistoryKey) ?? [];
    final q = query.trim();
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > 20) list.removeRange(20, list.length);
    await prefs.setStringList(_searchHistoryKey, list);
  }

  Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }

  Future<List<Song>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_downloadedSongsKey);
    if (jsonString == null) return [];
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => Song.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> addDownloadedSong(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_downloadedSongsKey);
    final List<Song> list = jsonString == null
        ? []
        : (json.decode(jsonString) as List)
            .map((j) => Song.fromJson(j as Map<String, dynamic>))
            .toList();
    if (!list.any((s) => s.id == song.id)) {
      list.add(song);
      await prefs.setString(_downloadedSongsKey, json.encode(list.map((s) => s.toJson()).toList()));
    }
  }

  Future<void> removeDownloadedSong(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_downloadedSongsKey);
    if (jsonString != null) {
      final List<Song> list = (json.decode(jsonString) as List)
          .map((j) => Song.fromJson(j as Map<String, dynamic>))
          .toList();
      list.removeWhere((s) => s.id == songId);
      await prefs.setString(
          _downloadedSongsKey, json.encode(list.map((s) => s.toJson()).toList()));
    }
    // Also drop it from every playlist's offline set. Online copies in
    // playlist.songs are preserved. When a playlist's offline set becomes
    // empty it is unprotected so it behaves normally again (deletable).
    final playlists = await getPlaylists();
    bool changed = false;
    for (var i = 0; i < playlists.length; i++) {
      final p = playlists[i];
      if (!p.downloadedSongIds.contains(songId)) continue;
      final nextIds = Set<String>.from(p.downloadedSongIds)..remove(songId);
      final isDl = nextIds.isNotEmpty && nextIds.length == p.songs.length;
      if (p.id == downloadedPlaylistId) {
        playlists[i] = p.copyWith(
          isDownloaded: isDl,
          downloadedSongIds: nextIds,
        );
      } else if (nextIds.isEmpty) {
        playlists[i] = p.copyWith(
          isDownloaded: false,
          downloadedSongIds: nextIds,
          isSystemManaged: false,
        );
      } else {
        playlists[i] = p.copyWith(
          isDownloaded: isDl,
          downloadedSongIds: nextIds,
        );
      }
      changed = true;
    }
    if (changed) {
      await prefs.setString(
          _playlistsKey, json.encode(playlists.map((p) => p.toJson()).toList()));
      notifyListeners();
    }
  }

  Future<Playlist> ensureDownloadedPlaylist() async {
    final playlists = await getPlaylists();
    var pl = playlists.firstWhere(
      (p) => p.id == downloadedPlaylistId,
      orElse: () => Playlist(
        id: downloadedPlaylistId,
        name: 'Downloaded Music',
        songs: [],
        createdAt: DateTime.now(),
        source: 'system',
        isSystemManaged: true,
      ),
    );
    if (!playlists.any((p) => p.id == downloadedPlaylistId)) {
      await savePlaylist(pl);
    }
    return pl;
  }

  Future<void> addSongToDownloadedPlaylist(Song song) async {
    await ensureDownloadedPlaylist();
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == downloadedPlaylistId);
    if (idx >= 0) {
      final existing = playlists[idx];
      if (!existing.songs.any((s) => s.id == song.id)) {
        existing.songs.add(song);
        await savePlaylist(existing);
        notifyListeners();
      }
    }
  }

  Future<void> removeSongFromDownloadedPlaylist(String songId) async {
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == downloadedPlaylistId);
    if (idx >= 0) {
      final pl = playlists[idx];
      pl.songs.removeWhere((s) => s.id == songId);
      await savePlaylist(pl);
    }
    // Keep global downloaded list in sync, but preserve it if another
    // downloaded playlist still references this song offline.
    final fresh = await getPlaylists();
    final stillNeeded =
        fresh.any((pl) => pl.downloadedSongIds.contains(songId));
    if (stillNeeded) {
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_downloadedSongsKey);
    if (jsonString != null) {
      final List<Song> list = (json.decode(jsonString) as List)
          .map((j) => Song.fromJson(j as Map<String, dynamic>))
          .toList();
      final before = list.length;
      list.removeWhere((s) => s.id == songId);
      if (list.length != before) {
        await prefs.setString(
            _downloadedSongsKey, json.encode(list.map((s) => s.toJson()).toList()));
      }
    }
    notifyListeners();
  }

  /// Removes one offline track from a downloaded playlist via Offline Content.
  /// Preserves the online playlist and its songs; only clears offline flags.
  /// When the last offline track is removed the playlist is unprotected
  /// (isDownloaded=false, isSystemManaged=false) so it becomes deletable.
  Future<void> removeOfflineSongFromPlaylist(
      String playlistId, String songId) async {
    if (playlistId == downloadedPlaylistId) {
      await removeSongFromDownloadedPlaylist(songId);
      return;
    }
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final p = playlists[idx];
    if (!p.downloadedSongIds.contains(songId)) return;
    final nextIds = Set<String>.from(p.downloadedSongIds)..remove(songId);
    final isDl = nextIds.isNotEmpty && nextIds.length == p.songs.length;
    final sys = nextIds.isNotEmpty ? p.isSystemManaged : false;
    playlists[idx] = p.copyWith(
      isDownloaded: isDl,
      downloadedSongIds: nextIds,
      isSystemManaged: sys,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _playlistsKey, json.encode(playlists.map((p) => p.toJson()).toList()));

    // Drop from global downloaded list if no other playlist still needs it.
    final stillNeeded = playlists.any((pl) =>
        pl.id != playlistId && pl.downloadedSongIds.contains(songId));
    final sysPl = playlists.firstWhere(
      (pl) => pl.id == downloadedPlaylistId,
      orElse: () => Playlist(id: '', name: '', songs: [], createdAt: DateTime.now()),
    );
    final inSys = sysPl.id.isNotEmpty && sysPl.songs.any((s) => s.id == songId);
    if (!stillNeeded && !inSys) {
      final js = prefs.getString(_downloadedSongsKey);
      if (js != null) {
        final List<Song> list = (json.decode(js) as List)
            .map((j) => Song.fromJson(j as Map<String, dynamic>))
            .toList();
        list.removeWhere((s) => s.id == songId);
        await prefs.setString(
            _downloadedSongsKey, json.encode(list.map((s) => s.toJson()).toList()));
      }
    }
    notifyListeners();
  }

  /// Clears all offline state for a playlist via Offline Content.
  /// Online playlist and its songs are preserved; only download flags,
  /// protection, and global downloaded entries are removed.
  Future<void> clearPlaylistDownload(String playlistId) async {
    if (playlistId == downloadedPlaylistId) return;
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final p = playlists[idx];
    final removedIds = Set<String>.from(p.downloadedSongIds);
    playlists[idx] = p.copyWith(
      isDownloaded: false,
      downloadedSongIds: <String>{},
      isSystemManaged: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _playlistsKey, json.encode(playlists.map((p) => p.toJson()).toList()));
    if (removedIds.isNotEmpty) {
      // Remove orphaned ids from global list (keep those still needed elsewhere).
      final needed = <String>{};
      for (final pl in playlists) {
        if (pl.id == playlistId) continue;
        needed.addAll(pl.downloadedSongIds);
      }
      final sysIdx =
          playlists.indexWhere((pl) => pl.id == downloadedPlaylistId);
      if (sysIdx >= 0) {
        for (final s in playlists[sysIdx].songs) {
          needed.add(s.id);
        }
      }
      final js = prefs.getString(_downloadedSongsKey);
      if (js != null) {
        final List<Song> list = (json.decode(js) as List)
            .map((j) => Song.fromJson(j as Map<String, dynamic>))
            .toList();
        list.removeWhere(
            (s) => removedIds.contains(s.id) && !needed.contains(s.id));
        await prefs.setString(
            _downloadedSongsKey, json.encode(list.map((s) => s.toJson()).toList()));
      }
    }
    notifyListeners();
  }

  Future<void> deleteDownloadedPlaylist() async {
    final playlists = await getPlaylists();
    final filtered = playlists.where((p) => p.id != downloadedPlaylistId).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, json.encode(filtered.map((p) => p.toJson()).toList()));
    // also clear downloaded songs
    await prefs.remove(_downloadedSongsKey);
    notifyListeners();
  }
}
