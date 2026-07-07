import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import 'premium_screen.dart';

/// Золотой акцент Premium.
const Color kPremiumGold = Color(0xFFF5C451);

/// Дата в формате dd.MM.yyyy (без пакета intl).
String fmtPremiumDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// Открыть экран Premium.
void openPremiumScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PremiumScreen()),
  );
}

/// Показать окно «нужен Premium» с уводом на экран Premium.
Future<void> showPremiumRequired(
  BuildContext context, {
  required String feature,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface2,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.workspace_premium, color: kPremiumGold),
              SizedBox(width: 8),
              Text('Premium',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Text('«$feature» доступно в Premium.',
              style: const TextStyle(fontSize: 14.5)),
          const SizedBox(height: 6),
          Text('Оформите подписку на Boosty и активируйте код в приложении.',
              style: TextStyle(fontSize: 12.5, color: AppColors.white60)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                openPremiumScreen(context);
              },
              child: const Text('Подробнее о Premium'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Убедиться, что есть Premium: если нет — показать окно и вернуть false.
Future<bool> ensurePremium(
  BuildContext context,
  WidgetRef ref, {
  required String feature,
}) async {
  if (ref.read(premiumProvider).isPremium) return true;
  await showPremiumRequired(context, feature: feature);
  return false;
}
