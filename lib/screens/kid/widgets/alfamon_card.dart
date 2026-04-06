import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Styrke-farver matchende kortdesignet (POWER, SPEED, MIND, MAGIC, ARMOR, CHARM)
const strengthColors = [
  Color(0xFFBA2A13), // POWER - rød
  Color(0xFF22556B), // SPEED - blå/teal
  Color(0xFF67314F), // MIND - lilla
  Color(0xFF54651D), // MAGIC - grøn
  Color(0xFFB85518), // ARMOR - orange
  Color(0xFFC53C3E), // CHARM - pink
];

/// Ikoner for hver styrke (Power, Speed, Mind, Magic, Armor, Charm)
const strengthIcons = [
  Icons.bolt,              // Power
  Icons.speed,            // Speed
  Icons.psychology,       // Mind
  Icons.auto_awesome,     // Magic
  Icons.shield,           // Armor
  Icons.favorite,         // Charm
];

/// Alfamon-navn → type (Fleximon, Powermon, Crazymon, Cutimon)
const _alfamonTypes = {
  'apego': 'Fleximon',
  'bazzle': 'Fleximon',
  'cekimon': 'Powermon',
  'deedoo': 'Crazymon',
  'elisboo': 'Cutimon',
  'flizard': 'Fleximon',
  'gemitsui': 'Powermon',
  'harkal': 'Fleximon',
  'iitle': 'Cutimon',
  'jadrik': 'Crazymon',
  'klyax': 'Powermon',
  'l-mii': 'Cutimon',
  'master': 'Powermon',
  'nimbroo': 'Powermon',
  'oglah': 'Crazymon',
  'peppapop': 'Fleximon',
  'quibbty': 'Fleximon',
  'r-minax': 'Crazymon',
  's-males': 'Cutimon',
  'tegorm': 'Powermon',
  'ummiroo': 'Fleximon',
  'vindleak': 'Fleximon',
  'windioo': 'Powermon',
  'x-bug': 'Powermon',
  'yalfax': 'Cutimon',
  'zebra': 'Powermon',
  'aelgor': 'Fleximon',
  'armok': 'Powermon',
  // Variant-stavninger fra appen
  'quibbly': 'Fleximon',
  'iffle': 'Cutimon',
  'atiach': 'Powermon',
  'wigloo': 'Fleximon',
  'bezzle': 'Fleximon',
  'kavax': 'Powermon',
  'kåvax': 'Powermon',
  's-nake': 'Cutimon',
};

class AlfamonCardData {
  final String name;
  final String? letter;
  final String imageUrl;
  final String? assetPath;
  final List<AlfamonStrength> strengths;

  AlfamonCardData({
    required this.name,
    this.letter,
    required this.imageUrl,
    this.assetPath,
    required this.strengths,
  });
}

class AlfamonStrength {
  final int strengthIndex;
  final String name;
  final int value;

  AlfamonStrength({
    required this.strengthIndex,
    required this.name,
    required this.value,
  });
}

/// Billede til kort: lokalt SVG-asset eller netværksbillede. BoxFit.contain viser hele figuren.
/// Prøver asset først; ved fejl (load eller parse) falder tilbage til netværksbillede.
class _CardImage extends StatefulWidget {
  final String? assetPath;
  final String imageUrl;

  const _CardImage({this.assetPath, required this.imageUrl});

  @override
  State<_CardImage> createState() => _CardImageState();
}

class _CardImageState extends State<_CardImage> {
  static final _assetCache = <String, bool>{};
  static final _loggedCards = <String>{};
  static Map<String, String>? _assetLookupByCanonical;
  static Future<void>? _assetLookupInit;

  void _log(String tag, String message, [Object? error, StackTrace? stack]) {
    developer.log(message, name: 'AlfamonCard.$tag', error: error, stackTrace: stack);
  }

  String _canonicalizePath(String input) {
    var s = input.toLowerCase();
    // Gør precomposed/decomposed nordiske tegn mere robuste.
    s = s
        .replaceAll('å', 'a')
        .replaceAll('æ', 'ae')
        .replaceAll('ø', 'oe');
    // Fjern combining marks (fx a + ring).
    s = s.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
    // Sammenlign kun på sikre path-tegn.
    s = s.replaceAll(RegExp(r'[^a-z0-9/_\.\-]'), '');
    return s;
  }

  Future<void> _ensureAssetLookup() async {
    if (_assetLookupByCanonical != null) return;
    _assetLookupInit ??= () async {
      try {
        final manifestRaw = await rootBundle.loadString('AssetManifest.json');
        final decoded = json.decode(manifestRaw);
        if (decoded is! Map<String, dynamic>) {
          _assetLookupByCanonical = {};
          return;
        }
        final map = <String, String>{};
        for (final key in decoded.keys) {
          if (!key.startsWith('assets/')) continue;
          final canonical = _canonicalizePath(key);
          map.putIfAbsent(canonical, () => key);
        }
        _assetLookupByCanonical = map;
        _log('asset', 'AssetManifest loaded (${map.length} assets)');
      } catch (e, st) {
        _assetLookupByCanonical = {};
        _log('asset', 'FEJL ved load af AssetManifest', e, st);
      }
    }();
    await _assetLookupInit;
  }

