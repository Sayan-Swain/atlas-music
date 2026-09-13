import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../services/user_preferences.dart';
import '../services/song_filter.dart';
import '../theme/app_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/liquid_background.dart';
import '../widgets/mini_player.dart';
import '../widgets/play_helper.dart';

/// Liked songs collection. Listens to storage so likes/unlikes anywhere
/// in the app reflect here instantly.
class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final _storage = StorageService.instance;
  List<Song> _liked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _storage.addListener(_onStorageChanged);
    _load();
  }

  @override
  void dispose() {
    _storage.removeListener(_onStorageChanged);
    super.dispose();
  }

  void _onStorageChanged() => _load();

  Future<void> _load() async {
    final l = await _storage.getLikedSongs();
    MusicLanguage lang = MusicLanguage.all;
    try {
      lang = await UserPreferences().getLanguage();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      // GLOBAL rules: 00:45–07:00 window + strict selected language.
      // Stored data untouched; the member doubles as the play queue.
      _liked = SongFilter.apply(l, language: lang);
      _loading = false;
    });
  }

  Future<void> _unlike(Song song) async {
    await _storage.toggleLikedSong(song);
    // Listener reloads; no manual refresh needed.
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<AudioPlayerService, bool>(
        (s) => s.currentSong != null);
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Liked Songs',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: AppColors.ink)),
          centerTitle: true,
        ),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              _loading
                  ? const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)))
                  : _liked.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.favorite_outline,
                                    size: 44, color: AppColors.mute),
                                SizedBox(height: 12),
                                Text('No liked songs yet',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink)),
                                SizedBox(height: 6),
                                Text(
                                    'Tap the heart on any song and it will appear here',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.inkSoft)),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(
                              left: 8,
                              right: 8,
                              top: 8,
                              bottom: hasSong ? 190 : 120),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _liked.length,
                          itemBuilder: (_, i) {
                            final s = _liked[i];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              leading: Artwork(
                                s.thumbnailUrl,
                                size: 48,
                                radius: 10,
                              ),
                              title: Text(s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink)),
                              subtitle: Text(s.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.inkSoft,
                                      fontSize: 12)),
                              trailing: IconButton(
                                icon: const Icon(Icons.favorite,
                                    size: 20, color: AppColors.ink),
                                tooltip: 'Unlike',
                                onPressed: () => _unlike(s),
                              ),
                              onTap: () => playSongs(
                                  context,
                                  song: s,
                                  queue: _liked,
                                  index: i),
                            );
                          },
                        ),
              if (hasSong)
                const Positioned(
                    left: 16, right: 16, bottom: 8, child: MiniPlayer()),
            ],
          ),
        ),
      ),
    );
  }
}
