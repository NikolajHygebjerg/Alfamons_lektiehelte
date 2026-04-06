/// Dans alfabetisk ordning til Alfamon-navne: a–z, derefter æ, ø, å.
int compareDanishAlfamonName(String a, String b) {
  final ar = a.trim().toLowerCase().runes.toList();
  final br = b.trim().toLowerCase().runes.toList();
  final n = ar.length < br.length ? ar.length : br.length;
  for (var i = 0; i < n; i++) {
    final c = _danishRuneOrder(ar[i]).compareTo(_danishRuneOrder(br[i]));
    if (c != 0) return c;
  }
  return ar.length.compareTo(br.length);
}

int _danishRuneOrder(int r) {
  if (r >= 0x61 && r <= 0x7a) return r - 0x61;
  switch (r) {
    case 0xe6:
      return 26;
    case 0xf8:
      return 27;
    case 0xe5:
      return 28;
    default:
      if (r < 0x80) return 200 + r;
      return 1000 + r;
  }
}

const _kExcludedAdminAvatarPickerNames = {'ok', 'atiachtest', 'kla'};

/// Skjules i admin-vælgeren (og slettes via migration); ikke Alfamon-produktdata.
bool isExcludedFromAdminAvatarPicker(String? name) {
  final k = name?.trim().toLowerCase() ?? '';
  return _kExcludedAdminAvatarPickerNames.contains(k);
}
