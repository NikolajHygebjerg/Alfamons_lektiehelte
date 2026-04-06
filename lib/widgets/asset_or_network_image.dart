import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// [Image.network] for http(s); [Image.asset] / [SvgPicture.asset] for `assets/` og `packages/…`.
class AssetOrNetworkImage extends StatelessWidget {
  const AssetOrNetworkImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String src;
  final double? width;
  final double? height;
  final BoxFit fit;

  static int? _cachePx(double? logical, double dpr) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    return (logical * dpr).round().clamp(1, 2048);
  }

  Widget _broken(BuildContext context) {
    final w = width;
    final sz = (w != null && w.isFinite && w > 0 && w < 160) ? w * 0.4 : 36.0;
    return ColoredBox(
      color: Colors.black12,
      child: Center(
        child: Icon(Icons.image_not_supported_outlined, size: sz, color: Colors.black38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = src.trim();
    if (s.isEmpty) {
      return _broken(context);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);

    if (s.startsWith('assets/') || s.startsWith('packages/')) {
      final lower = s.toLowerCase();
      if (lower.endsWith('.svg')) {
        return SvgPicture.asset(
          s,
          width: width,
          height: height,
          fit: fit,
        );
      }
      return Image.asset(
        s,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: _cachePx(width, dpr),
        cacheHeight: _cachePx(height, dpr),
        errorBuilder: (ctx, err, st) => _broken(ctx),
      );
    }
    return Image.network(
      s,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: _cachePx(width, dpr),
      cacheHeight: _cachePx(height, dpr),
      errorBuilder: (ctx, err, st) => _broken(ctx),
    );
  }
}
