import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../module_appareils/interne/controllers/device_controller.dart';
import '../../../../shared/models/user_models.dart';

class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  final DeviceController _controller = Get.find<DeviceController>();

  @override
  void initState() {
    super.initState();
    _controller.loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;
    final surface = isDark ? AppColors.black1 : AppColors.surface;
    final textPrimary = isDark ? AppColors.white : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Row(
          children: [
            Text('Devices', style: AppTextStyles.h4.copyWith(color: textPrimary, fontSize: 20)),
            const SizedBox(width: 8),
            Obx(() {
              final count = _controller.devices.length;
              if (count == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              );
            }),
          ],
        ),
      ),
      body: Obx(() {
        if (_controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_controller.errorMessage.value != null) {
          return _buildErrorState(_controller.errorMessage.value!, textPrimary, textSecondary);
        }

        final devices = _controller.devices;
        final current = devices.where((d) => d.isCurrentDevice == true).toList();
        final others = devices.where((d) => d.isCurrentDevice != true).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            Text(
              'Here are all the devices that are currently logged in with your Scrole account. You can log out of each one individually.',
              style: TextStyle(color: textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Current Device', textSecondary),
            const SizedBox(height: 12),
            if (current.isNotEmpty)
              ...current.map((d) => _DeviceTile(
                    device: d,
                    surface: surface,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    isCurrent: true,
                  ))
            else
              _buildWarningBox(surface, textSecondary, 'Current device could not be identified.'),
            const SizedBox(height: 24),
            _buildSectionHeader('Other Devices', textSecondary),
            const SizedBox(height: 12),
            if (others.isEmpty)
              _buildWarningBox(surface, textSecondary, 'No other devices are currently associated with your account.')
            else
              ...others.map((d) => _DeviceTile(
                    device: d,
                    surface: surface,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    isCurrent: false,
                    onDelete: d.id == null ? null : () => _confirmRemove(context, d.id!),
                  )),
          ],
        );
      }),
    );
  }

  Widget _buildErrorState(String message, Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text('Unable to load devices', textAlign: TextAlign.center, style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(onPressed: _controller.loadDevices, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Text(title.toUpperCase(), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }

  Widget _buildWarningBox(Color surface, Color textSecondary, String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: textSecondary, fontSize: 13))),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, String deviceId) {
    Get.dialog(
      AlertDialog(
        backgroundColor: AppColors.black1,
        title: Text('Log out of this device?', style: AppTextStyles.h4.copyWith(color: Colors.white)),
        content: const Text('This device will be removed from your account.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () async {
              Get.back();
              try {
                await _controller.removeDevice(deviceId);
              } catch (_) {
                Get.snackbar('Error', 'Unable to log out of this device.', snackPosition: SnackPosition.BOTTOM);
              }
            },
            child: const Text('Log Out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceInfos device;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final bool isCurrent;
  final VoidCallback? onDelete;

  const _DeviceTile({
    required this.device,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.isCurrent,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final platform = device.platform?.trim().toLowerCase();
    final icon = platform == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded;
    final platformLabel = platform == 'ios'
        ? 'iOS'
        : platform == 'android'
            ? 'Android'
            : (device.platform?.trim().isNotEmpty == true ? device.platform! : 'Unknown');
    final model = device.deviceModel?.trim().isNotEmpty == true
        ? device.deviceModel!.trim()
        : platform == 'ios'
            ? 'iPhone / iPad'
            : platform == 'android'
                ? 'Android device'
                : 'Unknown device';
    final appVersion = device.appVersion?.trim().isNotEmpty == true ? device.appVersion!.trim() : 'Unknown';
    final country = device.detectedCountry?.trim().isNotEmpty == true ? device.detectedCountry!.trim() : 'Unknown';
    final lastActivity = device.lastSeenAt != null ? _formatDateTime(device.lastSeenAt!) : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(model, style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    if (isCurrent)
                      const Text('Current', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoLine(label: 'Platform', value: platformLabel, color: textSecondary),
                _InfoLine(label: 'App version', value: appVersion, color: textSecondary),
                _InfoLine(label: 'Country', value: country, color: textSecondary),
                _InfoLine(label: 'Last activity', value: lastActivity, color: textSecondary),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 20), onPressed: onDelete),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}
