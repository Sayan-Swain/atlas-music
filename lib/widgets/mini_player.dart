import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'app_transitions.dart';
import 'artwork.dart';
import '../screens/player_screen.dart';

/// Floating frosted-glass mini player. Thumb+text navigate; transport
/// buttons sit strictly outside the nav InkWell so skip taps never
/// push routes. Backdrop blur keeps the list behind subtly visible.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  void _openPlayer(BuildContext context) {
    final cur = ModalRoute.of(context)?.settings.name;
    if (cur == PlayerScreen.routeName) return;
    pushAppPage(
      context,
      const PlayerScreen(),
      routeName: PlayerScreen.routeName,
    );
  }

  Future<void> _skip(BuildContext context, AudioPlayerService audio,
      Future<bool> Function() action) async {
    final ok = await action();
    if (!ok && context.mounted) {
      final reason = audio.lastFailure;
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

  static final _blur = ImageFilter.blur(sigmaX: 16, sigmaY: 16);
  static final _shadow = BoxShadow(
    color: Colors.black.withValues(alpha: 0.4),
    blurRadius: 20,
    offset: const Offset(0, 10),
  );

  @override
  Widget build(BuildContext context) {
    // Shell subscribes transport only. Position tick lives in
    // [_MiniProgress] so blur/shadow/artwork never rebuild per second.
    final Song? song =
        context.select<AudioPlayerService, Song?>((s) => s.currentSong);
    final bool playing =
        context.select<AudioPlayerService, bool>((s) => s.isPlaying);
    final bool isLoading =
        context.select<AudioPlayerService, bool>((s) => s.isLoading);
    final audio = context.read<AudioPlayerService>();
    if (song == null) return const SizedBox.shrink();

    final loading = isLoading && !playing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: _blur,
        child: Container(
          height: 70,
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [_shadow],
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey('mini_nav_area'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openPlayer(context),
                          child: Row(
                            children: [
                              Artwork(
                                song.thumbnailUrl,
                                size: 42,
                                radius: 10,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppColors.ink)),
                                    Text(song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.inkSoft,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    else ...[
                      IconButton(
                        key: const ValueKey('mini_prev'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_previous,
                            size: 24, color: AppColors.inkSoft),
                        onPressed: () =>
                            _skip(context, audio, audio.playPrevious),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: IconButton(
                          key: const ValueKey('mini_play_pause'),
                          visualDensity: VisualDensity.compact,
                          icon: PlayPauseIcon(
                            playing: playing,
                            size: 26,
                            color: AppColors.charcoal,
                          ),
                          onPressed: () {
                            if (playing) {
                              audio.pause();
                            } else {
                              audio.resume();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('mini_skip_next'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_next,
                            size: 24, color: AppColors.inkSoft),
                        onPressed: () => _skip(context, audio,
                            () => audio.playNext(0, true)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const _MiniProgress(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress tick isolated: only this 2px bar rebuilds per second.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  static const _fill = AlwaysStoppedAnimation<Color>(Colors.white);

  @override
  Widget build(BuildContext context) {
    final int posSec = context.select<AudioPlayerService, int>(
        (s) => s.position.inSeconds);
    final int durSec = context.select<AudioPlayerService, int>(
        (s) => s.duration.inSeconds);
    final max = durSec > 0 ? durSec.toDouble() : 1.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: (posSec.toDouble() / max).clamp(0.0, 1.0),
        minHeight: 2,
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        valueColor: _fill,
      ),
    );
  }
}