  /// Prøver WebP, PNG, JPG, SVG i rækkefølge (raster viser korrekt; SVG har flutter_svg-problemer).
  Future<String?> _resolveFirstAvailablePath(List<String> pathsToTry) async {
    for (final p in pathsToTry) {
      final resolved = await _resolveAssetPath(p);
      if (resolved != null) return resolved;
    }
    return null;
  }

  bool _isRasterPath(String path) =>
      path.endsWith('.webp') ||
      path.endsWith('.png') ||
      path.endsWith('.jpg') ||
      path.endsWith('.jpeg');

  Future<String?> _resolveAssetPath(String requestedPath) async {
    if (_assetCache[requestedPath] == true) return requestedPath;
    try {
      await rootBundle.load(requestedPath);
      _assetCache[requestedPath] = true;
      _log('asset', 'OK: $requestedPath');
      return requestedPath;
    } catch (e, st) {
      _log('asset', 'FEJL rootBundle.load: $requestedPath', e, st);
    }

    await _ensureAssetLookup();
    final canonical = _canonicalizePath(requestedPath);
    final altPath = _assetLookupByCanonical?[canonical];
    if (altPath != null && altPath != requestedPath) {
      try {
        await rootBundle.load(altPath);
        _assetCache[requestedPath] = true;
        _assetCache[altPath] = true;
        _log('asset', 'Recovered via AssetManifest: $requestedPath -> $altPath');
        return altPath;
      } catch (e, st) {
        _log('asset', 'Alt path fejlede: $altPath', e, st);
      }
    }

    _assetCache[requestedPath] = false;
    return null;
  }

  Widget _buildNetworkFallback({String? reason}) {
    final imageUrl = widget.imageUrl;
    const fit = BoxFit.contain;
    if (imageUrl.isEmpty) {
      _log('fallback', 'imageUrl tom - viser intet');
      return const SizedBox.expand();
    }
    if (reason != null && !_loggedCards.contains('$imageUrl-$reason')) {
      _loggedCards.add('$imageUrl-$reason');
      _log('fallback', 'Bruger Image.network (fordi: $reason) - ${imageUrl.length > 60 ? "${imageUrl.substring(0, 60)}..." : imageUrl}');
    }
    return Image.network(
      imageUrl,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, err, st) {
        _log('network', 'Image.network fejlede', err, st);
        return const SizedBox.expand();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = widget.assetPath;
    final imageUrl = widget.imageUrl;
    const fit = BoxFit.contain;

    if (assetPath == null || assetPath.isEmpty) {
      _log('input', 'assetPath=null/empty, imageUrl=${imageUrl.isEmpty ? "tom" : "har URL"}');
      return _buildNetworkFallback(reason: 'ingen assetPath');
    }

    // Prøv WebP, PNG, JPG først (viser korrekt); SVG har flutter_svg-problemer med base64-billeder
    final basePath = assetPath.replaceAll('.svg', '');
    final pathsToTry = ['$basePath.webp', '$basePath.png', '$basePath.jpg', assetPath];

    return FutureBuilder<String?>(
      key: ValueKey(assetPath),
      future: _resolveFirstAvailablePath(pathsToTry),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data;
        if (resolvedPath != null) {
          if (_isRasterPath(resolvedPath)) {
            return Image.asset(
              resolvedPath,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                _log('image', 'Image.asset fejlede for $resolvedPath', error, stackTrace);
                return _buildNetworkFallback(reason: 'raster load fejl');
              },
            );
          }
          return SvgPicture.asset(
            resolvedPath,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            allowDrawingOutsideViewBox: true,
            errorBuilder: (context, error, stackTrace) {
              _log('svg', 'SvgPicture.asset fejlede for $resolvedPath', error, stackTrace);
              return _buildNetworkFallback(reason: 'svg parse/render fejl');
            },
          );
        }
        if (snapshot.connectionState == ConnectionState.done && imageUrl.isNotEmpty) {
          return _buildNetworkFallback(reason: 'asset findes ikke');
        }
        if (imageUrl.isNotEmpty) {
          return _buildNetworkFallback(reason: 'venter på asset check');
        }
        return const SizedBox.expand();
      },
    );
  }
}

/// Kortbagsdesign – samme størrelse som AlfamonCard, bruges til modstanderens bunke.
class AlfamonCardBack extends StatelessWidget {
  final double width;

  const AlfamonCardBack({super.key, this.width = 103.5}); // Samme som AlfamonCard

