import 'dart:math';

import 'package:flutter/material.dart';

/// Живой фон плеера: радиальный градиент из акцентного цвета, центр которого
/// медленно ходит по кругу. Если [animate] выключен — статичный градиент.
class AnimatedPlayerBg extends StatefulWidget {
  const AnimatedPlayerBg({
    super.key,
    required this.accent,
    required this.animate,
  });

  final Color accent;
  final bool animate;

  @override
  State<AnimatedPlayerBg> createState() => _AnimatedPlayerBgState();
}

class _AnimatedPlayerBgState extends State<AnimatedPlayerBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedPlayerBg old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
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
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value * 2 * pi;
          final cx = 0.35 * cos(t);
          final cy = -0.55 + 0.18 * sin(t);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(cx, cy),
                radius: 1.25,
                colors: [
                  widget.accent.withValues(alpha: 0.30),
                  Colors.black,
                ],
                stops: const [0, 0.72],
              ),
            ),
          );
        },
      ),
    );
  }
}
