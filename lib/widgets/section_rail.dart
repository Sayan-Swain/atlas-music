import 'package:flutter/material.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../theme/app_theme.dart';
import 'artwork.dart';

/// Horizontal square-artwork rail. One widget serves Recently Played,
/// Recommended, Popular, and Playlists to keep Home lean.
class SectionRail extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> cards;

  const SectionRail({
    super.key,
    required this.title,
    required this.cards,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction ?? () {},
                  child: Text(actionLabel!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }
}

class SquareSongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  const SquareSongCard({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Artwork(
                song.thumbnailUrl,
                size: 124,
                radius: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class SquarePlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  const SquarePlaylistCard({super.key, required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final art = playlist.thumbnailUrl ?? '';
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.mist,
                    AppColors.line,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: art.isEmpty
                  ? const Icon(Icons.queue_music,
                      color: AppColors.mute, size: 36)
                  : Artwork(art, size: 124, radius: 16),
            ),
            const SizedBox(height: 8),
            Text(playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${playlist.songs.length} songs',
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}
