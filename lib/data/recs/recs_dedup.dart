/// Recs v2 — нормализация ключа трека для дедупа кросс-источников и дизлайк-
/// фильтра. Один и тот же трек с YTM и SC должен давать одинаковый ключ.
/// Phase 1 — базовая нормализация; fuzzy-сравнение добавится в Phase 2.
library;

class RecsDedup {
  const RecsDedup._();

  static final RegExp _feat = RegExp(
    r'\s*[\(\[]\s*(feat|ft|featuring|with)\.?\s[^\)\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _tags = RegExp(
    r'\s*[\(\[][^\)\]]*(remaster(ed)?|live|radio edit|mono|stereo|deluxe|'
    r'bonus|explicit|clean|version|remix|\d{4})[^\)\]]*[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _punct = RegExp(r'[^0-9a-zA-Zа-яёА-ЯЁ\s]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Нормализованный ключ `artist|title`.
  static String normKey(String artist, String title) =>
      '${normalize(artist)}|${normalize(title)}';

  /// Нормализует отдельную строку (артист или название).
  static String normalize(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll(_feat, ' ');
    s = s.replaceAll(_tags, ' ');
    s = _stripDiacritics(s);
    s = s.replaceAll(_punct, ' ');
    s = s.replaceAll(_spaces, ' ').trim();
    return s;
  }

  static const Map<String, String> _dia = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c', 'ß': 'ss',
  };

  static String _stripDiacritics(String s) {
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(_dia[ch] ?? ch);
    }
    return b.toString();
  }
}
