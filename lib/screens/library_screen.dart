import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../services/spotify_service.dart';
import '../services/youtube_service.dart';
import '../services/user_preferences.dart';
import '../services/song_filter.dart';
import '../theme/app_theme.dart';
import '../widgets/app_transitions.dart';
import '../widgets/liquid_background.dart';
import '../widgets/artwork.dart';
import '../widgets/play_helper.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _storage = StorageService.instance;
  final _yt = YouTubeService();
  List<Playlist> _playlists = [];
  bool _loading = true;
  bool _loadBusy = false;
  bool _loadQueued = false;
  List<Song> _visibleLiked = [];
  Map<String, int> _playlistCounts = {};

  @override
  void initState() {
    super.initState();
    _storage.addListener(_onStorageChanged);
    _load();
  }

  @override
  void dispose() {
    _storage.removeListener(_onStorageChanged);
    _yt.dispose();
    super.dispose();
  }

  void _onStorageChanged() {
    if (_loadBusy) {
      _loadQueued = true;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    if (_loadBusy) {
      _loadQueued = true;
      return;
    }
    _loadBusy = true;
    try {
      final p = await _storage.getPlaylists();
      final l = await _storage.getLikedSongs();
      MusicLanguage lang = MusicLanguage.all;
      try {
        lang = await UserPreferences().getLanguage();
      } catch (_) {}
      if (!mounted) return;
      /// GLOBAL rules on generated listings: liked rail shows only
      /// 00:45–07:00 tracks in the selected language (queue-aligned).
      /// Cached here so build never re-filters per row per frame.
      final visible = SongFilter.apply(l, language: lang);
      final counts = <String, int>{};
      for (final pl in p) {
        counts[pl.id] =
            SongFilter.apply(pl.songs, language: lang).length;
      }
      setState(() {
        _playlists = p;
        _visibleLiked = visible;
        _playlistCounts = counts;
        _loading = false;
      });
    } finally {
      _loadBusy = false;
      if (_loadQueued) {
        _loadQueued = false;
        _load();
      }
    }
  }

  Future<void> _import() async {
    final src = await _importSource();
    if (src == null) return;
    if (src == 'spotify') {
      await _importSpotify();
      return;
    }
    if (src == 'paste') {
      await _importPasted();
      return;
    }
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import YouTube Playlist'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'Paste playlist URL or ID',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Import')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    final text = result.trim();
    final m = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(text);
    final id = m != null
        ? m.group(1)!
        : (RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(text)
            ? text
            : null);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import failed. Check link.')),
      );
      return;
    }
    await _runYouTubeImport(id);
  }

  /// Shared YouTube import runner: progress, fetch, save, toast.
  Future<void> _runYouTubeImport(String id) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: AppColors.card,
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('Importing playlist...')
        ]),
      ),
    );
    try {
      final pl = await _yt.getPlaylist(id);
      await _storage.savePlaylist(pl);
      if (!context.mounted) return;
      Navigator.pop(context);
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported "${pl.name}" (${pl.songs.length})')),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import failed. Check link.')),
      );
    }
  }

  /// YouTube vs Spotify source picker for import/clone.
  Future<String?> _importSource() {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import playlist'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'youtube'),
            child: const Row(
              children: [
                Icon(Icons.smart_display_outlined,
                    size: 20, color: AppColors.inkSoft),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YouTube',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('Paste playlist URL or ID',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'spotify'),
            child: const Row(
              children: [
                Icon(Icons.music_note_outlined,
                    size: 20, color: AppColors.inkSoft),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spotify (clone)',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('Needs API keys · match each track',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'paste'),
            child: const Row(
              children: [
                Icon(Icons.content_paste_outlined,
                    size: 20, color: AppColors.inkSoft),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Paste track list',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('No keys needed · one per line',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Clone a Spotify playlist: read its tracks via Spotify Web API, match
  /// each to a playable song, save as a local playlist. Needs the user's
  /// own Spotify Client ID/Secret once (free at
  /// developer.spotify.com/dashboard).
  Future<void> _importSpotify() async {
    final sp = SpotifyService();
    try {
      if (!await sp.hasCredentials()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Add Spotify keys in Profile → Spotify first')),
        );
        return;
      }
      final linkCtrl = TextEditingController();
      final link = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Clone Spotify playlist'),
          content: TextField(
            controller: linkCtrl,
            decoration: const InputDecoration(
                hintText: 'Paste Spotify playlist link or ID',
                border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, linkCtrl.text),
                child: const Text('Clone')),
          ],
        ),
      );
      linkCtrl.dispose();
      if (link == null || link.trim().isEmpty) return;

      var matched = 0;
      var total = 0;
      void Function(void Function())? setProg;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (_, setSt) {
            setProg = setSt;
            return AlertDialog(
              backgroundColor: AppColors.card,
              content: Row(children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(total == 0
                      ? 'Reading Spotify tracks...'
                      : 'Matching $matched/$total...'),
                ),
              ]),
            );
          },
        ),
      );
      Playlist pl;
      try {
        pl = await sp.clonePlaylist(
          yt: _yt,
          playlistIdOrUrl: link.trim(),
          onProgress: (d, t) {
            matched = d;
            total = t;
            try {
              setProg?.call(() {});
            } catch (_) {}
          },
        );
      } catch (_) {
        if (mounted) Navigator.pop(context);
        rethrow;
      }
      if (!mounted) return;
      Navigator.pop(context);
      await _storage.savePlaylist(pl);
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned "${pl.name}" (${pl.songs.length})')),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final authish = raw.toLowerCase().contains('auth') ||
          raw.contains('401') ||
          raw.toLowerCase().contains('credential');
      if (authish) {
        // Bad secret: forget it so the next attempt re-prompts.
        await sp.clearCredentials();
      }
      final short = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spotify clone failed: $short')),
      );
    }
  }

  /// Keyless clone: paste "Title - Artist" lines (or a Spotify desktop
  /// copy), match each to playable audio. No API, no keys.
  Future<void> _importPasted() async {
    final nameCtrl = TextEditingController();
    final tracksCtrl = TextEditingController();
    final input = await showDialog<List<String>>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Paste track list'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      hintText: 'Playlist name',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                const Text(
                  'One per line: Title - Artist. Spotify copies paste as-is.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tracksCtrl,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      hintText: 'Blinding Lights - The Weeknd\n...',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(
                  context, [nameCtrl.text, tracksCtrl.text]),
              child: const Text('Clone')),
        ],
      ),
    );
    final name = (input != null && input.isNotEmpty ? input[0] : '');
    final text = (input != null && input.length > 1 ? input[1] : '');
    nameCtrl.dispose();
    tracksCtrl.dispose();
    if (input == null || text.trim().isEmpty) return;

    var matched = 0;
    var total = 0;
    void Function(void Function())? setProg;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (_, setSt) {
          setProg = setSt;
          return AlertDialog(
            backgroundColor: AppColors.card,
            content: Row(children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(total == 0
                    ? 'Reading tracks...'
                    : 'Matching $matched/$total...'),
              ),
            ]),
          );
        },
      ),
    );
    try {
      final pl = await SpotifyService().cloneFromText(
        yt: _yt,
        name: name,
        text: text,
        onProgress: (d, t) {
          matched = d;
          total = t;
          try {
            setProg?.call(() {});
          } catch (_) {}
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
      await _storage.savePlaylist(pl);
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned "${pl.name}" (${pl.songs.length})')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final short = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clone failed: $short')),
      );
    }
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Create Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Playlist name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    await _storage.savePlaylist(Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: result,
      songs: [],
      createdAt: DateTime.now(),
      source: 'local',
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<AudioPlayerService, bool>(
        (s) => s.currentSong != null);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(strokeWidth: 2)))
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 20, right: 12, top: 14),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Your Library',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: _create,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: GlassPanel(
                            radius: 20,
                            padding: const EdgeInsets.all(6),
                            opacity: 0.07,
                            child: Row(
                              children: [
                                _quick(Icons.download, 'Import', _import),
                                _quick(Icons.favorite_outline, 'Liked',
                                    _openLiked),
                                _quick(Icons.history, 'Recent', () {}),
                              ],
                            ),
                          ),
                        ),
                      ),
                       SliverToBoxAdapter(
                         child: Builder(builder: (context) {
                           final liked = _visibleLiked;
                           if (liked.isEmpty) {
                             return const SizedBox.shrink();
                           }
                           return Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             const Padding(
                               padding:
                                   EdgeInsets.symmetric(horizontal: 20),
                               child: Text('Liked Songs',
                                   style: TextStyle(
                                       fontSize: 16,
                                       fontWeight: FontWeight.w700)),
                             ),
                             ListView.builder(
                               shrinkWrap: true,
                               physics:
                                   const NeverScrollableScrollPhysics(),
                               itemCount: liked.length.clamp(0, 5),
                               itemBuilder: (_, i) {
                                 final s = liked[i];
                                 return ListTile(
                                   leading: Artwork(
                                     s.thumbnailUrl,
                                     size: 48,
                                     radius: 10,
                                   ),
                                   title: Text(s.title,
                                       maxLines: 1,
                                       overflow:
                                           TextOverflow.ellipsis),
                                   subtitle: Text(s.artist,
                                       maxLines: 1,
                                       overflow:
                                           TextOverflow.ellipsis,
                                       style: TextStyle(
                                           color: AppColors.inkSoft)),
                                   onTap: () => playSongs(
                                       context,
                                       song: s,
                                       queue: liked,
                                       index: i),
                                 );
                               },
                             ),
                           ],
                         );
                       }),
                       ),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text('Playlists',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      if (_playlists.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No playlists yet\nTap + to create or import',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.inkSoft),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) {
                              final p = _playlists[i];
                              // GLOBAL rules: counts reflect listed songs.
                              final visibleCount =
                                  _playlistCounts[p.id] ?? p.songs.length;
                              return ListTile(
                                leading: (p.thumbnailUrl ?? '').isEmpty
                                    ? Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: AppColors.mist,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                            Icons.queue_music,
                                            color: AppColors.mute),
                                      )
                                    : Artwork(
                                        p.thumbnailUrl!,
                                        size: 48,
                                        radius: 10,
                                      ),
                                title: Text(
                                    p.isDownloaded ? '${p.name} - Downloaded' : p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text('$visibleCount songs',
                                    style: TextStyle(
                                        color: AppColors.inkSoft)),
                                trailing: const Icon(
                                    Icons.chevron_right,
                                    color: AppColors.mute),
                                onTap: () async {
                                  await pushAppPage(
                                    context,
                                    PlaylistDetailScreen(playlist: p),
                                  );
                                  _load();
                                },
                              );
                            },
                            childCount: _playlists.length,
                          ),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.only(
                            bottom: hasSong ? 190 : 120),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _openLiked() async {
    await pushAppPage(context, const LikedSongsScreen());
    _load();
  }

  Widget _quick(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
