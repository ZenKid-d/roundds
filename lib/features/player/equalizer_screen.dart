import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

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
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
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
