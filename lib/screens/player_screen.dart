import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_transitions.dart';
import '../widgets/artwork.dart';
import '../widgets/liquid_background.dart';
import '../widgets/lyrics_sheet.dart';

class PlayerScreen extends StatefulWidget {
  static const routeName = '/player';
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final StorageService _storageService = StorageService();
  bool _isLiked = false;
  String? _likedForId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkIfLiked();
  }

  Future<void> _checkIfLiked() async {
    final audioService = context.read<AudioPlayerService>();
    final cur = audioService.currentSong;
    if (cur != null && _likedForId != cur.id) {
      _likedForId = cur.id;
      final liked = await _storageService.isSongLiked(cur.id);
      if (mounted && _likedForId == cur.id) {
        setState(() => _isLiked = liked);
      }
    }
  }

  Future<void> _toggleLike() async {
    final audioService = context.read<AudioPlayerService>();
    if (audioService.currentSong != null) {
      await _storageService.toggleLikedSong(audioService.currentSong!);
      // Explicit toggle bypasses song-id guard so heart refreshes.
      _likedForId = null;
      _checkIfLiked();
    }
  }

  Future<void> _skip(Future<bool> Function() action) async {
    final ok = await action();
    if (!ok && mounted) {
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

  @override
  Widget build(BuildContext context) {
    // Selective subscriptions: parent rebuilds on song/transport only,
    // never on 1/sec position ticks (those live in [_PlayerSlider]).
    final audioService = context.read<AudioPlayerService>();
    final song =
        context.select<AudioPlayerService, Song?>((s) => s.currentSong);
    final isPlaying = context.select<AudioPlayerService, bool>(
        (s) => s.isPlaying);
    final shuffle = context.select<AudioPlayerService, bool>(
        (s) => s.shuffleEnabled);
    final loop = context.select<AudioPlayerService, LoopMode>(
        (s) => s.loopMode);
    final artSize = (MediaQuery.of(context).size.width - 104)
        .clamp(160.0, 320.0);

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                size: 30, color: AppColors.ink),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Now Playing',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.ink)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(
                _isLiked ? Icons.favorite : Icons.favorite_border,
                color: _isLiked ? Colors.white : AppColors.mute,
              ),
              onPressed: _toggleLike,
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            if (song != null) ...[
                              RepaintBoundary(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 40),
                                  child: GlassPanel(
                                    radius: 28,
                                    padding: const EdgeInsets.all(12),
                                    opacity: 0.09,
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Artwork(
                                        song.thumbnailUrl,
                                        size: artSize,
                                        radius: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32),
                                child: Column(
                                  children: [
                                    Text(song.title,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 6),
                                    Text(song.artist,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.inkSoft),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 32),
                                child: _PlayerSlider(),
                              ),
                              const SizedBox(height: 10),
                              GlassPanel(
                                radius: 26,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                opacity: 0.08,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.shuffle,
                                          color: shuffle
                                              ? Colors.white
                                              : AppColors.mute,
                                          size: 24),
                                      onPressed: audioService.toggleShuffle,
                                    ),
                                    IconButton(
                                      key: const ValueKey('player_prev'),
                                      icon: const Icon(Icons.skip_previous,
                                          size: 34, color: AppColors.ink),
                                      onPressed: () =>
                                          _skip(audioService.playPrevious),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                                alpha: 0.4),
                                            blurRadius: 18,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: PlayPauseIcon(
                                          playing: isPlaying,
                                          size: 40,
                                          color: AppColors.charcoal,
                                        ),
                                        onPressed: () {
                                          if (isPlaying) {
                                            audioService.pause();
                                          } else {
                                            audioService.resume();
                                          }
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('player_next'),
                                      icon: const Icon(Icons.skip_next,
                                          size: 34, color: AppColors.ink),
                                      onPressed: () => _skip(() =>
                                          audioService.playNext(0, true)),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        loop == LoopMode.one
                                            ? Icons.repeat_one
                                            : Icons.repeat,
                                        color: loop == LoopMode.off
                                            ? AppColors.mute
                                            : Colors.white,
                                        size: 24,
                                      ),
                                      onPressed: audioService.cycleRepeatMode,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      key: const ValueKey('player_lyrics'),
                                      icon: const Icon(Icons.lyrics_outlined,
                                          size: 18),
                                      label: const Text('Lyrics'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.ink,
                                        side: const BorderSide(
                                          color: AppColors.line,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10),
                                      ),
                                      onPressed: () {
                                        final s = song;
                                        if (s == null) return;
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => LyricsSheet(
                                            song: s,
                                            audio: audioService,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.download_outlined,
                                        size: 18),
                                      label: const Text('Download'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.ink,
                                        side: const BorderSide(
                                          color: AppColors.line,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10),
                                      ),
                                      onPressed: () async {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => const AlertDialog(
                                            content: Column(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(),
                                                SizedBox(height: 16),
                                                Text('Downloading...'),
                                              ],
                                            ),
                                          ),
                                        );
                                        final ok = await audioService
                                            .downloadCurrentSong();
                                        if (!mounted) return;
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(ok
                                                ? 'Download completed'
                                                : 'Download failed'),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                            ] else ...[
                              const SizedBox(height: 80),
                              const Icon(Icons.music_note,
                                  size: 88, color: AppColors.mute),
                              const SizedBox(height: 12),
                              const Text('No song playing',
                                  style:
                                      TextStyle(color: AppColors.inkSoft)),
                              const SizedBox(height: 40),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Slider + time labels isolated: only this row rebuilds per second.
class _PlayerSlider extends StatefulWidget {
  const _PlayerSlider();

  @override
  State<_PlayerSlider> createState() => _PlayerSliderState();
}

class _PlayerSliderState extends State<_PlayerSlider> {
  double? _dragValue;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final posSec = context.select<AudioPlayerService, int>(
        (s) => s.position.inSeconds);
    final durSec = context.select<AudioPlayerService, int>(
        (s) => s.duration.inSeconds);
    final audio = context.read<AudioPlayerService>();
    final max = durSec > 0 ? durSec.toDouble() : 1.0;
    final value = (_dragValue ?? posSec.toDouble()).clamp(0.0, max);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white,
            inactiveTrackColor: AppColors.line,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              audio.seek(Duration(seconds: v.toInt()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(Duration(seconds: posSec)),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSoft)),
              Text(_fmt(durSec > 0 ? Duration(seconds: durSec) : Duration.zero),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSoft)),
            ],
          ),
        ),
      ],
    );
  }
}