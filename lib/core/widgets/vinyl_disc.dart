import 'package:flutter/material.dart';

import 'artwork.dart';

/// Вращающийся винил: обложка вшита в центр чёрной пластинки.
/// Крутится при игре, плавно замирает на паузе. Свечение — в акцентном цвете.
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
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: s,
      height: s,
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
        child: CustomPaint(
          painter: _GroovePainter(),
          child: Center(
            child: Container(
              width: s * 0.42,
              height: s * 0.42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black, blurRadius: 0, spreadRadius: 4),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(widget.artworkUrl,
                        radius: 999, seed: widget.seed),
                    Center(
                      child: Container(
                        width: s * 0.06,
                        height: s * 0.06,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          border: Border.all(
                              color: Colors.white24, width: 2),
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
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double r = maxR * 0.45; r < maxR; r += 3) {
      paint.color = Color.lerp(
          const Color(0xFF0A0A0A), const Color(0xFF1A1A1A), (r / maxR))!;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
