import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/user_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/app_transitions.dart';
import '../widgets/liquid_background.dart';
import 'onboarding_screen.dart';
import 'onboarding_preferences.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/floating_glass_nav.dart';
import '../services/audio_service.dart';

/// Owns first-run + future-launch name flight:
/// center name → top-right header, home fades in underneath.
/// BACKGROUND IS ALWAYS VISIBLE — no black-screen gap during flight.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final UserPrefs _prefs = UserPrefs();
  String? _name;
  bool _loading = true;
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final saved = await _prefs.getName();
    final done = await _prefs.isOnboardingDone();
    if (!mounted) return;
    final hasName = saved != null && saved.isNotEmpty;
    setState(() {
      _loading = false;
      _name = saved;
      // Preferences only when named but never completed. Language "all"
      // is valid — completion is stamped explicitly, never inferred.
      _showPreferences = hasName && !done;
    });
    if (hasName && done) {
      setState(() => _showHome = true);
    }
  }

  Future<void> _onNameComplete(String name) async {
    await _prefs.setName(name);
    if (!mounted) return;
    setState(() => _name = name);
    await _pickAvatar();
    if (!mounted) return;
    setState(() => _showPreferences = true);
  }

  Future<void> _pickAvatar() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Choose Avatar',
            style: TextStyle(color: AppColors.ink)),
        content: SizedBox(
          width: 320,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: 8,
            itemBuilder: (_, i) {
              if (i == 0) {
                return ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mist),
                  child: const Icon(Icons.skip_next,
                      color: AppColors.inkSoft),
                );
              }
              if (i == 1) {
                return ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (picked == null) return;
                    final dir = await getApplicationDocumentsDirectory();
                    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
                    final newPath = '${dir.path}/$fileName';
                    await picked.saveTo(newPath);
                    await _prefs.setAvatar(newPath);
                    if (mounted) setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mist),
                  child: const Icon(Icons.add_a_photo,
                      color: AppColors.inkSoft),
                );
              }
              final imgIdx = i - 1;
              final url = 'https://i.pravatar.cc/150?img=${imgIdx + 1}';
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, url),
                child: CircleAvatar(backgroundImage: NetworkImage(url), radius: 32),
              );
            },
          ),
        ),
      ),
    );
    if (result != null) {
      await _prefs.setAvatar(result);
    }
  }

  bool _showPreferences = false;

  Future<void> _onPreferencesComplete() async {
    setState(() {
      _showPreferences = false;
      _showHome = true;
    });
  }



  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_name == null) {
      return SafeArea(
        child: OnboardingContent(onContinue: _onNameComplete),
      );
    }
    if (_name != null && !_showHome && _showPreferences) {
      return OnboardingPreferences(
        onComplete: _onPreferencesComplete,
      );
    }
    return MainNavigation(userName: _name!);
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
    // Re-sync on foreground so Play/Pause never appears dead.
    if (!mounted) return;
    try {
      final audio = context.read<AudioPlayerService>();
      if (state == AppLifecycleState.resumed) {
        audio.setAppBackgrounded(false);
        audio.syncPlaybackState();
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        audio.setAppBackgrounded(true);
      }
    } catch (_) {}
  }

  List<Widget> _buildScreens() {
    return _screens ??= [
      FadeSlideIn(child: HomeScreen(userName: widget.userName)),
      const FadeSlideIn(child: SearchScreen()),
      const FadeSlideIn(child: LibraryScreen()),
      FadeSlideIn(child: ProfileScreen(userName: widget.userName)),
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
              ClipRect(
                child: AnimatedSwitcher(
                  duration: AppMotion.modal,
                  switchInCurve: AppMotion.curve,
                  switchOutCurve: AppMotion.curve,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: hasSong
                      ? const Padding(
                          key: ValueKey('mini_on'),
                          padding:
                              EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: MiniPlayer(),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('mini_off')),
                ),
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