import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

/// Fetches playlist videos by parsing YouTube's playlist page.
///
/// youtube_explode_dart cannot parse playlists right now because YouTube
/// replaced `playlistVideoRenderer` items with `lockupViewModel` items.
/// This parser reads the new structure, including continuation pages.
class PlaylistParser {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const _timeout = Duration(seconds: 20);

  Future<List<Song>> fetchVideos(String playlistId, {int maxPages = 10}) async {
    final songs = <Song>[];
    final seen = <String>{};

    final html = await _getPage(playlistId);
    final data = _extractInitialData(html);
    final apiKey = _firstMatch(html, r'"INNERTUBE_API_KEY":"([^"]+)"');
    final clientVersion =
        _firstMatch(html, r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"');

    String? token = _collect(data, songs, seen);
    var pages = 1;
    while (token != null &&
        token.isNotEmpty &&
        pages < maxPages &&
        apiKey != null) {
      final cont = await _postContinuation(apiKey, clientVersion, token);
      token = _collect(cont, songs, seen);
      pages++;
    }
    return songs;
  }

  Future<String> _getPage(String playlistId) async {
    final resp = await http
        .get(
          Uri.parse(
              'https://www.youtube.com/playlist?list=$playlistId&hl=en&persist_hl=1'),
          headers: {'User-Agent': _ua},
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Playlist page returned ${resp.statusCode}');
    }
    return resp.body;
  }

  Map<String, dynamic> _extractInitialData(String html) {
    final match =
        RegExp(r'ytInitialData\s*=\s*(\{.*?\});').firstMatch(html);
    if (match == null) throw Exception('Playlist data not found on page');
    return json.decode(match.group(1)!) as Map<String, dynamic>;
  }

  String? _firstMatch(String text, String pattern) {
    return RegExp(pattern).firstMatch(text)?.group(1);
  }

  Future<Map<String, dynamic>> _postContinuation(
      String apiKey, String? clientVersion, String token) async {
    final resp = await http
        .post(
          Uri.parse(
              'https://www.youtube.com/youtubei/v1/browse?key=$apiKey&prettyPrint=false'),
          headers: {'User-Agent': _ua, 'Content-Type': 'application/json'},
          body: json.encode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': clientVersion ?? '2.20250222',
                'hl': 'en',
                'gl': 'US',
              }
            },
            'continuation': token,
          }),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Continuation returned ${resp.statusCode}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Collects songs from a response map. Returns next continuation token.
  String? _collect(
      Map<String, dynamic> data, List<Song> out, Set<String> seen) {
    final items = _findItems(data);
    String? token;
    for (final item in items) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      if (map.containsKey('lockupViewModel')) {
        final song = _parseLockup(map['lockupViewModel']);
        if (song != null && seen.add(song.videoId ?? song.id)) {
          out.add(song);
        }
      } else if (map.containsKey('continuationItemRenderer')) {
        final cir = map['continuationItemRenderer'];
        if (cir is Map) {
          final ep = cir['continuationEndpoint'];
          if (ep is Map) {
            final cmd = ep['continuationCommand'];
            if (cmd is Map && cmd['token'] is String) {
              token = cmd['token'] as String;
            }
          }
        }
      }
    }
    return token;
  }

  List<dynamic> _findItems(Map<String, dynamic> data) {
    // Continuation response shape.
    final actions = data['onResponseReceivedActions'];
    if (actions is List && actions.isNotEmpty) {
      final items = (actions.first as Map?)?['appendContinuationItemsAction']
          ?['continuationItems'];
      if (items is List) return items;
    }
    // First page shape.
    try {
      final tabs = (data['contents'] as Map)['twoColumnBrowseResultsRenderer']
          as Map;
      final tab = ((tabs['tabs'] as List).first as Map)['tabRenderer'] as Map;
      final section = (((tab['content'] as Map)['sectionListRenderer']
              as Map)['contents'] as List)
          .first as Map;
      final contents =
          (section['itemSectionRenderer'] as Map)['contents'];
      if (contents is List) return contents;
    } catch (_) {
      // Fall through to empty.
    }
    return const [];
  }

  Song? _parseLockup(dynamic vm) {
    if (vm is! Map) return null;
    final map = vm.cast<String, dynamic>();
    if (map['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;

    String? videoId = map['contentId'] as String?;

    String? titleText;
    final meta = map['metadata'];
    if (meta is Map) {
      final lmm = meta['lockupMetadataViewModel'];
      if (lmm is Map) {
        final title = lmm['title'];
        if (title is Map) titleText = title['content'] as String?;
      }
    }

    String artist = '';
    try {
      final metaMap = map['metadata'];
      if (metaMap is Map) {
        final lmm = metaMap['lockupMetadataViewModel'];
        if (lmm is Map) {
          final md = lmm['metadata'];
          if (md is Map) {
            final cmvm = md['contentMetadataViewModel'];
            if (cmvm is Map) {
              final rows = cmvm['metadataRows'];
              if (rows is List && rows.isNotEmpty && rows.first is Map) {
                final parts = (rows.first as Map)['metadataParts'];
                if (parts is List && parts.isNotEmpty && parts.first is Map) {
                  final text = (parts.first as Map)['text'];
                  if (text is Map) {
                    artist = (text['content'] as String?) ?? '';
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {
      artist = '';
    }

    Duration duration = Duration.zero;
    String? thumbUrl;
    try {
      final ci = map['contentImage'];
      if (ci is Map) {
        final tvm = ci['thumbnailViewModel'];
        if (tvm is Map) {
          final overlays = tvm['overlays'];
          if (overlays is List) {
            for (final o in overlays) {
              if (o is! Map) continue;
              final tbovm = o['thumbnailBottomOverlayViewModel'];
              if (tbovm is! Map) continue;
              final badges = tbovm['badges'];
              if (badges is! List) continue;
              for (final b in badges) {
                if (b is! Map) continue;
                final bvm = b['thumbnailBadgeViewModel'];
                if (bvm is! Map) continue;
                final text = bvm['text'];
                if (text is String &&
                    RegExp(r'^[\d:]+$').hasMatch(text)) {
                  duration = _parseDuration(text);
                }
              }
            }
          }
          final img = tvm['image'];
          if (img is Map) {
            final sources = img['sources'];
            if (sources is List && sources.isNotEmpty && sources.first is Map) {
              thumbUrl = (sources.first as Map)['url'] as String?;
            }
          }
        }
      }
    } catch (_) {
      // Keep defaults.
    }

    videoId ??= _firstMatch(
        thumbUrl ?? '', r'i\.ytimg\.com/vi/([^/]+)/');
    if (videoId == null || videoId.isEmpty) return null;

    return Song(
      id: videoId,
      title: (titleText == null || titleText.isEmpty) ? videoId : titleText,
      artist: artist.isEmpty ? 'Unknown' : artist,
      thumbnailUrl: thumbUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      duration: duration,
      videoId: videoId,
    );
  }

  Duration _parseDuration(String text) {
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
    } catch (_) {
      // Fall through.
    }
    return Duration.zero;
  }
}
