/// Recs v2 — характер «Моей волны». Меняет баланс exploitation/exploration и
/// жёсткость cooldown, отображая на пресеты весов скоринга и anti-repetition.
library;

import 'scorer.dart';
import 'wave_constraints.dart';

enum WaveMode { balanced, favorite, unfamiliar, popular }

extension WaveModeX on WaveMode {
  String get id => name;

  String get label => switch (this) {
        WaveMode.balanced => 'Баланс',
        WaveMode.favorite => 'Любимое',
        WaveMode.unfamiliar => 'Незнакомое',
        WaveMode.popular => 'Популярное',
      };

  String get hint => switch (this) {
        WaveMode.balanced => 'Знакомое и открытия поровну',
        WaveMode.favorite => 'Больше любимого, меньше нового',
        WaveMode.unfamiliar => 'Преимущественно новые артисты',
        WaveMode.popular => 'Упор на популярное',
      };

  ScoreWeights get weights => switch (this) {
        WaveMode.balanced => ScoreWeights.balanced,
        WaveMode.favorite => ScoreWeights.favorite,
        WaveMode.unfamiliar => ScoreWeights.unfamiliar,
        WaveMode.popular => ScoreWeights.popular,
      };

  WaveConstraints get constraints => switch (this) {
        WaveMode.favorite => WaveConstraints.favorite,
        _ => WaveConstraints.balanced,
      };

  static WaveMode fromId(String? s) => WaveMode.values
      .firstWhere((e) => e.name == s, orElse: () => WaveMode.balanced);
}
