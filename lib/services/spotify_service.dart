import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import 'song_filter.dart';
import 'user_preferences.dart';
import 'youtube_service.dart';

/// Spotify import + clone. Spotify exposes no audio streams usable here,
/// so "clone" means: read the track list via Spotify Web API, then match
/// each track to a playable YouTube song (which the normal resolver,
/// cache, and queue logic handle like any other song).
///
/// Auth is Client Credentials from the user's own Spotify app
/// (developer.spotify.com/dashboard). ID/secret are stored on-device
/// only and sent solely to accounts.spotify.com for a token.
class SpotifyService {
  static const String _baseUrl = 'https://api.spotify.com/v1';
  static const _idKey = 'spotify_client_id';
  static const _secretKey = 'spotify_client_secret';
  static const _timeout = Duration(seconds: 20);

  String? _accessToken;
  DateTime? _tokenExpiry;

  Future<void> saveCredentials(String clientId, String clientSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, clientId.trim());
    await prefs.setString(_secretKey, clientSecret.trim());
    _accessToken = null;
    _tokenExpiry = null;
  }

  Future<bool> hasCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final secret = prefs.getString(_secretKey);
    return id != null &&
        id.isNotEmpty &&
        secret != null &&
        secret.isNotEmpty;
  }

  /// Saved Client ID for display/prefill. Secret is never exposed.
  Future<String?> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_secretKey);
    _accessToken = null;
    _tokenExpiry = null;
  }

  Future<void> authenticate([String? clientId, String? clientSecret]) async {
    var id = clientId;
    var secret = clientSecret;
    if (id == null || secret == null) {
      final prefs = await SharedPreferences.getInstance();
      id ??= prefs.getString(_idKey);
      secret ??= prefs.getString(_secretKey);
    }
    if (id == null || id.isEmpty || secret == null || secret.isEmpty) {
      throw Exception(
          'Spotify credentials missing. Add your Client ID and Secret first.');
    }
    final response = await http
        .post(
          Uri.parse('https://accounts.spotify.com/api/token'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$id:$secret'))}',
          },
          body: {'grant_type': 'client_credentials'},
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      _accessToken = data['access_token'] as String?;
      final ttl = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _tokenExpiry =
          DateTime.now().add(Duration(seconds: ttl > 120 ? ttl - 60 : ttl));
      if (_accessToken == null || _accessToken!.isEmpty) {
        throw Exception('Spotify authentication failed: empty token.');
      }
    } else {
      throw Exception(
          'Spotify authentication failed (${response.statusCode}). Check Client ID and Secret.');
    }
  }

  /// No-op when the cached token is still valid.
  Future<void> ensureAuthenticated() async {
    if (_accessToken != null &&
        _accessToken!.isNotEmpty &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }
    await authenticate();
  }

  /// Raw Spotify track list (videoId null — display only). Prefer
  /// [clonePlaylist] for playable clones. Accepts link or bare ID.
  Future<Playlist> getPlaylist(String playlistIdOrUrl) async {
    final playlistId = parsePlaylistId(playlistIdOrUrl);
    await ensureAuthenticated();
    final meta = await _getJson(
        '$_baseUrl/playlists/$playlistId?fields=name,description,images(url)');
    final tracks = await _fetchAllTracks(playlistId);
    return Playlist(
      id: 'spotify-$playlistId',
      name: (meta['name'] as String?) ?? 'Spotify Playlist',
      description: meta['description'] as String?,
      thumbnailUrl: _coverOf(meta),
      songs: tracks,
      createdAt: DateTime.now(),
      source: 'spotify',
    );
  }

  /// Full clone: every Spotify track matched to a playable YouTube song.
  /// [onProgress] reports (matched-so-far, total-tracks) for UI.
  /// Throws when nothing matched or auth/link is bad.
  Future<Playlist> clonePlaylist({
    required YouTubeService yt,
    required String playlistIdOrUrl,
    void Function(int done, int total)? onProgress,
  }) async {
    final playlistId = parsePlaylistId(playlistIdOrUrl);
    await ensureAuthenticated();
    final meta = await _getJson(
        '$_baseUrl/playlists/$playlistId?fields=name,description,images(url)');
    final tracks = await _fetchAllTracks(playlistId);
    if (tracks.isEmpty) {
      throw Exception('No tracks found in this Spotify playlist.');
    }
    // GLOBAL rules like YouTube imports: playable window + language
    // (applied inside _matchAndSave).
    return _matchAndSave(
      yt: yt,
      id: 'spotify-$playlistId',
      name: (meta['name'] as String?) ?? 'Spotify Playlist',
      description: meta['description'] as String?,
      cover: _coverOf(meta),
      tracks: tracks,
      onProgress: onProgress,
    );
  }

  /// Keyless clone: user pastes a track list (copied from Spotify or
  /// typed), no API involved. Accepts "Title - Artist" lines and raw
  /// Spotify desktop copies (title/artist/album/duration blocks).
  Future<Playlist> cloneFromText({
    required YouTubeService yt,
    required String name,
    required String text,
    void Function(int done, int total)? onProgress,
  }) async {
    final tracks = parseTrackList(text);
    if (tracks.isEmpty) {
      throw Exception('No tracks found. Paste one "Title - Artist" per line.');
    }
    final cleanName = name.trim().isEmpty ? 'Pasted Playlist' : name.trim();
    return _matchAndSave(
      yt: yt,
      id: 'paste-${DateTime.now().millisecondsSinceEpoch}',
      name: cleanName,
      description: 'Cloned from pasted track list',
      cover: null,
      tracks: tracks,
      onProgress: onProgress,
    );
  }

  /// Parses pasted track lists into matchable songs. Static for tests.
  /// - "Title - Artist" (also en/em dashes, colon) one per line.
  /// - Spotify desktop copy blocks closed by a duration line (m:ss):
  ///   first line = title, second = artist, rest skipped.
  /// - Bare single lines become title-only queries.
  static List<Song> parseTrackList(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final out = <Song>[];
    final seen = <String>{};
    void add(String title, String artist) {
      title = title.trim();
      artist = artist.trim();
      if (title.isEmpty) return;
      final key = '$title\u0000$artist'.toLowerCase();
      if (!seen.add(key)) return;
      out.add(Song(
        id: 'paste-$key'.hashCode.toString(),
        title: title,
        artist: artist.isEmpty ? 'Unknown' : artist,
        thumbnailUrl: '',
        duration: Duration.zero,
      ));
    }

    final durRe = RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$');
    var i = 0;
    while (i < lines.length) {
      // Duration-closed block: [..., title, artist, (album,) duration].
      var j = i;
      while (j < lines.length && !durRe.hasMatch(lines[j])) {
        j++;
      }
      if (j < lines.length && j > i) {
        // Block lines[i..j] ends with duration at j.
        final block = lines.sublist(i, j);
        add(block.first, block.length > 1 ? block[1] : '');
        i = j + 1;
        continue;
      }
      final line = lines[i];
      final sep = RegExp(r'\s+[-–—:]\s+').firstMatch(line);
      if (sep != null) {
        add(line.substring(0, sep.start), line.substring(sep.end));
      } else {
        add(line, '');
      }
      i++;
    }
    return out;
  }

  /// Shared match + filter + wrap used by API and text clones.
  Future<Playlist> _matchAndSave({
    required YouTubeService yt,
    required String id,
    required String name,
    required String? description,
    required String? cover,
    required List<Song> tracks,
    void Function(int done, int total)? onProgress,
  }) async {
    final matched = <Song>[];
    var done = 0;
    const batch = 4;
    for (var k = 0; k < tracks.length; k += batch) {
      final chunk = tracks.skip(k).take(batch);
      final results =
          await Future.wait(chunk.map((t) => _matchTrack(yt, t)));
      for (final m in results) {
        done++;
        if (m != null) matched.add(m);
        onProgress?.call(done, tracks.length);
      }
    }
    var songs = matched;
    try {
      final lang = await UserPreferences().getLanguage();
      songs = SongFilter.apply(matched, language: lang);
    } catch (_) {}
    if (songs.isEmpty) {
      throw Exception(
          'No playable matches found (${matched.length}/${tracks.length} matched before filtering).');
    }
    return Playlist(
      id: id,
      name: name,
      description: description,
      thumbnailUrl: cover ?? songs.first.thumbnailUrl,
      songs: songs,
      createdAt: DateTime.now(),
      source: 'spotify',
    );
  }

  /// Best YouTube hit for one Spotify track: first duration-compatible
  /// hit (±25s), else first hit. Null when search fails entirely.
  Future<Song?> _matchTrack(YouTubeService yt, Song t) async {
    try {
      final results = await yt
          .search('${t.title} ${t.artist} official audio', limit: 5)
          .timeout(const Duration(seconds: 12));
      if (results.isEmpty) return null;
      final want = t.duration.inSeconds;
      for (final s in results) {
        if (s.videoId == null) continue;
        if (want <= 0) return s;
        if ((s.duration.inSeconds - want).abs() <= 25) return s;
      }
      return results.first;
    } catch (_) {
      return null;
    }
  }

  /// All tracks across pages. Skips local/unavailable (no Spotify ID).
  Future<List<Song>> _fetchAllTracks(String playlistId) async {
    final out = <Song>[];
    String? url =
        '$_baseUrl/playlists/$playlistId/tracks?limit=100&fields=${Uri.encodeComponent('items(track(id,name,artists(name),album(images(url)),duration_ms,is_local)),next')}';
    while (url != null) {
      final resp = await http
          .get(Uri.parse(url),
              headers: {'Authorization': 'Bearer $_accessToken'})
          .timeout(_timeout);
      if (resp.statusCode == 401) {
        // Token died mid-clone: refresh once, retry same page.
        _accessToken = null;
        await ensureAuthenticated();
        continue;
      }
      if (resp.statusCode != 200) _fail(resp.statusCode);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      for (final item in (data['items'] as List? ?? const [])) {
        final track = item is Map ? item['track'] : null;
        if (track is! Map) continue;
        final id = track['id'] as String?;
        if (id == null || id.isEmpty || track['is_local'] == true) continue;
        final artists = ((track['artists'] as List?) ?? const [])
            .map((a) => (a as Map?)?['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(', ');
        final images = (track['album'] as Map?)?['images'] as List?;
        out.add(Song(
          id: 'sp-$id',
          title: (track['name']?.toString() ?? '').isEmpty
              ? 'Unknown'
              : track['name'].toString(),
          artist: artists.isEmpty ? 'Unknown' : artists,
          thumbnailUrl: images != null && images.isNotEmpty
              ? ((images.first as Map?)?['url']?.toString() ?? '')
              : '',
          duration: Duration(
              milliseconds: (track['duration_ms'] as num?)?.toInt() ?? 0),
        ));
      }
      final next = data['next'];
      url = (next is String && next.isNotEmpty) ? next : null;
    }
    return out;
  }

  /// First playlist image URL, or null. Static for unit tests.
  static String? coverOf(Map<String, dynamic> meta) => _coverOf(meta);

  static String? _coverOf(Map<String, dynamic> meta) {
    final images = meta['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        final url = first['url'];
        if (url is String && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  /// Friendly failures. 403 almost always means Spotify itself refused
  /// the app (not bad keys): new developer apps are quota-restricted and
  /// private playlists are invisible to Client Credentials. Static for
  /// unit tests.
  static String friendlyError(int code) {
    if (code == 403) {
      return 'Spotify denied access (403). Fix: use a PUBLIC playlist, and '
          'in developer.spotify.com/dashboard request Extended Quota Mode '
          'for your app (new apps are restricted by default).';
    }
    if (code == 404) return 'Spotify playlist not found. Check the link.';
    return 'Spotify request failed ($code).';
  }

  Never _fail(int code) => throw Exception(friendlyError(code));

  Future<Map<String, dynamic>> _getJson(String url) async {
    final resp = await http
        .get(Uri.parse(url),
            headers: {'Authorization': 'Bearer $_accessToken'})
        .timeout(_timeout);
    if (resp.statusCode == 401) {
      _accessToken = null;
      await ensureAuthenticated();
      return _getJson(url);
    }
    if (resp.statusCode != 200) _fail(resp.statusCode);
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Accepts open.spotify.com links, spotify:playlist: URIs, bare IDs.
  /// Static for unit tests.
  static String parsePlaylistId(String input) {
    final text = input.trim();
    if (text.startsWith('spotify:playlist:')) {
      final id = text.split(':').last.trim();
      if (id.isNotEmpty) return id;
    }
    try {
      final uri = Uri.parse(text);
      final segs = uri.pathSegments;
      final i = segs.indexOf('playlist');
      if (i >= 0 && i + 1 < segs.length && segs[i + 1].isNotEmpty) {
        return segs[i + 1];
      }
    } catch (_) {}
    if (RegExp(r'^[A-Za-z0-9]{10,}$').hasMatch(text) &&
        !text.contains('/')) {
      return text;
    }
    throw Exception('Invalid Spotify playlist link or ID.');
  }

  Future<String> extractPlaylistId(String url) async =>
      parsePlaylistId(url);
}
