import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../screens/player_screen.dart';
import 'app_transitions.dart';

/// Plays a song and shows a snackbar instead of failing silently.
/// Push-first: player opens instantly, load happens behind it. Old
/// push-after-load made a delayed push land right after a skip tap,
/// looking like skip itself navigated.
Future<void> playSongs(
  BuildContext context, {
  required Song song,
  required List<Song> queue,
  required int index,
  bool openPlayer = false,
  bool autoplayOnEnd = true,
  String? queueOrigin,
}) async {
  if (openPlayer && context.mounted) {
    // Guard duplicate push: double-tap on a card used to stack two
    // identical PlayerScreens, so a later skip/back felt like skip
    // opened a new page.
    final cur = ModalRoute.of(context)?.settings.name;
    if (cur != PlayerScreen.routeName) {
      pushAppPage(
        context,
        const PlayerScreen(),
        routeName: PlayerScreen.routeName,
      );
    }
  }
  try {
    final ok = await context.read<AudioPlayerService>().playSong(
          song,
          queue: queue,
          index: index,
          autoplayOnEnd: autoplayOnEnd,
          queueOrigin: queueOrigin,
        );
    // Silent FAIL (no exception): toast only if this tap still owns
    // playback AND it sits silent — a same-song double-tap's first load
    // returns false while the second load flies (or already plays), and
    // must not cry wolf over audible music. A newer attempt reports
    // for itself.
    final audio = context.read<AudioPlayerService>();
    if (!ok &&
        context.mounted &&
        audio.currentSong?.id == song.id &&
        !audio.isPlaying &&
        !audio.isLoading) {
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
  } catch (e) {
    if (context.mounted) {
      // Full error in selectable dialog: snackbar truncation hid root cause.
      final msg = e.toString().replaceAll(RegExp(r'\s+'), ' ');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Play failed'),
          content: SingleChildScrollView(child: SelectableText(msg)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
