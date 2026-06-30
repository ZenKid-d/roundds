import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_settings.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  double _hue = 260;
  double _sat = 0.6;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(Color(ref.read(themeSettingsProvider).customColor));
    _hue = hsv.hue;
    _sat = hsv.saturation.clamp(0.2, 1.0);
  }

  void _applyCustom() {
    final c = HSVColor.fromAHSV(1, _hue, _sat, 0.9).toColor();
    ref.read(themeSettingsProvider).setCustomColor(c.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(themeSettingsProvider);
    final ctl = ref.read(themeSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Внешний вид')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section('Фон'),
          Row(
            children: [
              for (var i = 0; i < kBgPresets.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? 10 : 0),
                    child: _BgCard(
                      preset: kBgPresets[i],
                      selected: ts.bgIndex == i,
                      onTap: () => ctl.setBackground(i),
                    ),
                  ),
                ),
            ],
          ),
          _section('Акцентный цвет'),
          _Seg(
            labels: const ['Динамический', 'Пресеты', 'Свой'],
            index: ts.accentMode.index,
            onTap: (i) => ctl.setAccentMode(AccentMode.values[i]),
          ),
          if (ts.accentMode == AccentMode.preset) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < kAccentPresets.length; i++)
                  _Swatch(
                    color: kAccentPresets[i],
                    selected: ts.presetIndex == i,
                    onTap: () => ctl.setPreset(i),
                  ),
              ],
            ),
          ],
          if (ts.accentMode == AccentMode.custom) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(ts.customColor),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Свой цвет',
                    style: TextStyle(color: AppColors.white60, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            _label('Оттенок'),
            Slider(
              min: 0,
              max: 360,
              value: _hue,
              onChanged: (v) {
                setState(() => _hue = v);
                _applyCustom();
              },
            ),
            _label('Насыщенность'),
            Slider(
              min: 0.2,
              max: 1,
              value: _sat,
              onChanged: (v) {
                setState(() => _sat = v);
                _applyCustom();
              },
            ),
          ],
          _section('Вид плеера'),
          _Seg(
            labels: const ['Винил', 'Обложка'],
            index: ts.playerView.index,
            onTap: (i) => ctl.setPlayerView(PlayerView.values[i]),
          ),
          _section('Анимации'),
          _Seg(
            labels: const ['Максимум', 'Сдержанные', 'Минимум'],
            index: ts.animLevel.index,
            onTap: (i) => ctl.setAnimLevel(AnimLevel.values[i]),
          ),
          _section('Скругления углов'),
          _Seg(
            labels: const ['Острые', 'Средние', 'Круглые'],
            index: ts.corners.index,
            onTap: (i) => ctl.setCorners(CornerStyle.values[i]),
          ),
          _section('Шрифт'),
          _Seg(
            labels: const ['Poppins', 'Системный'],
            index: ts.systemFont ? 1 : 0,
            onTap: (i) => ctl.setSystemFont(i == 1),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 4),
        child: Text(t,
            style: TextStyle(fontSize: 12, color: AppColors.white45)),
      );
}

class _BgCard extends StatelessWidget {
  const _BgCard(
      {required this.preset, required this.selected, required this.onTap});
  final BgPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: preset.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? accent : Colors.white12,
              width: selected ? 2 : 1),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: preset.surface2,
                  borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(width: 8),
            Text(preset.name,
                style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? Colors.white : Colors.transparent, width: 3),
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: Colors.black)
            : null,
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(
      {required this.labels, required this.index, required this.onTap});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index
                        ? accent.withValues(alpha: 0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: i == index ? accent : Colors.transparent),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        color: i == index ? Colors.white : AppColors.white60,
                        fontWeight:
                            i == index ? FontWeight.w500 : FontWeight.w400,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
