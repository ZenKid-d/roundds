import 'dart:math';

import 'package:flutter/material.dart';

import 'artwork.dart';

/// Круглая обложка «как пластинка»: квадратные края обрезаны в круг, диск
/// вращается при игре и замирает на паузе. По центру — дырка пластинки,
/// вокруг — свечение акцентного цвета.
class VinylDisc extends StatefulWidget {
  const VinylDisc({
    super.key,
    required this.artworkUrl,
    required this.isPlaying,
    required this.accent,
    this.size = 240,
    this.seed,
  });

  final String? artworkUrl;
  final bool isPlaying;
  final Color accent;
  final double size;
  final String? seed;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant VinylDisc old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.isPlaying && _c.isAnimating) {
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
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent
                          .withValues(alpha: widget.isPlaying ? 0.45 : 0.22),
                      blurRadius: 46,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: RotationTransition(
                  turns: _c,
                  // Диск растеризуется в слой один раз — вращение дешёвое.
                  child: RepaintBoundary(
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Artwork(widget.artworkUrl,
                              size: s, radius: 999, seed: widget.seed),
                          Center(
                            child: Container(
                              width: s * 0.05,
                              height: s * 0.05,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                                border:
                                    Border.all(color: Colors.white38, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Тонарм с иглой: опускается на пластинку при игре, поднят на паузе.
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: widget.isPlaying ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOut,
                  builder: (_, t, __) => CustomPaint(
                    painter: _TonearmPainter(t: t, accent: widget.accent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рисует тонарм проигрывателя: игла опускается на пластинку (t=1) или поднята
/// (t=0). Крепление — в правом верхнем углу диска.
class _TonearmPainter extends CustomPainter {
  _TonearmPainter({required this.t, required this.accent});
  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pivot = Offset(s * 0.9, s * 0.05);
    final tip =
        Offset.lerp(Offset(s * 0.79, s * 0.17), Offset(s * 0.62, s * 0.32), t)!;
    final dir = tip - pivot;
    final u = dir / dir.distance;
    final angle = atan2(u.dy, u.dx);

    // Тень руки.
    canvas.drawLine(
      pivot + Offset(0, s * 0.01),
      tip + Offset(0, s * 0.01),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round,
    );
    // Рука тонарма.
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = const Color(0xFFDADADA)
        ..strokeWidth = s * 0.022
        ..strokeCap = StrokeCap.round,
    );
    // Основание/противовес.
    canvas.drawCircle(pivot, s * 0.06, Paint()..color = const Color(0xFF262626));
    canvas.drawCircle(
        pivot,
        s * 0.06,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white24);
    canvas.drawCircle(pivot, s * 0.022, Paint()..color = const Color(0xFF444444));

    // Головка звукоснимателя на конце.
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(-s * 0.01, 0), width: s * 0.08, height: s * 0.05),
      Radius.circular(s * 0.012),
    );
    canvas.drawRRect(head, Paint()..color = const Color(0xFF383838));
    canvas.drawRRect(
        head,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: 0.85));
    // Игла на самом кончике.
    canvas.drawCircle(
        Offset(s * 0.035, 0), s * 0.009, Paint()..color = accent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TonearmPainter old) =>
      old.t != t || old.accent != accent;
}
