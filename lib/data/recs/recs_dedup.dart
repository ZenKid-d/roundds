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

  /// Верен ли резолв: найденный [gotArtist]/[gotTitle] — действительно тот трек,
  /// что искали ([candArtist]/[candTitle]). Название строго (fuzzy ≥ 0.8),
  /// артист мягко (вхождение с учётом feat./перестановок или заметное
  /// пересечение токенов). Отсекает каверы/караоке/ускоренные/чужие треки при
  /// резолве кандидатов поиском.
  static bool resolvesTo(
    String candArtist,
    String candTitle,
    String gotArtist,
    String gotTitle,
  ) {
    return matchScore(
          wantArtist: candArtist,
          wantTitle: candTitle,
          gotArtist: gotArtist,
          gotTitle: gotTitle,
        ) !=
        null;
  }

  /// Порог принятия [matchScore]: ниже — считаем чужим треком (кавер/караоке).
  static const double matchThreshold = 0.62;

  /// Скоринг совпадения кандидата с искомым треком для ранжирования фолбэка.
  /// Возвращает 0..1, либо null — если кандидат точно не тот трек (кавер, чужая
  /// песня под тем же названием, сниппет вместо полного трека).
  ///
  /// Взвешивает три сигнала: название (0.55), артист (0.25), длительность (0.20).
  /// Жёсткие гейты как в [resolvesTo]: title fuzzy ≥ 0.8, артист проходит мягкую
  /// проверку (вхождение или пересечение токенов ≥ 0.34) — иначе кавер проскочил
  /// бы за счёт названия. Длительность штрафует «другую версию»: радио-эдит,
  /// ускоренный/замедленный вариант, 30-сек сниппет против полного трека.
  ///
  /// [wantDuration]/[gotDuration] опциональны: если хотя бы одного нет, сигнал
  /// нейтрален (0.6), чтобы не дисквалифицировать трек без данных о длине.
  static double? matchScore({
    required String wantArtist,
    required String wantTitle,
    required String gotArtist,
    required String gotTitle,
    Duration? wantDuration,
    Duration? gotDuration,
  }) {
    if (normKey(wantArtist, wantTitle) == normKey(gotArtist, gotTitle)) {
      // Точное совпадение ключа — максимальный счёт с поправкой на длительность,
      // чтобы из дублей предпочесть версию той же длины.
      return 0.8 + 0.2 * _durationScore(wantDuration, gotDuration);
    }
    final titleSim = math.max(
      tokenSimilarity(wantTitle, gotTitle),
      levenshteinRatio(wantTitle, gotTitle),
    );
    if (titleSim < 0.8) return null;

    // Гейт по артисту — отсекает каверы (Birdy vs Bon Iver при том же «Skinny
    // Love»). Без него название даёт слишком много очков и кавер проходит.
    final a1 = normalize(wantArtist);
    final a2 = normalize(gotArtist);
    if (a1.isEmpty || a2.isEmpty) return null;
    final double artistSim;
    if (a2.contains(a1) || a1.contains(a2)) {
      artistSim = 1.0; // feat./перестановка/«Drake, Rick Ross» против «Drake»
    } else {
      final t = tokenSimilarity(wantArtist, gotArtist);
      if (t < 0.34) return null;
      artistSim = t;
    }

    final durScore = _durationScore(wantDuration, gotDuration);
    final total = 0.55 * titleSim + 0.25 * artistSim + 0.20 * durScore;
    return total >= matchThreshold ? total : null;
  }

  /// Оценка совпадения длительности, 0.2..1.0 (0.6 — нейтрально при отсутствии
  /// данных). Полное совпадение и расхождение ≤3с — 1.0; до 10с — плавный спад к
  /// 0.8; до 30с — к 0.5; свыше — 0.2 (явно другая версия/сниппет). Ratio длин
  /// < 0.5 тоже даёт 0.2 — на случай wildly разных треков.
  static double _durationScore(Duration? want, Duration? got) {
    if (want == null || got == null) return 0.6;
    final ws = want.inSeconds;
    final gs = got.inSeconds;
    if (ws == 0 && gs == 0) return 0.6;
    final maxLen = math.max(ws, gs);
    if (maxLen == 0) return 0.6;
    final ratio = math.min(ws, gs) / maxLen;
    if (ratio < 0.5) return 0.2;
    final delta = (ws - gs).abs();
    if (delta <= 3) return 1.0;
    if (delta > 30) return 0.2;
    if (delta <= 10) {
      // 3..10с → 1.0..0.8
      return 1.0 - 0.2 * (delta - 3) / 7;
    }
    // 10..30с → 0.8..0.5
    return 0.8 - 0.3 * (delta - 10) / 20;
  }
}
