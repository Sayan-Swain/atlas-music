import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Single cached artwork path. Memory + disk cache, bounded decode size,
/// no re-fetch on every 1/sec position tick. Gapless so song changes
/// don't flash. Square by default ([size]); pass [width]+[height] for
/// fixed-ratio boxes (rails, headers).
class Artwork extends StatelessWidget {
  final String url;
  final double? size;
  final double? width;
  final double radius;
  final double? height;
  final BoxFit fit;
  final bool fillWidth;

  const Artwork(
    this.url, {
    super.key,
    this.size,
    this.width,
    this.radius = 12,
    this.height,
    this.fit = BoxFit.cover,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final computedSize = size ?? (mq.size.width * 0.4).clamp(100, 300);
    final w = width ?? computedSize;
    final h = height ?? (width ?? computedSize);
    final px = ((width ?? computedSize) * mq.devicePixelRatio).round();
    if (url.isEmpty) return _fallback(w, h);
    // Single decode per art: contain over cheap mist fill. Prior double
    // stack fetched/decoded same URL twice per large card.
    if (!fillWidth && w >= 70) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: w,
          height: h,
          color: AppColors.mist,
          child: CachedNetworkImage(
            imageUrl: url,
            cacheKey: '$url-$px',
            width: w,
            height: h,
            fit: BoxFit.contain,
            memCacheWidth: px.clamp(96, 1024),
            fadeInDuration: const Duration(milliseconds: 150),
            fadeOutDuration: const Duration(milliseconds: 120),
            useOldImageOnUrlChange: true,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => _fallback(w, h),
          ),
        ),
      );
    }
    final imgW = fillWidth ? null : w;
    final imgH = fillWidth ? null : h;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: fillWidth ? double.infinity : w,
        height: h,
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: '$url-$px',
          width: imgW,
          height: imgH,
          fit: fit,
          memCacheWidth: px.clamp(96, 1024),
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 120),
          useOldImageOnUrlChange: true,
          placeholder: (_, __) => Container(
            width: imgW,
            height: h,
            color: AppColors.mist,
          ),
          errorWidget: (_, __, ___) => _fallback(imgW ?? computedSize, h),
        ),
      ),
    );
  }

  Widget _fallback(double w, double h) => Container(
        width: w,
        height: h,
        color: AppColors.mist,
        child: const Icon(Icons.music_note, color: AppColors.mute),
      );
}
