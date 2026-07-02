import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

/// Чёрный список артистов: их треки не попадают в ленту, рекомендации и радио.
class BlacklistScreen extends ConsumerWidget {
  const BlacklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(libraryProvider).blacklistedArtists;
    return Scaffold(
      appBar: AppBar(title: const Text('Чёрный список артистов')),
      body: artists.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Пусто. Чтобы скрыть артиста — долгий тап на его треке → '
                  '«Скрыть артиста».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white45),
                ),
              ),
            )
          : ListView(
              children: [
                for (final a in artists)
                  ListTile(
                    leading: const Icon(Icons.block, size: 20),
                    title: Text(a),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          ref.read(libraryProvider).unblacklistArtist(a),
                    ),
                  ),
              ],
            ),
    );
  }
}
