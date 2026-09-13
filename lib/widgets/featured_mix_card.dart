import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'app_transitions.dart';
import 'artwork.dart';
import 'liquid_background.dart';

/// Large white hero card. Bound to real playback state:
/// shows current song when playing, else featured fallback.
class FeaturedMixCard extends StatelessWidget {
  final String title;
  final String artist;
  final String artworkUrl;
  final VoidCallback onOpenPlayer;

  const FeaturedMixCard({
    super.key,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.onOpenPlayer,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to transport + 1/sec position tick + track identity.
    final isPlaying = context.select<AudioPlayerService, bool>(
        (s) => s.isPlaying);
    final isLoading = context.select<AudioPlayerService, bool>(
        (s) => s.isLoading);
    final int posSec = context.select<AudioPlayerService, int>(
        (s) => s.position.inSeconds);
    final int durSec = context.select<AudioPlayerService, int>(
        (s) => s.duration.inSeconds);
    context.select<AudioPlayerService, String?>((s) => s.currentSong?.id);
    final audio = context.read<AudioPlayerService>();
    final pos = Duration(seconds: posSec);
    final dur = durSec > 0
        ? Duration(seconds: durSec)
        : const Duration(minutes: 4, seconds: 5);
    final progress = dur.inSeconds > 0
        ? (pos.inSeconds / dur.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final showSpinner = isLoading && !isPlaying;

    Future<void> skip(Future<bool> Function() fn) async {
      final ok = await fn();
      if (!ok && context.mounted) {
        final reason =
            context.read<AudioPlayerService>().lastFailure;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason == null
                ? 'Could not play that song'
                : 'Could not play: $reason'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }

    return GlassPanel(
      radius: 28,
      padding: const EdgeInsets.all(16),
      opacity: 0.10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onOpenPlayer,
                child: Artwork(
                  artworkUrl,
                  size: 112,
                  radius: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.glassBorder),
                      ),
                      child: const Text(
                        'Featured Mix',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSoft),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor:
                  Colors.white.withValues(alpha: 0.14),
              valueColor:
                  const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.inkSoft)),
              Text(_fmt(dur),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('featured_prev'),
                icon: const Icon(Icons.skip_previous,
                    size: 30, color: AppColors.inkSoft),
                onPressed: () => skip(audio.playPrevious),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: showSpinner
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.charcoal),
                        ),
                      )
                    : IconButton(
                        key: const ValueKey('featured_play_pause'),
                        icon: PlayPauseIcon(
                          playing: isPlaying,
                          size: 34,
                          color: AppColors.charcoal,
                        ),
                        onPressed: () {
                          if (isPlaying) {
                            audio.pause();
                          } else {
                            audio.resume();
                          }
                        },
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('featured_next'),
                icon: const Icon(Icons.skip_next,
                    size: 30, color: AppColors.inkSoft),
                onPressed: () => skip(audio.playNext),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
