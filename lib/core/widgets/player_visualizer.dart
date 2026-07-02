import 'dart:math';

import 'package:flutter/material.dart';

/// Декоративный спектр-визуализатор под обложкой. Анимируется во время
/// воспроизведения (не настоящий FFT — just_audio не отдаёт спектр).
class PlayerVisualizer extends StatefulWidget {
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
  State<PlayerVisualizer> createState() => _PlayerVisualizerState();
}

class _PlayerVisualizerState extends State<PlayerVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant PlayerVisualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(widget.bars, (i) {
                final t = _c.value * 2 * pi;
                // Разные фазы/частоты — «живой» спектр; на паузе — низкие.
                final wave = widget.playing
                    ? (0.5 +
                        0.5 *
                            sin(t + i * 0.5) *
                            sin(t * 0.7 + i * 0.28).abs())
                    : 0.14;
                final h = (widget.height * (0.12 + 0.88 * wave))
                    .clamp(3.0, widget.height);
                return Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                        alpha: widget.playing ? 0.85 : 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
