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
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Вся обложка кругом — квадратные края обрезаны.
              Artwork(widget.artworkUrl,
                  size: s, radius: 999, seed: widget.seed),
              // Дырка по центру, как у пластинки.
              Center(
                child: Container(
                  width: s * 0.05,
                  height: s * 0.05,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: Colors.white38, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
