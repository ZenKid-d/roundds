import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'providers.dart';
import 'theme/accent_provider.dart';
import '../domain/models/track.dart';

/// Рендерит красивую карточку трека (обложка + название) в PNG и открывает
/// системный «Поделиться».
Future<void> shareTrackCard(
    BuildContext context, WidgetRef ref, Track track) async {
  try {
    Uint8List? cover;
    final url = track.artworkUrl;
    if (url != null && url.isNotEmpty) {
      try {
        final r = await ref.read(dioProvider).get<List<int>>(url,
            options: Options(responseType: ResponseType.bytes));
        if (r.data != null) cover = Uint8List.fromList(r.data!);
      } catch (_) {}
    }
    final accent = ref.read(effectiveAccentProvider);
    final isYt = url != null && url.contains('i.ytimg.com');

    final bytes = await ScreenshotController().captureFromWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _Card(track: track, cover: cover, accent: accent, isYt: isYt),
      ),
      pixelRatio: 1.0,
      delay: const Duration(milliseconds: 30),
    );

    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/roundds_card.png');
    await f.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(f.path)],
        text: '${track.artist} — ${track.title} · Roundds');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать карточку')));
    }
  }
}

class _Card extends StatelessWidget {
  const _Card(
      {required this.track,
      required this.cover,
      required this.accent,
      required this.isYt});
  final Track track;
  final Uint8List? cover;
  final Color accent;
  final bool isYt;

  @override
  Widget build(BuildContext context) {
    Widget coverBox;
    if (cover != null) {
      Widget img = Image.memory(cover!,
          width: 760, height: 760, fit: BoxFit.cover);
      if (isYt) img = Transform.scale(scale: 1.34, child: img);
      coverBox = ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: SizedBox(width: 760, height: 760, child: img),
      );
    } else {
      coverBox = Container(
        width: 760,
        height: 760,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.6), Colors.black],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: const Icon(Icons.music_note, color: Colors.white54, size: 120),
      );
    }

    return Container(
      width: 1080,
      height: 1080,
      padding: const EdgeInsets.all(80),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A0A0A),
            accent.withValues(alpha: 0.22),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 70,
                    spreadRadius: 4),
              ],
            ),
            child: coverBox,
          ),
          const SizedBox(height: 56),
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 58,
                fontWeight: FontWeight.w700,
                height: 1.1),
          ),
          const SizedBox(height: 16),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 40),
          ),
          const SizedBox(height: 44),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, color: accent, size: 40),
              const SizedBox(width: 10),
              const Text('Roundds',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 34,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
