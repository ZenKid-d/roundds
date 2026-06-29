import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/service_badge.dart';
import '../../domain/models/source_type.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _RiskBanner(),
        const SizedBox(height: 16),
        const _Header('Источники'),
        for (final s in SourceType.values)
          SwitchListTile(
            value: settings.isEnabled(s),
            onChanged: (v) =>
                ref.read(settingsProvider).toggleSource(s, v),
            secondary: ServiceBadge(s, size: 26),
            title: Text(s.label),
            subtitle: Text(_sourceHint(s),
                style: TextStyle(color: AppColors.white45, fontSize: 11)),
          ),
        const SizedBox(height: 16),
        const _Header('Яндекс Музыка'),
        _YandexToken(settings.hasYandexToken),
        const SizedBox(height: 16),
        const _Header('SoundCloud'),
        const _SoundcloudClientId(),
        const SizedBox(height: 24),
        const _About(),
      ],
    );
  }

  String _sourceHint(SourceType s) => switch (s) {
        SourceType.youtube => 'Играет внутри приложения. Ключи не нужны.',
        SourceType.soundcloud => 'Играет внутри. Нужен публичный client_id.',
        SourceType.yandex => 'Играет внутри. Нужен токен аккаунта (риск бана).',
      };
}

class _RiskBanner extends StatelessWidget {
  const _RiskBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFE24B4A), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Воспроизведение использует неофициальные методы. Это нарушает '
              'правила сервисов и авторские права, может ломаться при их '
              'обновлениях, а токен Яндекса несёт риск блокировки аккаунта. '
              'Ответственность за использование — на вас.',
              style: TextStyle(fontSize: 11.5, color: AppColors.white60, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _YandexToken extends ConsumerStatefulWidget {
  const _YandexToken(this.hasToken);
  final bool hasToken;
  @override
  ConsumerState<_YandexToken> createState() => _YandexTokenState();
}

class _YandexTokenState extends ConsumerState<_YandexToken> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.hasToken)
          Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF43E08A), size: 18),
              const SizedBox(width: 8),
              const Text('Токен сохранён'),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(settingsProvider).setYandexToken(null),
                child: const Text('Удалить'),
              ),
            ],
          )
        else ...[
          TextField(
            controller: _c,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'OAuth-токен Яндекс Музыки',
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => ref
                  .read(settingsProvider)
                  .setYandexToken(_c.text.trim()),
              child: const Text('Сохранить токен'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SoundcloudClientId extends ConsumerStatefulWidget {
  const _SoundcloudClientId();
  @override
  ConsumerState<_SoundcloudClientId> createState() =>
      _SoundcloudClientIdState();
}

class _SoundcloudClientIdState extends ConsumerState<_SoundcloudClientId> {
  bool _loading = false;
  String? _status;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final id = await ref.read(soundcloudSourceProvider).refreshClientId();
      await ref.read(prefsProvider).setString('sc_client_id', id);
      setState(() => _status = 'Обновлён ✓');
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _status ??
                'client_id определяется автоматически. Если SoundCloud '
                    'перестал играть — обновите его.',
            style: TextStyle(fontSize: 11.5, color: AppColors.white45),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _loading ? null : _refresh,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Обновить'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      );
}

class _About extends StatelessWidget {
  const _About();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('Roundds 0.1 · не для Google Play',
            style: TextStyle(fontSize: 11, color: AppColors.white45)),
      );
}
