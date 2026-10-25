import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/service_global/app_config_service.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = Get.find<AppConfigService>();
    final colors = Theme.of(context).colorScheme;
    final message = config.updateMessage.value.trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 104, width: 104,
                    decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
                    child: Icon(Icons.system_update_rounded, size: 54, color: colors.primary),
                  ),
                  const SizedBox(height: 28),
                  Text('update_required_title'.tr, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Text(message.isEmpty ? 'update_required_message'.tr : message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: () => _openStore(config),
                    icon: const Icon(Icons.download_rounded),
                    label: Text('update_button'.tr),
                  )),
                  const SizedBox(height: 12),
                  Text('${'update_required_version'.tr}: ${config.currentServerVersion.value}', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(AppConfigService config) async {
    final rawUrl = Platform.isIOS ? config.iosStoreUrl.value : config.androidStoreUrl.value;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr, snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr, snackPosition: SnackPosition.BOTTOM);
    }
  }
}
