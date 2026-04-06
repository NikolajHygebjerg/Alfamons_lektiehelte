import 'dart:developer' as developer;

/// Resolver for lokale kort-SVG'er i assets. Format: {Navn}kort{1-4}.svg
/// Eksempel: Ifflekort1, Ifflekort2, Atiachkort1, osv.
/// Bruger både avatar-navn og bogstav (a-å) til lookup.
class CardAssets {
  /// Bogstav (a-å) -> asset base. Matcher eksakte filnavne (case-sensitive på web/Android).
  static const Map<String, String> _letterToAssetBase = {
    'a': 'Atiachkort',
    'b': 'Bezzlekort',
    'c': 'Cekimoskort',
    'd': 'Dedookort',
    'e': 'Ellabookort',
    'f': 'Flizardkort',
    'g': 'Gemibullkort',
    'h': 'Haaghaikort',
    'i': 'Ifflekort',
    'j': 'Jaadrikkort',
    'k': 'Kåvaxkort',
    'l': 'Lmikort',
    'm': 'Maxtorkort',
    'n': 'Nimbrookort',
    'o': 'Oodlobkort',
    'p': 'Peppapopkort',
    'q': 'Quibblykort',
    'r': 'Rminaxkort',
    's': 'Snakekort',
    't': 'Tegormkort',
    'u': 'Ummirookort',
    'v': 'Vindlookort',
    'w': 'Wiglookort',
    'x': 'X-bugkort',
    'y': 'Yglifaxkort',
    'z': 'Zetbrakort',
    'æ': 'Aelgorkort',
    'ø': 'Oegleonkort',
    'å': 'Aarmokkort',
  };

  /// Avatar-navn (lowercase) -> asset base (uden stage). Stage 1-4 tilføjes.
  static const Map<String, String> _nameToAssetBase = {
    'iffle': 'Ifflekort',
    'atiach': 'Atiachkort',
    'aelgor': 'Aelgorkort',
    'bezzle': 'Bezzlekort',
    'cekimon': 'Cekimoskort',
    'cekimos': 'Cekimoskort',
    'deedoo': 'Dedookort',
    'dedoo': 'Dedookort',
    'elisboo': 'Ellabookort',
    'ellaboo': 'Ellabookort',
    'flizard': 'Flizardkort',
    'f-lizard': 'Flizardkort',
    'gemitsui': 'Gemibullkort',
    'gemitsull': 'Gemibullkort',
    'hakkul': 'Haaghaikort',
    'haaghai': 'Haaghaikort',
    'irile': 'Ifflekort',
    'jadrik': 'Jaadrikkort',
    'jaadrik': 'Jaadrikkort',
    'kåvax': 'Kåvaxkort',
    'kavax': 'Kåvaxkort',
    'l-mii': 'Lmikort',
    'lmi': 'Lmikort',
    'l-titi': 'Lmikort',
    'master': 'Maxtorkort',
    'm-astar': 'Maxtorkort',
    'maxtor': 'Maxtorkort',
    'nimbroo': 'Nimbrookort',
    'oglah': 'Oodlobkort',
    'oqlen': 'Oodlobkort',
    'oodlob': 'Oodlobkort',
    'odiab': 'Oodlobkort',
    'peppapop': 'Peppapopkort',
    'quibbly': 'Quibblykort',
    'quibbty': 'Quibblykort',
    'r-minax': 'Rminaxkort',
    'rminax': 'Rminaxkort',
    's-nake': 'Snakekort',
    's-nalo': 'Snakekort',
    's-males': 'Snakekort',
    'snake': 'Snakekort',
    'tegorm': 'Tegormkort',
    'tagorm': 'Tegormkort',
    'ummiroo': 'Ummirookort',
    'vindleak': 'Vindlookort',
    'windioo': 'Vindlookort',
    'vindloo': 'Vindlookort',
    'wigloo': 'Wiglookort',
    'wiglook': 'Wiglookort',
    'x-bug': 'X-bugkort',
    'yalfax': 'Yglifaxkort',
    'yglifax': 'Yglifaxkort',
    'zebra': 'Zetbrakort',
    'zetbra': 'Zetbrakort',
    'armok': 'Aarmokkort',
    'aarmok': 'Aarmokkort',
    'oegleon': 'Oegleonkort',
    'bazzle': 'Bezzlekort',
    'bazzie': 'Bezzlekort',
    'apego': 'Bezzlekort',
    'adonis': 'Bezzlekort',
    'aerios': 'Dedookort',
    'abbas': 'Atiachkort',
    // Variant-stavninger fra database
    'x-rub': 'X-bugkort',
    'vindleek': 'Vindlookort',
    'ummiboo': 'Ummirookort',
    'teoborn': 'Tegormkort',
    'boleon': 'Oegleonkort',
    'm-axtor': 'Maxtorkort',
    'ældor': 'Aelgorkort',
  };

