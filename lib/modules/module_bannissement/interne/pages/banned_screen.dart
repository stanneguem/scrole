import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:scrole/app_controller.dart';

class BannedScreen extends StatelessWidget {
  final String? reason;
  final DateTime? bannedUntil;
  final String? userId;

  const BannedScreen({
    super.key,
    this.reason,
    this.bannedUntil,
    this.userId,
  });

  bool get isPermanent => bannedUntil == null;

  String get _formattedDate {
    if (bannedUntil == null) return '';
    final d = bannedUntil!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _copyUserId(BuildContext context) {
    if (userId == null) return;
    Clipboard.setData(ClipboardData(text: userId!));
    Get.snackbar(
      'copied'.tr,
      'banned_id_copied'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              onPressed: () {
                Get.offAllNamed('/login');
              },
              icon: Icon(Icons.logout_rounded, size: 18, color: colorScheme.error),
              label: Text(
                'drawer_logout'.tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                backgroundColor: colorScheme.error.withValues(alpha: 0.1),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Icon Container ---
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: Colors.redAccent,
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // --- Title ---
                  Text(
                    'banned_title'.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- Subtitle / Message ---
                  Text(
                    isPermanent
                        ? 'banned_msg_permanent'.tr
                        : 'banned_msg_temporary'.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- Details Card ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (reason != null && reason!.isNotEmpty) ...[
                          _DetailRow(
                            icon: Icons.info_outline_rounded,
                            label: 'banned_reason_label'.tr,
                            value: reason!,
                          ),
                          const SizedBox(height: 14),
                        ],
                        _DetailRow(
                          icon: Icons.timer_outlined,
                          label: 'banned_duration_label'.tr,
                          value: isPermanent ? 'banned_permanent'.tr : 'banned_until'.trParams({'date': _formattedDate}),
                        ),
                        if (userId != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _DetailRow(
                                  icon: Icons.badge_outlined,
                                  label: 'banned_user_id_label'.tr,
                                  value: userId!,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.copy_rounded, size: 18, color: colorScheme.primary),
                                tooltip: 'banned_copy_id_tooltip'.tr,
                                onPressed: () => _copyUserId(context),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Check Status / Refresh Button ---
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (Get.isRegistered<AppController>()) {
                          await Get.find<AppController>().forceRefresh();
                        }
                      },
                      icon: Icon(Icons.refresh_rounded, size: 20, color: colorScheme.primary),
                      label: Text('Vérifier le statut', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          '$label : ',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}
