import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/audio_service.dart';
import '../widgets/floating_glass_nav.dart';
import '../widgets/liquid_background.dart';
import '../widgets/mini_player.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/welcome_flow.dart';

class AtlasMusicApp extends StatelessWidget {
  const AtlasMusicApp({super.key});

  @override
  Widget build(BuildContext context) {    return MaterialApp(
      title: 'Atlas Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const WelcomeScreen(),
    );
  }
}

/// Root tabs with floating glass nav. [userName] renders top-right only —
/// never app title in header per design spec.
class MainNavigation extends StatefulWidget {
  final String userName;
  final bool interactive;
  const MainNavigation({super.key, required this.userName, this.interactive = true});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _index = 0;
  List<Widget>? _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background pause can drift Dart UI state from native player state.
    // Re-sync on foreground so Play/Pause never appears dead. The flag
    // lets the player tell genuine completion apart from background
    // telemetry gaps — without it every background blip looks live.
    if (state == AppLifecycleState.resumed && mounted) {
      try {
        final audio = context.read<AudioPlayerService>();
        audio.setAppBackgrounded(false);
        audio.syncPlaybackState();
      } catch (_) {}
    } else if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        mounted) {
      try {
        context.read<AudioPlayerService>().setAppBackgrounded(true);
      } catch (_) {}
    }
  }

  List<Widget> _buildScreens() {
    return _screens ??= [
      HomeScreen(userName: widget.userName),
      const SearchScreen(),
      const LibraryScreen(),
      ProfileScreen(userName: widget.userName),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Selector instead of watch: rebuild shell only when song identity
    // changes (start/stop), NOT every 1/sec position tick.
    final hasSong = context.select<AudioPlayerService, bool>(
        (s) => s.currentSong != null);
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IgnorePointer(
          ignoring: !widget.interactive,
          child: IndexedStack(index: _index, children: _buildScreens()),
        ),
        bottomNavigationBar: IgnorePointer(
          ignoring: !widget.interactive,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSong)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: MiniPlayer(),
                ),
              FloatingGlassNav(
                currentIndex: _index,
                onTap: (i) => setState(() => _index = i),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
