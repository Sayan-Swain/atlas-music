import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Deep-neutral backdrop with soft gray washes. The washes stay visible
/// through frosted surfaces, so the whole UI reads as layered glass.
/// RepaintBoundary wraps each wash so content repaints never repaint
/// the background — cheap on low-end hardware.
class LiquidBackground extends StatelessWidget {
  final Widget child;
  const LiquidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper,
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -100,
            child: RepaintBoundary(
              child: _Blob(
                  size: 340,
                  color: const Color(0xFF3A3A46),
                  opacity: 0.55),
            ),
          ),
          Positioned(
            top: -80,
            right: -110,
            child: RepaintBoundary(
              child: _Blob(
                  size: 320,
                  color: const Color(0xFF2A2A33),
                  opacity: 0.7),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -40,
            right: -40,
            child: RepaintBoundary(
              child: _FloorBlob(
                  color: const Color(0xFF23232B), opacity: 0.8),
            ),
          ),
          Positioned(
            bottom: 60,
            right: -80,
            child: RepaintBoundary(
              child: _Blob(
                  size: 260,
                  color: const Color(0xFF33333D),
                  opacity: 0.5),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Blob({required this.size, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _FloorBlob extends StatelessWidget {
  final Color color;
  final double opacity;
  const _FloorBlob({required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Frosted-glass panel: translucent surface + backdrop blur + hairline
/// border + top highlight + soft shadow. BackdropFilter is used only here
/// and on the nav/mini player (a handful of blurs per screen), so scrolling
/// lists stay at full frame rate. Same API as before, no caller changes.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blur;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.opacity = 0.08,
    this.blur = 2,
  });

  static final Map<double, ImageFilter> _blurCache = {};

  static ImageFilter _filter(double sigma) =>
      _blurCache.putIfAbsent(sigma, () => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07 + opacity * 0.25),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: AppColors.glassBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: AppColors.glassHighlight,
          blurRadius: 0,
          offset: const Offset(0, 1),
        ),
      ],
    );
    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    if (blur <= 0.5) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      );
    }
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: _filter(blur),
          child: content,
        ),
      ),
    );
  }
}
