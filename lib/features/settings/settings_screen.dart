import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/update_controller.dart';
import '../../core/update_flow.dart';
import '../../core/widgets/service_badge.dart';
import '../../domain/models/source_type.dart';
import '../stats/stats_screen.dart';
import 'appearance_screen.dart';
import 'blacklist_screen.dart';
import 'dislikes_screen.dart';
import 'diagnostics_screen.dart';
import 'storage_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _RiskBanner(),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Внешний вид'),
          subtitle: Text('Тема, акцент, плеер, формы, шрифт',
              style: TextStyle(color: AppColors.white45, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AppearanceScreen())),
        ),
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
        _SoundcloudToken(settings.hasSoundcloudToken),
        const SizedBox(height: 10),
        const _SoundcloudClientId(),
        const SizedBox(height: 16),
        const _Header('Аудио'),
        Consumer(builder: (context, ref, _) {
          final pc = ref.watch(playbackProvider);
          final cf = pc.crossfade;
          return Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cf,
                title: const Text('Плавные переходы (кроссфейд)'),
                subtitle: Text('Затухание в конце и появление в начале трека',
                    style: TextStyle(color: AppColors.white45, fontSize: 11)),
                onChanged: (v) {
                  ref.read(playbackProvider).setCrossfade(v);
                  ref.read(prefsProvider).setBool('crossfade', v);
                },
              ),
              if (cf)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Row(
                    children: [
                      Text('Длительность',
                          style: TextStyle(
                              color: AppColors.white60, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: pc.crossfadeSeconds.clamp(0.3, 6.0),
                          min: 0.3,
                          max: 6.0,
                          divisions: 57,
                          label:
                              '${pc.crossfadeSeconds.toStringAsFixed(1)} с',
                          onChanged: (v) {
                            ref.read(playbackProvider).setCrossfadeSeconds(v);
                            ref
                                .read(prefsProvider)
                                .setDouble('crossfade_seconds', v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text('${pc.crossfadeSeconds.toStringAsFixed(1)}с',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
        Consumer(builder: (context, ref, _) {
          final ss = ref.watch(playbackProvider.select((p) => p.skipSilence));
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: ss,
            title: const Text('Пропуск тишины'),
            subtitle: Text('Пропускать тихие участки в начале/конце трека',
                style: TextStyle(color: AppColors.white45, fontSize: 11)),
            onChanged: (v) {
              ref.read(playbackProvider).setSkipSilence(v);
              ref.read(prefsProvider).setBool('skip_silence', v);
            },
          );
        }),
        Consumer(builder: (context, ref, _) {
          final on = ref.watch(playbackProvider.select((p) => p.normalize));
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            title: const Text('Нормализация громкости'),
            subtitle: Text('Выравнивает громкость тихих и громких треков',
                style: TextStyle(color: AppColors.white45, fontSize: 11)),
            onChanged: (v) {
              ref.read(playbackProvider).setNormalize(v);
              ref.read(prefsProvider).setBool('normalize', v);
            },
          );
        }),
        Consumer(builder: (context, ref, _) {
          final on = ref.watch(playbackProvider.select((p) => p.gapless));
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            title: const Text('Бесшовное воспроизведение (эксперим.)'),
            subtitle: Text('Без паузы между треками. Экспериментально — если '
                'что-то играет не так, выключите.',
                style: TextStyle(color: AppColors.white45, fontSize: 11)),
            onChanged: (v) {
              ref.read(playbackProvider).setGapless(v);
              ref.read(prefsProvider).setBool('gapless', v);
            },
          );
        }),
        _DataSaverTile(),
        const _RealVizTile(),
        const SizedBox(height: 16),
        const _Header('Резервная копия'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportBackup(context, ref),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Экспорт'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _importBackup(context, ref),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Импорт'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bar_chart),
          title: const Text('Статистика прослушиваний'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsScreen())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sd_storage_outlined),
          title: const Text('Управление памятью'),
          subtitle: Text('Загрузки, кэш, очистка',
              style: TextStyle(color: AppColors.white45, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StorageScreen())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block),
          title: const Text('Чёрный список артистов'),
          subtitle: Text('Скрытые из ленты и радио',
              style: TextStyle(color: AppColors.white45, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlacklistScreen())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.thumb_down_outlined),
          title: const Text('Дизлайки'),
          subtitle: Text('Треки, исключённые из рекомендаций',
              style: TextStyle(color: AppColors.white45, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DislikesScreen())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Диагностика'),
          subtitle: Text('Журнал событий источников (если что-то не играет)',
              style: TextStyle(color: AppColors.white45, fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen())),
        ),
        _AutoDlLikesTile(),
        const SizedBox(height: 16),
        const _Header('Last.fm'),
        const _Lastfm(),
        const SizedBox(height: 16),
        const _Header('Обновление'),
        const _UpdateTile(),
        const SizedBox(height: 24),
        const _About(),
      ],
    );
  }

  String _sourceHint(SourceType s) => switch (s) {
        SourceType.youtube => 'Играет внутри приложения. Ключи не нужны.',
        SourceType.soundcloud =>
          'Играет внутри. Go+ — по токену твоей подписки.',
        SourceType.yandex => 'Играет внутри. Нужен токен аккаунта (риск бана).',
      };
}

Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final data = ref.read(libraryProvider).exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/roundds_backup.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Roundds — резервная копия библиотеки',
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }
}

Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
  final file = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: ['json']);
  final path = file?.path;
  if (path == null) return;
  try {
    final content = await File(path).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    await ref.read(libraryProvider).importData(data);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Библиотека импортирована')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка импорта: $e')));
    }
  }
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