  @override
  Widget build(BuildContext context) {
    final height = AlfamonCard.heightForWidth(width);
    final borderColor = const Color(0xFF4A3728);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF5C4033),
                Color(0xFF4A3728),
                Color(0xFF3D2E20),
              ],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: width * 0.4, color: const Color(0xFFE8DCC8).withValues(alpha: 0.9)),
                  const SizedBox(height: 4),
                  Text(
                    'ALFAMON',
                    style: TextStyle(
                      fontSize: width >= 100 ? 12 : 8,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFE8DCC8).withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alfamon-kort i trading card-stil: brun ramme, rød gradient, header med bogstav,
/// illustration, 6 styrkebokse, og "ALFAMON" type.
/// Kortformat 1.1:1.6 (bredde:højde) – altid samme proportioner
const double cardAspectRatio = 1.6 / 1.1;

class AlfamonCard extends StatelessWidget {
  /// Returnerer kortets højde for en given bredde – format 1.1×1.6
  static double heightForWidth(double width) => width * cardAspectRatio;

  final AlfamonCardData card;
  final int? selectedStrengthIndex;
  final bool isWinner;
  final double width;

  const AlfamonCard({
    super.key,
    required this.card,
    this.selectedStrengthIndex,
    this.isWinner = false,
    this.width = 103.5,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * cardAspectRatio;
    final borderColor = const Color(0xFF4A3728);
    final textColor = const Color(0xFFE8DCC8);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: isWinner ? 12 : 6,
            offset: const Offset(0, 4),
          ),
          if (isWinner)
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Solid baggrund – undgår at se igennem transparente SVG'er
            Container(
              color: const Color(0xFF4A3728),
              width: double.infinity,
              height: double.infinity,
            ),
            // Billede: prøv lokalt asset først, ellers netværksbillede
            _CardImage(assetPath: card.assetPath, imageUrl: card.imageUrl),
            // Brun overskrift ovenpå billedets top
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width >= 120 ? 8 : 4,
                  vertical: width >= 120 ? 4 : 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5C4033).withValues(alpha: 0.95),
                ),
                child: Row(
                  children: [
                    Text(
                      (card.letter ?? (card.name.isNotEmpty ? card.name[0] : '?'))
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: width >= 120 ? 22 : 16,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    SizedBox(width: width >= 120 ? 6 : 4),
                    Expanded(
                      child: Text(
                        card.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: width >= 120 ? 12 : 9,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Evnefelter og bundmenu ovenpå billedets bund
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(width >= 120 ? 6 : 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFFB33A00).withValues(alpha: 0.95),
                      const Color(0xFF5C4033).withValues(alpha: 0.98),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildStatBox(card, 0, textColor, width)),
                        const SizedBox(width: 2),
                        Expanded(child: _buildStatBox(card, 1, textColor, width)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(child: _buildStatBox(card, 2, textColor, width)),
                        const SizedBox(width: 2),
                        Expanded(child: _buildStatBox(card, 3, textColor, width)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(child: _buildStatBox(card, 4, textColor, width)),
                        const SizedBox(width: 2),
                        Expanded(child: _buildStatBox(card, 5, textColor, width)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _alfamonTypes[card.name.toLowerCase().trim()] ?? 'ALFAMON',
                      style: TextStyle(
                        fontSize: width >= 120 ? 10 : 7,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(AlfamonCardData card, int index, Color textColor, double cardWidth) {
    final strength = card.strengths
        .where((s) => s.strengthIndex == index)
        .firstOrNull;
    final value = strength?.value ?? 0;
    final color = index < strengthColors.length
        ? strengthColors[index]
        : Colors.grey;
    final icon = index < strengthIcons.length ? strengthIcons[index] : Icons.help_outline;

    final isSelected = selectedStrengthIndex == index;
    final iconSize = cardWidth >= 120 ? 12.0 : 8.0;
    final fontSize = cardWidth >= 120 ? 9.0 : 6.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: cardWidth >= 120 ? 4 : 1,
        vertical: cardWidth >= 120 ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? Colors.white : Colors.black26,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: Colors.white),
          SizedBox(width: cardWidth >= 120 ? 5 : 3),
          Text(
            '$value',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

}

/// Evneknapper til valg af styrke – altid samme layout og farver.
/// Kolonne 1: Power, Mind, Armor. Kolonne 2: Speed, Magic, Charm.
class StrengthChoiceGrid extends StatelessWidget {
  final List<AlfamonStrength> strengths;
  final void Function(int index) onSelect;

  const StrengthChoiceGrid({
    super.key,
    required this.strengths,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const col1 = [0, 2, 4];
    const col2 = [1, 3, 5];

    AlfamonStrength? getStrength(int index) {
      final list = strengths.where((x) => x.strengthIndex == index).toList();
      return list.isEmpty ? null : list.first;
    }

    Widget buildChip(int index) {
      final s = getStrength(index);
      if (s == null) return const SizedBox.shrink();
      final color = index < strengthColors.length
          ? strengthColors[index]
          : Colors.grey;
      final icon = index < strengthIcons.length ? strengthIcons[index] : Icons.help_outline;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => onSelect(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 100, maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${s.name}: ${s.value}',
                      style: const TextStyle(
                        color: Color(0xFFE8DCC8),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: col1.map((i) => buildChip(i)).toList(),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: col2.map((i) => buildChip(i)).toList(),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
