import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/premium/premium_config.dart';
import '../../core/premium/premium_controller.dart';
import '../../core/premium/wave_quota.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import 'premium_gate.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openBoosty() async {
    final uri = Uri.parse(kBoostyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть Boosty')),
      );
    }
  }

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    final result = await ref.read(premiumProvider).redeem(code);
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = switch (result) {
      RedeemResult.ok => 'Premium активирован ✓',
      RedeemResult.expired => 'Код просрочен — нужен новый',
      RedeemResult.invalid => 'Неверный код',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
    if (result == RedeemResult.ok) {
      _codeCtrl.clear();
      // Снять клампинг качества, если пользователь ранее выбирал «Высокое».
      final q = ref.read(prefsProvider).getInt('stream_quality');
      if (q != null) ref.read(youtubeSourceProvider).streamQuality = q;
    }
  }

  Future<void> _unlink() async {
    await ref.read(premiumProvider).clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Код отвязан')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumProvider);
    final quota = ref.read(waveQuotaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StatusCard(premium: premium),
          const SizedBox(height: 20),
          const _SectionTitle('Что даёт Premium'),
          const _Perk(
            icon: Icons.download_rounded,
            title: 'Скачивание оффлайн',
            subtitle: 'Треки и плейлисты в память устройства',
          ),
          const _Perk(
            icon: Icons.high_quality_rounded,
            title: 'Максимальное качество',
            subtitle: 'Без ограничения битрейта потока и загрузок',
          ),
          _Perk(
            icon: Icons.graphic_eq_rounded,
            title: '«Моя волна» без лимита',
            subtitle: premium.isPremium
                ? 'Безлимит активен'
                : 'Бесплатно — ${WaveQuota.freeDailyLimit} треков в день '
                    '(сегодня осталось ${quota.remaining})',
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Оформление'),
          Text(
            'Оплата — через Boosty ($kPremiumPriceLabel). После оплаты вы '
            'получаете код доступа, который активируется ниже.',
            style: TextStyle(fontSize: 13, color: AppColors.white60),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openBoosty,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Оформить на Boosty'),
              style: FilledButton.styleFrom(
                backgroundColor: kPremiumGold,
                foregroundColor: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Активация кода'),
          TextField(
            controller: _codeCtrl,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Вставьте код доступа (RD1.…)',
              filled: true,
              fillColor: AppColors.surface2,
              suffixIcon: IconButton(
                tooltip: 'Вставить',
                icon: const Icon(Icons.paste, size: 20),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _codeCtrl.text = data!.text!.trim();
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _redeem,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Активировать'),
            ),
          ),
          if (premium.isPremium || premium.isExpired) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _unlink,
                child: Text('Отвязать код',
                    style: TextStyle(color: AppColors.white60)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Оплата и вывод средств выполняются на стороне Boosty. Код '
            'действует на срок подписки; проверка проходит на устройстве, '
            'без интернета и передачи данных.',
            style: TextStyle(fontSize: 11.5, color: AppColors.white45),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.premium});
  final PremiumController premium;

  @override
  Widget build(BuildContext context) {
    final active = premium.isPremium;
    final color = active ? kPremiumGold : AppColors.white45;
    final title = active
        ? 'Premium активен'
        : (premium.isExpired ? 'Подписка истекла' : 'Premium не активен');
    final sub = active
        ? 'До ${fmtPremiumDate(premium.expiry!)}'
        : (premium.isExpired
            ? 'Оформите новый код, чтобы продлить'
            : 'Оформите подписку на Boosty');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(sub,
                    style:
                        TextStyle(fontSize: 12.5, color: AppColors.white60)),
                if (active && premium.owner != null) ...[
                  const SizedBox(height: 2),
                  Text('Владелец: ${premium.owner}',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.white45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _Perk extends StatelessWidget {
  const _Perk({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: kPremiumGold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: AppColors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