class _SoundcloudToken extends ConsumerStatefulWidget {
  const _SoundcloudToken(this.hasToken);
  final bool hasToken;
  @override
  ConsumerState<_SoundcloudToken> createState() => _SoundcloudTokenState();
}

class _SoundcloudTokenState extends ConsumerState<_SoundcloudToken> {
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
        Text(
          'OAuth-токен твоего аккаунта SoundCloud — открывает полные треки Go+, '
          'покрытые твоей подпиской.',
          style: TextStyle(fontSize: 11.5, color: AppColors.white45),
        ),
        const SizedBox(height: 8),
        if (widget.hasToken)
          Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF43E08A), size: 18),
              const SizedBox(width: 8),
              const Text('Токен сохранён'),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(settingsProvider).setSoundcloudToken(null),
                child: const Text('Удалить'),
              ),
            ],
          )
        else ...[
          TextField(
            controller: _c,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'OAuth-токен SoundCloud (2-xxxxxx-...)',
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
                  .setSoundcloudToken(_c.text.trim()),
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

class _Lastfm extends ConsumerStatefulWidget {
  const _Lastfm();
  @override
  ConsumerState<_Lastfm> createState() => _LastfmState();
}

class _LastfmState extends ConsumerState<_Lastfm> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final svc = ref.read(lastfmServiceProvider);
    setState(() {
      _busy = true;
      _msg = null;
    });
    await svc.saveCredentials(_key.text, _secret.text);
    final ok = await svc.login(_user.text, _pass.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = ok ? null : 'Не удалось войти — проверьте ключ/логин/пароль';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(lastfmServiceProvider);
    if (svc.enabled) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF43E08A), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Вошли как ${svc.username}')),
          TextButton(
            onPressed: () async {
              await ref.read(lastfmServiceProvider).logout();
              setState(() {});
            },
            child: const Text('Выйти'),
          ),
        ],
      );
    }
    InputDecoration dec(String h, {bool pass = false}) => InputDecoration(
          isDense: true,
          hintText: h,
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Скробблинг прослушиваний в ваш профиль. Создайте API-аккаунт на '
          'last.fm/api/account/create (нужны API key и shared secret), затем '
          'войдите логином и паролем. Пароль не сохраняется.',
          style: TextStyle(fontSize: 11.5, color: AppColors.white45),
        ),
        const SizedBox(height: 8),
        TextField(controller: _key, decoration: dec('API key')),
        const SizedBox(height: 8),
        TextField(controller: _secret, decoration: dec('Shared secret')),
        const SizedBox(height: 8),
        TextField(controller: _user, decoration: dec('Логин Last.fm')),
        const SizedBox(height: 8),
        TextField(
            controller: _pass, obscureText: true, decoration: dec('Пароль')),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_msg!,
                style: const TextStyle(color: Color(0xFFE24B4A), fontSize: 12)),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Войти'),
          ),
        ),
      ],
    );
  }
}

