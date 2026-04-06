/// Resolver for angreb-billeder (transparent raster; typisk WebP efter konvertering).
/// Format: {Navn}angreb{1-4}.png eller .webp afhængigt af assets (kør tool/convert_png_to_webp.py).
/// Eksempel: Oodlobangreb1, Atiachangreb2, osv.
class AngrebAssets {
  /// Bogstav (a-å) -> asset base for angreb
  static const Map<String, String> _letterToAssetBase = {
    'a': 'Atiachangreb',
    'b': 'Bezzleangreb',
    'c': 'Cekimosangreb',
    'd': 'Dedooangreb',
    'e': 'Ellabooangreb',
    'f': 'Flizardangreb',
    'g': 'Gemibullangreb',
    'h': 'Haaghaiangreb',
    'i': 'Iffleangreb',
    'j': 'Jaadrikangreb',
    'k': 'Kaavaxangreb',
    'l': 'Lmiangreb',
    'm': 'Maxtorangreb',
    'n': 'Nimbrooangreb',
    'o': 'Oodlobangreb',
    'p': 'Peppapopangreb',
    'q': 'Quibblyangreb',
    'r': 'Rminaxangreb',
    's': 'Snakeangreb',
    't': 'Tegormangreb',
    'u': 'Ummirooangreb',
    'v': 'Vindleekangreb',
    'w': 'Wiglooangreb',
    'x': 'Xbugangreb',
    'y': 'Yglifaxangreb',
    'z': 'Zetbraangreb',
    'æ': 'Aelgorangreb',
    'ø': 'Oegleonangreb',
    'å': 'Aarmokangreb',
  };

  /// Avatar-navn (lowercase) -> asset base
  static const Map<String, String> _nameToAssetBase = {
    'atiach': 'Atiachangreb',
    'abbas': 'Atiachangreb',
    'aelgor': 'Aelgorangreb',
    'aarmok': 'Aarmokangreb',
    'armok': 'Aarmokangreb',
    'bezzle': 'Bezzleangreb',
    'cekimon': 'Cekimosangreb',
    'cekimos': 'Cekimosangreb',
    'dedoo': 'Dedooangreb',
    'deedoo': 'Deedooangreb',
    'ellaboo': 'Ellabooangreb',
    'elisboo': 'Ellabooangreb',
    'flizard': 'Flizardangreb',
    'gemibull': 'Gemibullangreb',
    'gemitsui': 'Gemibullangreb',
    'haaghai': 'Haaghaiangreb',
    'hakkul': 'Haaghaiangreb',
    'iffle': 'Iffleangreb',
    'jaadrik': 'Jaadrikangreb',
    'jadrik': 'Jaadrikangreb',
    'kavax': 'Kaavaxangreb',
    'kåvax': 'Kaavaxangreb',
    'lmi': 'Lmiangreb',
    'l-mii': 'Lmiangreb',
    'maxtor': 'Maxtorangreb',
    'nimbroo': 'Nimbrooangreb',
    'oodlob': 'Oodlobangreb',
    'oglah': 'Oodlobangreb',
    'oegleon': 'Oegleonangreb',
    'peppapop': 'Peppapopangreb',
    'quibbly': 'Quibblyangreb',
    'rminax': 'Rminaxangreb',
    'snake': 'Snakeangreb',
    's-nake': 'Snakeangreb',
    'tegorm': 'Tegormangreb',
    'ummiroo': 'Ummirooangreb',
    'vindloo': 'Vindleekangreb',
    'vindleek': 'Vindleekangreb',
    'wigloo': 'Wiglooangreb',
    'wiglook': 'Wiglooangreb',
    'x-bug': 'Xbugangreb',
    'xbug': 'Xbugangreb',
    'yglifax': 'Yglifaxangreb',
    'zetbra': 'Zetbraangreb',
    'zebra': 'Zetbraangreb',
  };

  /// Returnerer asset-path for angreb-billede (f.eks. 'assets/Oodlobangreb1.webp').
  /// stageIndex: 1-4 (eller 0-3, konverteres til 1-4).
  static String? getAngrebAssetPath(String avatarName, int stageIndex, {String? letter}) {
    final stage = (stageIndex >= 1 && stageIndex <= 4)
        ? stageIndex
        : (stageIndex + 1).clamp(1, 4);

    String? base;

    if (letter != null && letter.isNotEmpty) {
      base = _letterToAssetBase[letter.toLowerCase().trim()];
    }
    if (base == null) {
      final nameKey = avatarName.toLowerCase().trim();
      base = _nameToAssetBase[nameKey];
    }
    if (base == null && avatarName.isNotEmpty) {
      final first = avatarName.toLowerCase().trim()[0];
      base = _letterToAssetBase[first];
    }

    if (base == null) return null;

    // Dedoo 1-3 vs Deedoo 4 (filnavne i assets)
    if (base == 'Dedooangreb' && stage == 4) {
      return 'assets/Deedooangreb4.webp';
    }
    return 'assets/$base$stage.webp';
  }
}