  /// Overrides for filer med afvigende navne (case, typo)
  static const Map<String, String> _pathOverrides = {
    'assets/Aelgorkort3.svg': 'assets/aelgorkort3.svg',
    'assets/Aelgorkort4.svg': 'assets/aelgorkort4.svg',
  };

  /// Returnerer asset-path for kort (f.eks. 'assets/Ifflekort1.svg') eller null.
  /// Navne har stort startbogstav, stage 1-4. Understøtter både 0- og 1-baseret stageIndex.
  /// letter: bruges først (pålidelig 1:1 mapping A→Atiach, B→Bezzle).
  /// Æg bruger ikke *kort0* i assets — kun kort1–4 findes lokalt; trin 0 (æg) kommer fra
  /// [avatar_stages.image_url] i Supabase (samme som Bezzle), typisk Storage-public URL.
  static String? getCardAssetPath(String avatarName, int stageIndex, {String? letter}) {
    // Database kan bruge 0-3 (baby→stærkeste) eller 1-4
    final stage = (stageIndex >= 1 && stageIndex <= 4)
        ? stageIndex
        : (stageIndex + 1).clamp(1, 4);

    String? base;

    // 1) Bogstav først – mest pålidelig (A→Atiachkort, B→Bezzlekort)
    if (letter != null && letter.isNotEmpty) {
      base = _letterToAssetBase[letter.toLowerCase().trim()];
    }
    // 2) Navn (lowercase) – Atiach→atiach→Atiachkort
    if (base == null) {
      final nameKey = avatarName.toLowerCase().trim();
      base = _nameToAssetBase[nameKey];
    }
    // 3) Første bogstav i navn – Bezzle→b→Bezzlekort
    if (base == null && avatarName.isNotEmpty) {
      final first = avatarName.toLowerCase().trim()[0];
      base = _letterToAssetBase[first];
    }

    final rawPath = base == null ? null : 'assets/${base}$stage.svg';
    final path = rawPath == null ? null : (_pathOverrides[rawPath] ?? rawPath);
    developer.log(
      'name=$avatarName letter=$letter stageIndex=$stageIndex -> base=$base path=$path',
      name: 'CardAssets',
    );
    return path;
  }

  /// Returnerer liste af asset-paths at prøve (WebP, PNG, JPG, SVG). Brug Image.asset for
  /// raster (WebP/PNG/JPG); SvgPicture for SVG (flutter_svg har problemer med
  /// indlejrede base64-billeder i SVG).
  static List<String> getCardImagePathsToTry(String avatarName, int stageIndex, {String? letter}) {
    final svgPath = getCardAssetPath(avatarName, stageIndex, letter: letter);
    if (svgPath == null) return [];
    final basePath = svgPath.replaceAll('.svg', '');
    return ['$basePath.webp', '$basePath.png', '$basePath.jpg', svgPath];
  }
}
