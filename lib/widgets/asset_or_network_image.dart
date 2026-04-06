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

  @override
  Widget build(BuildContext context) {
    final s = src.trim();
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
      );
    }
    return Image.network(
      s,
      width: width,
      height: height,
      fit: fit,
    );
  }
}
