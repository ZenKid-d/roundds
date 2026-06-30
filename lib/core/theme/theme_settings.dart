import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

enum AccentMode { dynamic, preset, custom }

enum PlayerView { vinyl, cover }

enum AnimLevel { max, moderate, min }

enum CornerStyle { sharp, medium, round }

/// Тёмные фоны-пресеты.
class BgPreset {
  final String name;
  final Color background;
  final Color surface1;
  final Color surface2;
  const BgPreset(this.name, this.background, this.surface1, this.surface2);
}

const kBgPresets = <BgPreset>[
  BgPreset('AMOLED', Color(0xFF000000), Color(0xFF0C0C0C), Color(0xFF141414)),
  BgPreset('Тёмно-серый', Color(0xFF121212), Color(0xFF1C1C1C),
      Color(0xFF262626)),
];

/// Готовые акцентные палитры.
const kAccentPresets = <Color>[
  Color(0xFF1DB954), // зелёный
  Color(0xFF4FC3F7), // циан
  Color(0xFFE040FB), // маджента
  Color(0xFFFFC107), // золото
  Color(0xFFB388FF), // фиолетовый
  Color(0xFFFF6E6E), // коралл
];

/// Расширение темы — несёт текущий радиус скруглений в любой виджет.
class AppShapes extends ThemeExtension<AppShapes> {
  final double radius;
  const AppShapes(this.radius);

  @override
  AppShapes copyWith({double? radius}) => AppShapes(radius ?? this.radius);

  @override
  AppShapes lerp(ThemeExtension<AppShapes>? other, double t) {
    if (other is! AppShapes) return this;
    return AppShapes(radius * (1 - t) + other.radius * t);
  }
}

/// Настройки внешнего вида, хранятся в SharedPreferences.
class ThemeSettingsController extends ChangeNotifier {
  ThemeSettingsController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  int bgIndex = 0;
  AccentMode accentMode = AccentMode.dynamic;
  int presetIndex = 4;
  int customColor = 0xFFB388FF;
  PlayerView playerView = PlayerView.vinyl;
  AnimLevel animLevel = AnimLevel.max;
  CornerStyle corners = CornerStyle.round;
  bool systemFont = false;

  BgPreset get bg => kBgPresets[bgIndex.clamp(0, kBgPresets.length - 1)];
  Color get presetColor =>
      kAccentPresets[presetIndex.clamp(0, kAccentPresets.length - 1)];

  double get radius => switch (corners) {
        CornerStyle.sharp => 6,
        CornerStyle.medium => 14,
        CornerStyle.round => 22,
      };

  bool get spin => animLevel != AnimLevel.min;
  bool get richMotion => animLevel == AnimLevel.max;

  void _load() {
    bgIndex = _prefs.getInt('ap_bg') ?? 0;
    accentMode = AccentMode.values[_prefs.getInt('ap_accentMode') ?? 0];
    presetIndex = _prefs.getInt('ap_preset') ?? 4;
    customColor = _prefs.getInt('ap_custom') ?? 0xFFB388FF;
    playerView = PlayerView.values[_prefs.getInt('ap_player') ?? 0];
    animLevel = AnimLevel.values[_prefs.getInt('ap_anim') ?? 0];
    corners = CornerStyle.values[_prefs.getInt('ap_corners') ?? 2];
    systemFont = _prefs.getBool('ap_sysfont') ?? false;
    AppColors.applyBackground(bg.background, bg.surface1, bg.surface2);
    notifyListeners();
  }

  void setBackground(int i) {
    bgIndex = i;
    AppColors.applyBackground(bg.background, bg.surface1, bg.surface2);
    _prefs.setInt('ap_bg', i);
    notifyListeners();
  }

  void setAccentMode(AccentMode m) {
    accentMode = m;
    _prefs.setInt('ap_accentMode', m.index);
    notifyListeners();
  }

  void setPreset(int i) {
    presetIndex = i;
    _prefs.setInt('ap_preset', i);
    notifyListeners();
  }

  void setCustomColor(int argb) {
    customColor = argb;
    _prefs.setInt('ap_custom', argb);
    notifyListeners();
  }

  void setPlayerView(PlayerView v) {
    playerView = v;
    _prefs.setInt('ap_player', v.index);
    notifyListeners();
  }

  void setAnimLevel(AnimLevel l) {
    animLevel = l;
    _prefs.setInt('ap_anim', l.index);
    notifyListeners();
  }

  void setCorners(CornerStyle c) {
    corners = c;
    _prefs.setInt('ap_corners', c.index);
    notifyListeners();
  }

  void setSystemFont(bool v) {
    systemFont = v;
    _prefs.setBool('ap_sysfont', v);
    notifyListeners();
  }
}