class _RealVizTile extends ConsumerWidget {
  const _RealVizTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(realVisualizerProvider);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      title: const Text('Реальный визуализатор'),
      subtitle: Text(
          'Спектр по звуку/биту (Android Visualizer). Требует разрешение '
          'микрофона — оно нужно системе для доступа к аудио, запись не ведётся.',
          style: TextStyle(color: AppColors.white45, fontSize: 11)),
      onChanged: (v) async {
        await ref.read(prefsProvider).setBool('real_visualizer', v);
        ref.read(realVisualizerProvider.notifier).state = v;
        if (v) {
          final st = await Permission.microphone.request();
          if (!st.isGranted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Без доступа к микрофону визуализатор останется декоративным')));
          }
        }
      },
    );
  }
}

class _AutoDlLikesTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AutoDlLikesTile> createState() => _AutoDlLikesTileState();
}

class _AutoDlLikesTileState extends ConsumerState<_AutoDlLikesTile> {
  @override
  Widget build(BuildContext context) {
    final on = ref.read(prefsProvider).getBool('autodl_likes') ?? false;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      title: const Text('Авто-скачивание лайков'),
      subtitle: Text('Скачивать трек офлайн при добавлении в избранное',
          style: TextStyle(color: AppColors.white45, fontSize: 11)),
      onChanged: (v) {
        ref.read(prefsProvider).setBool('autodl_likes', v);
        setState(() {});
      },
    );
  }
}

class _DataSaverTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DataSaverTile> createState() => _DataSaverTileState();
}

class _DataSaverTileState extends ConsumerState<_DataSaverTile> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(prefsProvider);
    final q = prefs.getInt('stream_quality') ??
        ((prefs.getBool('data_saver') ?? false) ? 0 : 2);
    const labels = ['Низкое', 'Среднее', 'Высокое'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 2),
          child: Text('Качество звука', style: TextStyle(fontSize: 16)),
        ),
        Text('Битрейт потока и загрузок',
            style: TextStyle(color: AppColors.white45, fontSize: 11)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(labels[i]),
                  selected: q == i,
                  onSelected: (_) {
                    prefs.setInt('stream_quality', i);
                    ref.read(youtubeSourceProvider).streamQuality = i;
                    setState(() {});
                  },
                ),
              ),
          ],
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

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.watch(updateControllerProvider);
    final version = ctl.info?.version ?? '';

    // Скачано — предлагаем установить.
    if (ctl.isReady) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.system_update),
        title: Text('Установить обновление $version'),
        subtitle: Text('Файл скачан — можно установить в любой момент',
            style: TextStyle(color: AppColors.white45, fontSize: 11)),
        trailing: const Icon(Icons.download_done),
        onTap: () => ref.read(updateControllerProvider).install(),
      );
    }

    // Идёт фоновая загрузка.
    if (ctl.isDownloading) {
      final pct = (ctl.progress * 100).round();
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.system_update),
        title: Text('Загрузка обновления $version…'),
        subtitle: Text('$pct% · продолжается в фоне',
            style: TextStyle(color: AppColors.white45, fontSize: 11)),
        trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final checking = ctl.stage == UpdateStage.checking;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.system_update),
      title: const Text('Проверить обновления'),
      subtitle: Text('Загрузка новой версии прямо из приложения',
          style: TextStyle(color: AppColors.white45, fontSize: 11)),
      trailing: checking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: checking ? null : () => checkForUpdate(context, ref, silent: false),
    );
  }
}

class _About extends ConsumerWidget {
  const _About();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: FutureBuilder<String>(
        future: ref.read(updateServiceProvider).currentVersion(),
        builder: (_, snap) => Text(
          'Roundds ${snap.data ?? ''} · не для Google Play',
          style: TextStyle(fontSize: 11, color: AppColors.white45),
        ),
      ),
    );
  }
}
