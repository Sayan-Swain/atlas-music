import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../services/user_preferences.dart';
import '../services/song_filter.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_background.dart';
import '../widgets/artwork.dart';
import '../widgets/play_helper.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final YouTubeService _yt = YouTubeService();
  final StorageService _storage = StorageService();
  List<Song> _results = [];
  bool _loading = false;
  bool _searched = false;
  List<String> _history = [];
  // Overlapping searches: only the latest request may publish results.
  // A slow earlier request finishing last used to overwrite fresh results
  // (or raise a stale failure toast for a query already replaced).
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final h = await _storage.getSearchHistory();
    if (mounted) setState(() => _history = h);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _yt.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    final int gen = ++_searchGen;
    await _storage.addSearchQuery(q.trim());
    await _loadHistory();
    if (!mounted || gen != _searchGen) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final r = await _yt.search(q.trim());
      if (!mounted || gen != _searchGen) return;
      setState(() {
        // Search: duration filter only, language unrestricted, require videoId
        final filtered = SongFilter.apply(r, language: MusicLanguage.all);
        _results = filtered.where((s) => s.videoId != null).toList();
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() => _loading = false);
      // Report the ACTUAL failure instead of always blaming the
      // connection: timeouts, provider throttling, and server errors are
      // not connection problems. Detail stays short for the snackbar;
      // the full error is in the ATLAS-SEARCH debug log.
      final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final short =
          raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $short')),
      );
    }
  }

  Future<void> _play(Song s, int i) async {
    // Search plays ONLY the tapped song, then seed-based radio keeps
    // playing tracks similar to it (see _playSeedRadio). The result
    // list is not a queue: finishing never walks down the list.
    await playSongs(context,
        song: s, queue: [s], index: 0, autoplayOnEnd: true,
        queueOrigin: 'search');
    try {
      await _storage.addToRecentlyPlayed(s);
    } catch (_) {}
  }

  Future<void> _addToPlaylist(Song song) async {
    final playlists = await _storage.getPlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Create a playlist first from the Home or Library tab')),
      );
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.card,
        title: const Text('Add to playlist'),
        children: playlists
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p.id),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music,
                          size: 20, color: AppColors.inkSoft),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w500)),
                            Text('${p.songs.length} songs',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _storage.addSongToPlaylist(chosen, song);
    if (mounted) {
      final pl = playlists.firstWhere((p) => p.id == chosen);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Added to "${pl.name}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<AudioPlayerService, bool>(
        (s) => s.currentSong != null);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Search',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 22),
                    tooltip: 'Clear search history',
                    onPressed: () async {
                      await _storage.clearSearchHistory();
                      await _loadHistory();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: GlassPanel(
                radius: 18,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6),
                opacity: 0.09,
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists...',
                    hintStyle: const TextStyle(
                        color: AppColors.mute),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.mute),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctrl,
                      builder: (_, value, __) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() {
                              _results = [];
                              _searched = false;
                            });
                          },
                        );
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(
                            vertical: 14),
                  ),
                  onSubmitted: _search,
                  textInputAction: TextInputAction.search,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                                  strokeWidth: 2)),
                    )
                  : _results.isEmpty
                      ? _searched
                          ? Center(
                              child: Text(
                                'No results found',
                                 style: TextStyle(
                                     color: AppColors.inkSoft),
                              ),
                            )
                          : _history.isEmpty
                              ? Center(
                                  child: Text(
                                    'Search for your favorite music',
                                    style: TextStyle(
                                     color: AppColors.inkSoft),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  itemCount: _history.length + 1,
                                  itemBuilder: (_, i) {
                                    if (i == 0) {
                                      return const Padding(
                                        padding: EdgeInsets.only(bottom: 8),
                                        child: Text('Recent searches',
                                             style: TextStyle(
                                                 fontSize: 14,
                                                 color: AppColors.inkSoft)),
                                      );
                                    }
                                    final q = _history[i - 1];
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                       leading: const Icon(
                                           Icons.history,
                                           size: 18,
                                           color: AppColors.inkSoft),
                                      title: Text(q, style: const TextStyle(fontSize: 14)),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () async {
                                          final updated = List<String>.from(_history);
                                          updated.removeAt(i - 1);
                                          await _storage.clearSearchHistory();
                                          for (final item in updated) {
                                            await _storage.addSearchQuery(item);
                                          }
                                          await _loadHistory();
                                        },
                                      ),
                                      onTap: () {
                                        _ctrl.text = q;
                                        _search(q);
                                      },
                                    );
                                  },
                                )
                      : ListView.separated(
                          padding: EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom:
                                  hasSong ? 190 : 120),
                          physics:
                              const BouncingScrollPhysics(),
                          cacheExtent: 600,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 2),
                          itemBuilder: (_, i) {
                            final s = _results[i];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(14)),
                              leading: Artwork(
                                s.thumbnailUrl,
                                size: 48,
                                radius: 10,
                              ),
                              title: Text(s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow
                                      .ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                          FontWeight
                                              .w500)),
                              subtitle: Text(s.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow
                                      .ellipsis,
                                  style: TextStyle(
                                      color:
                                          AppColors.inkSoft,
                                      fontSize: 12)),
                              trailing:
                                  PopupMenuButton(
                                icon: const Icon(
                                    Icons.more_vert,
                                    size: 20),
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'play',
                                    child: Text('Play'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'add',
                                    child: Text(
                                        'Add to Playlist'),
                                  ),
                                ],
                                onSelected: (v) {
                                  if (v == 'play') {
                                    _play(s, i);
                                  } else if (v ==
                                      'add') {
                                    _addToPlaylist(s);
                                  }
                                },
                              ),
                              onTap: () => _play(s, i),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
