import 'package:shared_preferences/shared_preferences.dart';

/// Дневной лимит «Моей волны» для бесплатной версии.
/// Premium — без ограничений. Счётчик сам сбрасывается при смене даты.
class WaveQuota {
  WaveQuota(this._prefs);

  /// Сколько треков волны в день доступно без Premium.
  static const int freeDailyLimit = 50;

  static const String _countKey = 'wave_quota_count';
  static const String _dateKey = 'wave_quota_date';

  final SharedPreferences _prefs;

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  int get usedToday =>
      _prefs.getString(_dateKey) == _today ? (_prefs.getInt(_countKey) ?? 0) : 0;

  int get remaining {
    final left = freeDailyLimit - usedToday;
    return left < 0 ? 0 : left;
  }

  /// Остался ли у бесплатного пользователя лимит на сегодня.
  bool get freeHasQuota => usedToday < freeDailyLimit;

  /// Отметить прослушанный в волне трек (вызывать при завершении трека волны).
  Future<void> noteWavePlay() async {
    final today = _today;
    if (_prefs.getString(_dateKey) != today) {
      await _prefs.setString(_dateKey, today);
      await _prefs.setInt(_countKey, 0);
    }
    await _prefs.setInt(_countKey, (_prefs.getInt(_countKey) ?? 0) + 1);
  }
}
