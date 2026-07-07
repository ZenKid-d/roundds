/// Recs v2 — нормализация ключа трека для дедупа кросс-источников и дизлайк-
/// фильтра. Один и тот же трек с YTM и SC должен давать одинаковый ключ.
/// Базовая нормализация + fuzzy-сравнение (Jaccard/Levenshtein) для граничных
/// случаев, когда точные ключи расходятся (лишнее слово, опечатка, транслит).
library;

import 'dart:math' as math;

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

  // --- fuzzy-сравнение (граничные случаи дедупа) ---

  /// Токенное сходство Жаккара нормализованных строк, 0..1.
  static double tokenSimilarity(String a, String b) {
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty && tb.isEmpty) return 1;
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return inter / union;
  }

  static Set<String> _tokens(String s) =>
      normalize(s).split(' ').where((t) => t.isNotEmpty).toSet();

  /// Расстояние Левенштейна между нормализованными строками.
  static int levenshtein(String a, String b) {
    final s = normalize(a);
    final t = normalize(b);
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    var prev = List<int>.generate(t.length + 1, (i) => i);
    var cur = List<int>.filled(t.length + 1, 0);
    for (var i = 0; i < s.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
        cur[j + 1] = math.min(
          math.min(cur[j] + 1, prev[j + 1] + 1),
          prev[j] + cost,
        );
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[t.length];
  }

  /// Нормированное сходство по Левенштейну, 0..1.
  static double levenshteinRatio(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    final maxLen = math.max(na.length, nb.length);
    if (maxLen == 0) return 1;
    return 1 - levenshtein(a, b) / maxLen;
  }

  /// Один ли это трек, несмотря на расхождение точных ключей. Сначала точный
  /// ключ; иначе — близость артиста И близость названия по порогу.
  static bool isFuzzyDuplicate(
    String artistA,
    String titleA,
    String artistB,
    String titleB, {
    double threshold = 0.82,
  }) {
    if (normKey(artistA, titleA) == normKey(artistB, titleB)) return true;
    if (tokenSimilarity(artistA, artistB) < 0.5) return false;
    final titleSim = math.max(
      tokenSimilarity(titleA, titleB),
      levenshteinRatio(titleA, titleB),
    );
    return titleSim >= threshold;
  }
}
