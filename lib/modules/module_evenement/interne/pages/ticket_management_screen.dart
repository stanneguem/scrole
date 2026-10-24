import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../controllers/ticket_controller.dart';
import '../../centre/models/ticket_model.dart';

class TicketManagementScreen extends GetView<TicketController> {
  const TicketManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gérer les billets',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.tickets.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final isFree = controller.event.value?.isFree ?? false;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Bandeau informatif (§18)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Les billets sont actuellement présentés à titre informatif uniquement. L\'achat de billets en ligne n\'est pas encore disponible sur Scrole.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // CAS ÉVÉNEMENT GRATUIT (§2)
            if (isFree) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.money_off_rounded, size: 52, color: AppColors.success),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Événement gratuit',
                        style: AppTextStyles.h4,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cet événement est actuellement configuré comme gratuit. La gestion des billets payants est désactivée tant que l\'événement est gratuit.\n\nLes billets éventuellement configurés restent conservés en base et réapparaîtront automatiquement si vous repassez l\'événement en payant.',
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (controller.tickets.isEmpty) ...[
              // CAS ÉVÉNEMENT PAYANT SANS BILLETS (§5)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.confirmation_number_outlined, size: 52, color: AppColors.primary),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Aucun billet créé pour le moment',
                        style: AppTextStyles.h4,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créez des types de billets pour informer vos participants des tarifs d\'entrée de votre événement.',
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => Get.toNamed(
                          AppPages.eventTicketCreate.replaceFirst(':id', controller.eventId),
                          arguments: controller.event.value,
                        ),
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: const Text('Ajouter un billet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // LISTE DES BILLETS CRÉÉS
              Text(
                'BILLETS DE L\'ÉVÉNEMENT (${controller.tickets.length})',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              ...controller.tickets.map((ticket) => _TicketCard(ticket: ticket)),
            ],
          ],
        );
      }),
      floatingActionButton: Obx(() {
        final isFree = controller.event.value?.isFree ?? false;
        if (!isFree && controller.tickets.isNotEmpty) {
          return FloatingActionButton.extended(
            onPressed: () => Get.toNamed(
              AppPages.eventTicketCreate.replaceFirst(':id', controller.eventId),
              arguments: controller.event.value,
            ),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Ajouter un billet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          );
        }
        return const SizedBox.shrink();
      }),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final TicketModel ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TicketController>();
    final colors = Theme.of(context).colorScheme;

    final priceFormatted = NumberFormatter.formatPrice(ticket.price, ticket.currency);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Partie haute du Billet
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.confirmation_number_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.name.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Billet d\'entrée officiel',
                        style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  priceFormatted,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Ligne perforée style Billet de concert/cinéma
          Row(
            children: [
              Container(
                width: 12,
                height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxWidth = constraints.maxWidth;
                    const dashWidth = 5.0;
                    const dashSpace = 4.0;
                    final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(dashCount, (_) {
                        return SizedBox(
                          width: dashWidth,
                          height: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: colors.outlineVariant.withValues(alpha: 0.5)),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              Container(
                width: 12,
                height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
            ],
          ),

          // Partie basse du Billet
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.confirmation_number_outlined, size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Billet d\'entrée pour cet événement',
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                  onPressed: () => controller.deleteTicket(ticket.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Supprimer le billet',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
