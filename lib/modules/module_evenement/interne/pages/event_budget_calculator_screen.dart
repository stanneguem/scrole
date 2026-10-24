import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../controllers/event_budget_controller.dart';

class EventBudgetCalculatorScreen extends GetView<EventBudgetController> {
  const EventBudgetCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CALCULER MON BUDGET'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionTitle(title: '1. Choisissez votre billet'),
                const SizedBox(height: 12),
                if (controller.tickets.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.money_off_rounded, color: AppColors.success, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Entrée Gratuite', style: AppTextStyles.h4),
                                Text('Aucun billet payant requis', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('Gratuit', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else
                  ...controller.tickets.map((ticket) => Obx(() {
                    final isSelected = controller.selectedTicket.value?.id == ticket.id;
                    return GestureDetector(
                      onTap: () => controller.selectedTicket.value = ticket,
                      child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.5),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CupertinoRadio<String>(
                                value: ticket.id,
                                groupValue: controller.selectedTicket.value?.id,
                                onChanged: (_) => controller.selectedTicket.value = ticket,
                                activeColor: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ticket.name, style: AppTextStyles.h4),
                                    Text(
                                      ticket.converted.amount <= 0
                                          ? 'Gratuit'
                                          : NumberFormatter.formatPrice(ticket.converted.amount, ticket.converted.symbol),
                                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  })).toList(),

                const SizedBox(height: 32),
                _SectionTitle(title: '2. Sélectionnez vos activités'),
                const SizedBox(height: 12),
                if (controller.activities.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.extension_off_rounded, color: colors.onSurfaceVariant, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Aucune activité payante liée',
                              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                            ),
                          ),
                          Text('Gratuit', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else
                  ...controller.activities.map((activity) => Obx(() {
                    final isSelected = controller.selectedActivityIds.contains(activity.activityId);
                    return GestureDetector(
                      onTap: () => controller.toggleActivity(activity.activityId),
                      child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : colors.outlineVariant.withValues(alpha: 0.5),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(activity.name, style: AppTextStyles.labelLarge),
                                    Text(
                                      activity.converted.amount <= 0
                                          ? 'Gratuit'
                                          : NumberFormatter.formatPrice(activity.converted.amount, activity.converted.symbol),
                                      style: TextStyle(
                                        color: isSelected ? AppColors.primary : colors.onSurfaceVariant,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoCheckbox(
                                value: isSelected,
                                onChanged: (_) => controller.toggleActivity(activity.activityId),
                                activeColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  })).toList(),

                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Note : Cette somme ne comprend pas les frais de transport. Prévoyez un budget supplémentaire selon votre trajet.',
                          style: AppTextStyles.bodySmall.copyWith(color: colors.onSurface.withValues(alpha: 0.8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: _buildBudgetBar(context),
    );
  }

  Widget _buildBudgetBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SOMME À PRÉVOIR', style: AppTextStyles.caption.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
              Obx(() => Text(
                controller.totalBudget <= 0
                    ? 'Gratuit'
                    : NumberFormatter.formatPrice(controller.totalBudget, controller.currency),
                style: AppTextStyles.h2.copyWith(color: AppColors.primary),
              )),
            ],
          ),
          ElevatedButton(
            onPressed: () => Get.back(),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('C\'est noté !'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.h4.copyWith(color: Theme.of(context).colorScheme.onSurface),
    );
  }
}
