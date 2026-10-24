import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';

/// Écran informatif des certifications. Aucun paiement n'est lancé ici.
class CertificationPlansScreen extends StatefulWidget {
  const CertificationPlansScreen({super.key});

  @override
  State<CertificationPlansScreen> createState() => _CertificationPlansScreenState();
}

class _CertificationPlansScreenState extends State<CertificationPlansScreen> {
  bool _loading = true;
  String? _error;
  String? _countryName;
  List<_Plan> _plans = const [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('certification_auth_required'.tr);

      final profile = await client.from('user_profiles')
          .select('country_id').eq('user_id', user.id).maybeSingle();
      final countryId = profile?['country_id']?.toString();
      String? countryName;
      final priceByType = <String, _Price>{};

      if (countryId != null && countryId.isNotEmpty) {
        final country = await client.from('countries')
            .select('nom').eq('id', countryId).maybeSingle();
        countryName = country?['nom']?.toString();

        final mappings = await client.from('certification_prix_group_pays')
            .select('prix_groupe').eq('pays_id', countryId);
        final ids = mappings.map((r) => r['prix_groupe']?.toString())
            .whereType<String>().where((id) => id.isNotEmpty).toSet().toList();

        if (ids.isNotEmpty) {
          final groups = await client.from('certification_prix_groupe')
              .select('id, nom, prix, devise, certification_type_id')
              .eq('est_actif', true).inFilter('id', ids);
          for (final row in groups) {
            final typeId = row['certification_type_id']?.toString();
            if (typeId == null || typeId.isEmpty) continue;
            priceByType[typeId] = _Price(
              amount: (row['prix'] as num?)?.toDouble(),
              currency: row['devise']?.toString() ?? '',
              group: row['nom']?.toString() ?? '',
            );
          }
        }
      }

      final rows = await client.from('certification_type')
          .select('id, code, nom, description').eq('est_actif', true);
      final plans = rows.map((row) {
        final code = (row['code']?.toString() ?? '').toLowerCase();
        return _Plan(
          id: row['id']?.toString() ?? code,
          code: code,
          name: row['nom']?.toString() ?? code,
          description: row['description']?.toString() ?? '',
          price: priceByType[row['id']?.toString()],
        );
      }).toList()
        ..sort((a, b) => _order(a.code).compareTo(_order(b.code)));

      if (!mounted) return;
      setState(() {
        _countryName = countryName;
        _plans = plans;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  int _order(String code) => const {'basique': 0, 'pro': 1, 'premium': 2}[code] ?? 3;

  void _showUnavailable() {
    Get.snackbar(
      'certification_unavailable_title'.tr,
      'certification_unavailable_message'.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.black,
      colorText: AppColors.white,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.backgroundDark : AppColors.background;
    final text = dark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: Text('certification_screen_title'.tr,
            style: AppTextStyles.h5.copyWith(color: text)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _Message(
                    icon: Icons.cloud_off_rounded,
                    title: 'certification_load_error_title'.tr,
                    message: _error!,
                    primary: text,
                    secondary: muted,
                    actionLabel: 'retry'.tr,
                    onAction: _loadPlans,
                  )
                : RefreshIndicator(
                    onRefresh: _loadPlans,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: dark
                                  ? const [Color(0xFF292D36), Color(0xFF1A1D24)]
                                  : const [Color(0xFFFFF1EA), Color(0xFFFFF8F4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.verified_user_rounded,
                                  color: AppColors.primary, size: 36),
                              const SizedBox(height: 12),
                              Text('certification_intro_title'.tr,
                                  style: AppTextStyles.h4.copyWith(color: text)),
                              const SizedBox(height: 8),
                              Text('certification_intro_body'.tr,
                                  style: AppTextStyles.body.copyWith(color: muted, height: 1.55)),
                              if (_countryName != null) ...[
                                const SizedBox(height: 12),
                                Text('certification_country_label'.trParams(
                                  {'country': _countryName!},
                                ), style: AppTextStyles.labelMedium.copyWith(color: muted)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(child: Text('certification_choose_plan'.tr,
                                style: AppTextStyles.h5.copyWith(color: text))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('certification_coming_soon'.tr,
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_plans.isEmpty)
                          _Message(
                            icon: Icons.workspace_premium_outlined,
                            title: 'certification_no_plans_title'.tr,
                            message: 'certification_no_plans_message'.tr,
                            primary: text,
                            secondary: muted,
                          )
                        else
                          for (final plan in _plans)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _PlanCard(
                                plan: plan,
                                dark: dark,
                                primary: text,
                                secondary: muted,
                                onUnavailable: _showUnavailable,
                              ),
                            ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: dark ? AppColors.surfaceDark : AppColors.surface,
                            border: Border.all(color: dark ? AppColors.black1 : AppColors.border),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: muted, size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Text('certification_payment_notice'.tr,
                                  style: AppTextStyles.bodySmall.copyWith(color: muted, height: 1.5))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _Plan {
  const _Plan({required this.id, required this.code, required this.name,
    required this.description, required this.price});
  final String id;
  final String code;
  final String name;
  final String description;
  final _Price? price;

  String get title {
    switch (code) {
      case 'basique': return 'certification_basic_name'.tr;
      case 'pro': return 'certification_pro_name'.tr;
      case 'premium': return 'certification_premium_name'.tr;
      default: return name;
    }
  }

  String get subtitle {
    switch (code) {
      case 'basique': return 'certification_basic_description'.tr;
      case 'pro': return 'certification_pro_description'.tr;
      case 'premium': return 'certification_premium_description'.tr;
      default: return description;
    }
  }

  List<String> get features {
    switch (code) {
      case 'basique':
        return ['certification_basic_feature_1'.tr, 'certification_basic_feature_2'.tr,
          'certification_basic_feature_3'.tr];
      case 'pro':
        return ['certification_pro_feature_1'.tr, 'certification_pro_feature_2'.tr,
          'certification_pro_feature_3'.tr];
      case 'premium':
        return ['certification_premium_feature_1'.tr, 'certification_premium_feature_2'.tr,
          'certification_premium_feature_3'.tr];
      default:
        return description.isEmpty ? [] : [description];
    }
  }
}

class _Price {
  const _Price({required this.amount, required this.currency, required this.group});
  final double? amount;
  final String currency;
  final String group;
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.dark, required this.primary,
    required this.secondary, required this.onUnavailable});
  final _Plan plan;
  final bool dark;
  final Color primary;
  final Color secondary;
  final VoidCallback onUnavailable;

  bool get premium => plan.code == 'premium';
  bool get pro => plan.code == 'pro';

  String get priceLabel {
    final p = plan.price;
    if (p == null || p.amount == null || p.currency.isEmpty) {
      return 'certification_price_unavailable'.tr;
    }
    final amount = NumberFormat.decimalPattern(Get.locale?.languageCode ?? 'fr').format(p.amount);
    return amount + ' ' + p.currency;
  }

  @override
  Widget build(BuildContext context) {
    final border = premium ? AppColors.primary : (dark ? AppColors.black1 : AppColors.border);
    final iconColor = premium ? AppColors.primary : (pro ? AppColors.blue : AppColors.success);
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: premium ? 1.8 : 1),
        boxShadow: premium ? [BoxShadow(
          color: AppColors.primary.withValues(alpha: .10),
          blurRadius: 18, offset: const Offset(0, 7),
        )] : null,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14)),
              child: Icon(premium ? Icons.workspace_premium_rounded
                  : (pro ? Icons.stars_rounded : Icons.verified_user_rounded),
                  color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(plan.title,
                    style: AppTextStyles.h5.copyWith(color: primary))),
                if (premium) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text('certification_popular'.tr,
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(plan.subtitle,
                style: AppTextStyles.bodySmall.copyWith(color: secondary, height: 1.45)),
            ])),
          ]),
          const SizedBox(height: 18),
          Text(priceLabel, style: AppTextStyles.h3.copyWith(color: primary,
            fontWeight: FontWeight.w700)),
          if (plan.price != null && plan.price!.group.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('certification_price_group'.trParams({'group': plan.price!.group}),
              style: AppTextStyles.caption.copyWith(color: secondary)),
          ],
          const SizedBox(height: 16),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                const SizedBox(width: 9),
                Expanded(child: Text(feature,
                  style: AppTextStyles.body.copyWith(color: primary, height: 1.4))),
              ]),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onUnavailable,
              style: OutlinedButton.styleFrom(
                foregroundColor: premium ? AppColors.primary : secondary,
                side: BorderSide(color: premium ? AppColors.primary.withValues(alpha: .65) : border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('certification_subscribe_unavailable'.tr,
                  style: AppTextStyles.buttonSmall, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.message,
    required this.primary, required this.secondary, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final Color primary;
  final Color secondary;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 42, color: secondary),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center,
        style: AppTextStyles.h5.copyWith(color: primary)),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: secondary, height: 1.5)),
      if (actionLabel != null && onAction != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ]),
  );
}
