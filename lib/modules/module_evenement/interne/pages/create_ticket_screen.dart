import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/text_input_field.dart';
import '../controllers/ticket_controller.dart';

class CreateTicketScreen extends GetView<TicketController> {
  const CreateTicketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Créer un billet',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Obx(() => TextButton(
              onPressed: controller.isSaving.value ? null : controller.addTicket,
              child: controller.isSaving.value
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : Text(
                      'Enregistrer',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary,
                      ),
                    ),
            )),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextInputField(
              controller: controller.nameController,
              imputTitle: 'Nom du billet',
              imputIcon: const Icon(Icons.label_outline),
              impuHintText: 'Ex: Pass VIP, Pass Standard',
              func: (v) => v == null || v.trim().isEmpty ? 'Champ requis' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextInputField(
                    controller: controller.priceController,
                    imputTitle: 'Prix du billet',
                    imputIcon: const Icon(Icons.attach_money),
                    impuHintText: '0.00',
                    func: (v) => v == null || v.trim().isEmpty ? 'Champ requis' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Obx(() {
                      final currencyService = Get.isRegistered<CurrencyService>()
                          ? Get.find<CurrencyService>()
                          : null;
                      final availableCurrencies = currencyService?.currencies ?? [];

                      final selectedValue = availableCurrencies.any((c) => c.code == controller.currency.value)
                          ? controller.currency.value
                          : (availableCurrencies.isNotEmpty ? availableCurrencies.first.code : 'XAF');

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedValue,
                          items: (availableCurrencies.isNotEmpty
                                  ? availableCurrencies.map<DropdownMenuItem<String>>((c) => DropdownMenuItem<String>(
                                        value: c.code,
                                        child: Text(c.code),
                                      ))
                                  : <String>['XAF', 'EUR', 'USD'].map<DropdownMenuItem<String>>((e) => DropdownMenuItem<String>(
                                        value: e,
                                        child: Text(e),
                                      )))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) controller.currency.value = v;
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
