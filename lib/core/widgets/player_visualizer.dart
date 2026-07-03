import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../../data/visualizer_channel.dart';

/// Спектр-визуализатор под обложкой. При включённом «реальном» режиме берёт FFT
/// из нативного Android Visualizer (реагирует на звук/бит); иначе — декоративная
/// анимация.
class PlayerVisualizer extends ConsumerStatefulWidget {
  const PlayerVisualizer({
    super.key,
    required this.playing,
    required this.color,
    this.bars = 32,
    this.height = 30,
  });

  final bool playing;
  final Color color;
  final int bars;
  final double height;

  @override
  ConsumerState<PlayerVisualizer> createState() => _PlayerVisualizerState();
}

class _PlayerVisualizerState extends ConsumerState<PlayerVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  StreamSubscription<List<double>>? _sub;
  bool _started = false;
  bool _enabled = false;
  List<double> _smooth = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.repeat(); // анимируем всегда — и при игре, и на паузе
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // В фоне/при выключенном экране останавливаем нативный захват спектра.
    if (state == AppLifecycleState.resumed) {
      _apply();
    } else {
      _stopReal();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerVisualizer old) {
    super.didUpdateWidget(old);
    _apply();
  }

  void _apply() {
    if (_enabled && widget.playing) {
      _ensureStarted();
    } else {
      _stopReal();
    }
  }

  Future<void> _ensureStarted() async {
    if (_started) return;
    _started = true;
    final ok = await Permission.microphone.request();
    if (!ok.isGranted) {
      _started = false;
      return;
    }
    final sid = ref.read(audioHandlerProvider).androidAudioSessionId ?? 0;
    final started = await VisualizerChannel.instance.start(sid);
    if (!started) {
      _started = false;
      return;
    }
    _sub = VisualizerChannel.instance.bands.listen((b) {
      if (!mounted) return;
      // Сглаживание: быстрый рост, плавный спад (эффект «отпускания» полос).
      if (_smooth.length != b.length) _smooth = List<double>.filled(b.length, 0);
      for (var i = 0; i < b.length; i++) {
        _smooth[i] = max(b[i], _smooth[i] * 0.80);
      }
      // Реальные данные сами двигают полосы через setState — декоративный
      // контроллер тут не нужен, глушим его, чтобы не гонять двойные ребилды.
      if (_c.isAnimating) _c.stop();
      setState(() {});
    });
  }

  void _stopReal({bool resumeDecor = true}) {
    if (!_started && _sub == null) return;
    _sub?.cancel();
    _sub = null;
    _started = false;
    _smooth = [];
    VisualizerChannel.instance.stop();
    // Реальный захват выключен — возвращаем декоративную волну.
    if (resumeDecor && mounted && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopReal(resumeDecor: false);
    _c.dispose();
    super.dispose();
  }

  double _valueAt(int i) {
    // Реальные данные, если есть; иначе — декоративная волна.
    if (_enabled && _smooth.isNotEmpty && widget.playing) {
      final idx = (i * _smooth.length / widget.bars).floor().clamp(0, _smooth.length - 1);
      return _smooth[idx];
    }
    final t = _c.value * 2 * pi;
    if (!widget.playing) {
      // На паузе — спокойная «дышащая» волна низкой амплитуды.
      return (0.16 + 0.11 * sin(t * 0.8 + i * 0.45)).clamp(0.05, 0.34);
    }
    return (0.5 + 0.5 * sin(t + i * 0.5) * sin(t * 0.7 + i * 0.28).abs())
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Реактивно на настройку: включили/выключили — стартуем/останавливаем.
    final enabled = ref.watch(realVisualizerProvider);
    if (enabled != _enabled) {
      _enabled = enabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _apply();
      });
    }
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _BarsPainter(
              values: List<double>.generate(widget.bars, _valueAt),
              color: widget.color
                  .withValues(alpha: widget.playing ? 0.85 : 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

/// Рисует спектр одним слоем (вместо десятков виджетов-полос на кадр).
/// Полосы шириной 3px с равными промежутками, вертикально по центру.
class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  static const _barW = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final gap = n > 1 ? (size.width - _barW * n) / (n - 1) : 0.0;
    final paint = Paint()..color = color;
    const radius = Radius.circular(3);
    for (var i = 0; i < n; i++) {
      final h = (size.height * (0.12 + 0.88 * values[i]))
          .clamp(3.0, size.height);
      final x = i * (_barW + gap);
      final top = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, top, _barW, h), radius),
        paint,
      );
    }
  }

  // Painter создаётся заново только при ребилде (тик анимации или FFT-колбэк),
  // и каждый такой ребилд обязан перерисоваться — поэтому всегда true.
  @override
  bool shouldRepaint(_BarsPainter old) => true;
}
