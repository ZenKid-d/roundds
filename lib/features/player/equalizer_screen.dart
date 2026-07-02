import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

/// Встроенные пресеты как 5-точечные профили (дБ), интерполируются под число
/// полос устройства.
const _builtinPresets = <String, List<double>>{
  'Плоский': [0, 0, 0, 0, 0],
  'Бас-буст': [7, 4, 0, 1, 2],
  'Вокал': [-2, 0, 3, 3, 1],
  'Рок': [5, 2, -1, 2, 4],
  'Поп': [2, 3, 1, 0, 1],
  'Джаз': [3, 1, 0, 1, 3],
  'Классика': [4, 2, 0, 2, 3],
  'Высокие': [0, 0, 0, 3, 6],
};

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  late final AndroidEqualizer _eq = ref.read(audioHandlerProvider).equalizer;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = _eq.enabled;
  }

  List<MapEntry<String, List<double>>> get _customPresets {
    final raw = ref.read(prefsProvider).getStringList('eq_presets') ?? const [];
    return raw.map((e) {
      final m = jsonDecode(e) as Map<String, dynamic>;
      return MapEntry(
          m['name'] as String,
          (m['gains'] as List).map((x) => (x as num).toDouble()).toList());
    }).toList();
  }

  void _applyProfile(AndroidEqualizerParameters params, List<double> p) {
    final bands = params.bands;
    final n = bands.length;
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? 0.0 : i * (p.length - 1) / (n - 1);
      final lo = x.floor().clamp(0, p.length - 1);
      final hi = x.ceil().clamp(0, p.length - 1);
      final frac = x - lo;
      final g = (p[lo] * (1 - frac) + p[hi] * frac)
          .clamp(params.minDecibels, params.maxDecibels);
      bands[i].setGain(g);
    }
    _eq.setEnabled(true);
    setState(() => _enabled = true);
  }

  Future<void> _saveCurrent(AndroidEqualizerParameters params) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface2,
          title: const Text('Сохранить пресет'),
          content: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Название')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(context, c.text.trim()),
                child: const Text('Сохранить')),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final gains = params.bands.map((b) => b.gain).toList();
    final list = ref.read(prefsProvider).getStringList('eq_presets') ?? [];
    list.add(jsonEncode({'name': name, 'gains': gains}));
    await ref.read(prefsProvider).setStringList('eq_presets', list);
    setState(() {});
  }

  Future<void> _deleteCustom(String name) async {
    final list = (ref.read(prefsProvider).getStringList('eq_presets') ?? [])
        .where((e) => (jsonDecode(e) as Map)['name'] != name)
        .toList();
    await ref.read(prefsProvider).setStringList('eq_presets', list);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Эквалайзер')),
      body: Column(
        children: [
          SwitchListTile(
            value: _enabled,
            activeColor: accent,
            title: const Text('Включить эквалайзер'),
            onChanged: (v) {
              _eq.setEnabled(v);
              setState(() => _enabled = v);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<AndroidEqualizerParameters>(
              future: _eq.parameters,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Эквалайзер недоступен (запустите трек и откройте снова).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.white45),
                      ),
                    ),
                  );
                }
                final params = snap.data!;
                final custom = _customPresets;
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text('Пресеты',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.white60)),
                    ),
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final e in _builtinPresets.entries)
                            _PresetChip(
                              label: e.key,
                              onTap: () => _applyProfile(params, e.value),
                            ),
                          for (final e in custom)
                            _PresetChip(
                              label: e.key,
                              custom: true,
                              onTap: () => _applyProfile(params, e.value),
                              onLong: () => _deleteCustom(e.key),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: const Text('Сохранить'),
                              onPressed: () => _saveCurrent(params),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 18),
                    for (final band in params.bands)
                      _BandRow(
                        band: band,
                        min: params.minDecibels,
                        max: params.maxDecibels,
                        accent: accent,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
    this.onLong,
    this.custom = false,
  });
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  final bool custom;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLong,
        child: ActionChip(
          avatar: custom
              ? Icon(Icons.person, size: 15, color: accent)
              : null,
          label: Text(label),
          onPressed: onTap,
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.band,
    required this.min,
    required this.max,
    required this.accent,
  });

  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final Color accent;

  String _freq(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}кГц'
                 : '${hz.round()}Гц';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: band.gainStream,
      initialData: band.gain,
      builder: (context, snap) {
        final gain = (snap.data ?? band.gain).clamp(min, max);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(_freq(band.centerFrequency),
                    style: TextStyle(fontSize: 12, color: AppColors.white60)),
              ),
              Expanded(
                child: Slider(
                  min: min,
                  max: max,
                  value: gain,
                  onChanged: (v) => band.setGain(v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${gain.toStringAsFixed(1)} дБ',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: AppColors.white45)),
              ),
            ],
          ),
        );
      },
    );
  }
}
