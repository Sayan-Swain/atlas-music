import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../services/user_preferences.dart';
import '../services/song_filter.dart';
import '../theme/app_theme.dart';
import '../media/cache_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/mini_player.dart';
import '../widgets/play_helper.dart';
import '../widgets/liquid_background.dart';
import '../widgets/artwork.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Playlist _playlist;
  final _storage = StorageService();
  MusicLanguage _lang = MusicLanguage.all;

  /// GLOBAL rules: listings show only 00:45–07:00 tracks in the selected
  /// language. Stored data is never mutated here; playback queues always
  /// use this visible list so taps and indices stay aligned. Cached on
  /// playlist/lang change so build never re-filters per frame.
  List<Song> _songsCache = [];
  List<Song> get _songs => _songsCache;

  void _resyncSongs() {
    _songsCache = SongFilter.apply(_playlist.songs, language: _lang);
  }

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _resyncSongs();
    _refreshFromStorage();
  }

  Future<void> _refreshFromStorage() async {
    final playlists = await _storage.getPlaylists();
    MusicLanguage lang = MusicLanguage.all;
    try {
      lang = await UserPreferences().getLanguage();
    } catch (_) {}
    final match = playlists.where((p) => p.id == _playlist.id);
    if (match.isNotEmpty && mounted) {
      setState(() {
        _playlist = match.first;
        _lang = lang;
        _resyncSongs();
      });
    }
  }

  static Widget _fallbackBackground(Playlist p) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.charcoal, AppColors.inkSoft],
          ),
        ),
        child:
            const Icon(Icons.queue_music, size: 80, color: Colors.white),
      );

  Future<void> _downloadPlaylist() async {
    if (_songs.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Downloading playlist...'),
          ],
        ),
      ),
    );
    final audioService = context.read<AudioPlayerService>();
    final downloadedIds = Set<String>.from(_playlist.downloadedSongIds);
    for (final song in _songs) {
      if (downloadedIds.contains(song.id)) continue;
      final ok = await audioService.downloadCurrentSongForSong(song, addToDownloadedPlaylist: false);
      if (ok) downloadedIds.add(song.id);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    // Protect only while offline content exists. Empty (all failed) stays normal.
    final updated = _playlist.copyWith(
      isDownloaded: downloadedIds.length == _songs.length && downloadedIds.isNotEmpty,
      downloadedSongIds: downloadedIds,
      isSystemManaged: downloadedIds.isNotEmpty,
    );
    await _storage.savePlaylist(updated);
    setState(() {
      _playlist = updated;
      _resyncSongs();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded ${downloadedIds.length}/${_songs.length} songs')),
    );
  }

  Future<void> _addSongDialog() async {
    final ctrl = TextEditingController();
    final yt = YouTubeService();
    List<Song> results = [];
    bool searched = false;
    bool loading = false;

    final song = await showDialog<Song>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Add Song'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: Column(
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'Search songs...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (q) async {
                    if (q.trim().isEmpty) return;
                    setDialogState(() => loading = true);
                    try {
                      final r = await yt.search(q.trim(), limit: 10);
                      setDialogState(() {
                        results = r;
                        searched = true;
                        loading = false;
                      });
                    } catch (_) {
                      setDialogState(() => loading = false);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Expanded(
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2))),
                if (!loading && searched && results.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No results',
                          style:
                              TextStyle(color: AppColors.inkSoft)),
                    ),
                  ),
                if (results.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final s = results[i];
                        final already = _playlist.songs
                            .any((ps) => ps.id == s.id);
                        return ListTile(
                          dense: true,
                          leading: Artwork(s.thumbnailUrl,
                              size: 40, radius: 8),
                          title: Text(s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(s.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkSoft)),
                          trailing: already
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 20)
                              : null,
                          onTap: already
                              ? null
                              : () => Navigator.pop(ctx, s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );

    yt.dispose();
    ctrl.dispose();
    if (song == null) return;
    if (_playlist.id == StorageService.downloadedPlaylistId ||
        _playlist.isDownloaded ||
        _playlist.downloadedSongIds.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Downloaded playlist is read-only — clear download first')),
        );
      }
      return;
    }
    await _storage.addSongToPlaylist(_playlist.id, song);
    await _refreshFromStorage();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${song.title}"')),
      );
    }
  }

  Future<void> _removeSong(Song song) async {
    // System Downloaded Music: delete the download (playlist entry + global
    // downloaded list + cache file). This is the supported delete path.
    if (_playlist.id == StorageService.downloadedPlaylistId) {
      await _storage.removeSongFromDownloadedPlaylist(song.id);
      try {
        await CacheService().invalidate(song);
      } catch (_) {}
      await _refreshFromStorage();
      return;
    }
    if ((_playlist.isDownloaded && _playlist.downloadedSongIds.contains(song.id)) ||
        _playlist.downloadedSongIds.contains(song.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Downloaded — remove via Offline Content to keep cache in sync')),
      );
      return;
    }
    await _storage.removeSongFromPlaylist(_playlist.id, song.id);
    await _refreshFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<AudioPlayerService, bool>(
        (s) => s.currentSong != null);
    final playlist = _playlist;
    final songs = _songs;

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 250,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        playlist.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (playlist.coverPath != null &&
                              playlist.coverPath!.isNotEmpty)
                            Image.file(
                              File(playlist.coverPath!),
                              fit: BoxFit.cover,
                              cacheWidth: 1024,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, __, ___) =>
                                  _fallbackBackground(playlist),
                            )
                          else if (playlist.thumbnailUrl != null)
                            Artwork(
                              playlist.thumbnailUrl!,
                              radius: 0,
                              fillWidth: true,
                              fit: BoxFit.cover,
                              height: 250,
                            )
                          else
                            _fallbackBackground(playlist),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xFF0D0D0D)
                                ],
                                stops: [0.5, 1.0],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      if (songs.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                              Icons.play_circle_fill),
                          onPressed: () {
                            playSongs(
                              context,
                              song: songs.first,
                              queue: songs,
                              index: 0,
                            );
                          },
                        ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'add_song',
                            child: Text('Add Song'),
                          ),
                          const PopupMenuItem(
                            value: 'play_all',
                            child: Text('Play All'),
                          ),
                          const                       PopupMenuItem(
                            value: 'shuffle',
                            child: Text('Shuffle'),
                          ),
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Download playlist'),
                          ),
                          const PopupMenuItem(
                            value: 'cover',
                            child: Text('Change cover'),
                          ),
                          if (playlist.coverPath != null &&
                              playlist.coverPath!.isNotEmpty)
                            const PopupMenuItem(
                              value: 'remove_cover',
                              child: Text('Remove cover'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete Playlist'),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'download') {
                            _downloadPlaylist();
                          } else if (value == 'add_song') {
                            _addSongDialog();
                          } else if (value == 'play_all' &&
                              songs.isNotEmpty) {
                            playSongs(
                              context,
                              song: songs.first,
                              queue: songs,
                              index: 0,
                            );
                          } else if (value == 'shuffle' &&
                              songs.isNotEmpty) {
                            final shuffled =
                                List<Song>.from(songs)
                                  ..shuffle();
                            playSongs(
                              context,
                              song: shuffled.first,
                              queue: shuffled,
                              index: 0,
                            );
                          } else if (value == 'cover') {
                            final picked =
                                await _pickPlaylistCover(context);
                            if (picked != null && mounted) {
                              setState(() {});
                            }
                          } else if (value == 'remove_cover') {
                            final old = playlist.coverPath;
                            await _storage.updateCover(
                                playlist.id, null);
                            if (old != null && old.isNotEmpty) {
                              try {
                                await File(old).delete();
                              } catch (_) {}
                            }
                            if (mounted) {
                              setState(() {
                                _playlist =
                                    _playlist.withCover(null);
                              });
                            }
                          } else if (value == 'delete') {
                            final confirm =
                                await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text(
                                    'Delete Playlist?'),
                                content: Text(
                                  'Delete "${playlist.name}"? This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                            context, false),
                                    child:
                                        const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                            context, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(
                                          color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _storage.deletePlaylist(
                                  playlist.id);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          if (playlist.description !=
                                  null &&
                              playlist
                                  .description!.isNotEmpty)
                            Text(
                              playlist.description!,
                              style: TextStyle(
                                  color: AppColors.inkSoft),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            '${songs.length} songs',
                            style: TextStyle(
                                color: AppColors.inkSoft),
                          ),
                          if (playlist.source != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  playlist.source == 'youtube'
                                      ? Icons
                                          .youtube_searched_for
                                      : Icons.music_note,
                                  size: 14,
                                  color: AppColors.mute,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Imported from ${playlist.source}',
                                  style: TextStyle(
                                    color: AppColors.mute,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (songs.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No songs yet — tap + to add',
                          style: TextStyle(
                              color: AppColors.inkSoft),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate:
                          SliverChildBuilderDelegate(
                        (context, index) {
                          return SongTile(
                            song: songs[index],
                            onTap: () {
                              playSongs(
                                context,
                                song:
                                    songs[index],
                                queue:
                                    songs,
                                index: index,
                              );
                            },
                            trailing:
                                playlist.isDownloaded && playlist.downloadedSongIds.contains(songs[index].id)
                                    ? null
                                    : PopupMenuButton(
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                      'Remove from Playlist'),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'remove') {
                                  _removeSong(
                                      songs[
                                          index]);
                                }
                              },
                            ),
                          );
                        },
                        childCount:
                            songs.length,
                      ),
                    ),
                  const SliverPadding(
                      padding:
                          EdgeInsets.only(bottom: 170)),
                ],
              ),
              if (hasSong)
                const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 8,
                    child: MiniPlayer()),
            ],
          ),
        ),
      ),
    );
  }

  Future<File?> _pickPlaylistCover(
      BuildContext context) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final dest = File(
        '${dir.path}/playlist_cover_${widget.playlist.id}.jpg');
    await File(picked.path).copy(dest.path);
    await _storage.updateCover(widget.playlist.id, dest.path);
    if (mounted) {
      setState(() {
        _playlist = _playlist.withCover(dest.path);
      });
    }
    return dest;
  }
}
