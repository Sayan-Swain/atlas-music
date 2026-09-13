import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Consistent 240ms fade + slide + scale route used for the player and
/// playlist pages. Framework-driven (no controllers to leak), back gesture
/// stays interactive, input is never blocked.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required Widget Function(BuildContext) builder,
    super.settings,
  }) : super(
          transitionDuration: AppMotion.page,
          reverseTransitionDuration: AppMotion.page,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.curve,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale:
                      Tween<double>(begin: 0.98, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Push with the shared transition. Drop-in for MaterialPageRoute.
Future<T?> pushAppPage<T>(BuildContext context, Widget page,
    {String? routeName}) {
  return Navigator.push<T>(
    context,
    AppPageRoute<T>(
      builder: (_) => page,
      settings:
          routeName == null ? null : RouteSettings(name: routeName),
    ),
  );
}

/// One-shot fade + rise for freshly mounted content (headers, cards).
/// TweenAnimationBuilder owns its controller internally: no manual vsync,
/// no dispose bugs, no restart on parent rebuilds.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppMotion.entrance + delay,
      curve: AppMotion.curve,
      builder: (context, value, child) {
        final v = ((value * (AppMotion.entrance + delay).inMilliseconds -
                    delay.inMilliseconds) /
                AppMotion.entrance.inMilliseconds)
            .clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Animated play/pause swap: fade + scale, fixed size so layout never jumps.
class PlayPauseIcon extends StatelessWidget {
  final bool playing;
  final double size;
  final Color color;
  const PlayPauseIcon(
      {super.key,
      required this.playing,
      required this.size,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.micro,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        playing ? Icons.pause : Icons.play_arrow,
        key: ValueKey(playing),
        size: size,
        color: color,
      ),
    );
  }
}
