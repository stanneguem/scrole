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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.backgroundDark : AppColors.background;
    final surface = dark ? AppColors.surfaceDark : AppColors.surface;
    final primary = dark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondary = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          tooltip: 'devices_cancel'.tr,
          icon: Icon(Icons.arrow_back_rounded, color: primary),
          onPressed: () => Get.back(),
        ),
        title: Obx(() => Row(children: [
          Expanded(child: Text('devices_title'.tr, style: AppTextStyles.h4.copyWith(color: primary))),
          if (_controller.devices.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
              child: Text('${_controller.devices.length}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
        ])),
        actions: [
          Obx(() => IconButton(
            tooltip: 'devices_retry'.tr,
            onPressed: _controller.isLoading.value ? null : _controller.loadDevices,
            icon: _controller.isLoading.value
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh_rounded, color: primary),
          )),
        ],
      ),
      body: Obx(() {
        if (_controller.isLoading.value && _controller.devices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_controller.errorMessage.value != null && _controller.devices.isEmpty) {
          return _errorState(primary, secondary);
        }
        final all = _controller.devices.toList(growable: false);
        final current = all.where((d) => d.isCurrentDevice == true).toList();
        final others = all.where((d) => d.isCurrentDevice != true).toList();
        return RefreshIndicator(
          onRefresh: _controller.loadDevices,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .35)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.shield_outlined, color: AppColors.primary, size: 25),
                  const SizedBox(width: 12),
                  Expanded(child: Text('devices_intro'.tr, style: TextStyle(color: secondary, height: 1.45, fontSize: 14))),
                ]),
              ),
              const SizedBox(height: 24),
              _section('devices_current'.tr, secondary),
              const SizedBox(height: 10),
              if (current.isEmpty) _notice(surface, secondary, 'devices_current_unknown'.tr)
              else ...current.map((d) => _DeviceTile(device: d, surface: surface, primary: primary, secondary: secondary, isCurrent: true)),
              const SizedBox(height: 20),
              _section('devices_others'.tr, secondary),
              const SizedBox(height: 10),
              if (others.isEmpty) _notice(surface, secondary, 'devices_empty'.tr)
              else ...others.map((d) => _DeviceTile(
                key: ValueKey(d.id ?? d.deviceToken ?? d.deviceModel ?? 'device'),
                device: d, surface: surface, primary: primary, secondary: secondary, isCurrent: false,
                isRemoving: d.id != null && _controller.removingDeviceIds.contains(d.id),
                onDelete: d.id == null ? null : () => _confirmRemove(d.id!),
              )),
              if (_controller.errorMessage.value != null) ...[
                const SizedBox(height: 12),
                Text(_controller.errorMessage.value!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
            ],
          ),
        );
      }),
    );
  }

  Widget _errorState(Color primary, Color secondary) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 42),
        const SizedBox(height: 12),
        Text('devices_error_title'.tr, textAlign: TextAlign.center,
          style: TextStyle(color: primary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_controller.errorMessage.value ?? 'devices_error_generic'.tr, textAlign: TextAlign.center, style: TextStyle(color: secondary, fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _controller.loadDevices, icon: const Icon(Icons.refresh_rounded), label: Text('devices_retry'.tr)),
      ]),
    ),
  );

  Widget _section(String title, Color color) => Text(title.toUpperCase(),
    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .7));

  Widget _notice(Color surface, Color secondary, String message) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, color: secondary, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: TextStyle(color: secondary, fontSize: 13, height: 1.4))),
    ]),
  );

  Future<void> _confirmRemove(String id) async {
    final confirmed = await Get.dialog<bool>(AlertDialog(
      title: Text('devices_remove_title'.tr),
      content: Text('devices_remove_body'.tr),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: Text('devices_cancel'.tr)),
        TextButton(onPressed: () => Get.back(result: true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error), child: Text('devices_remove'.tr)),
      ],
    ));
    if (confirmed != true) return;
    try {
      await _controller.removeDevice(id);
      if (mounted) Get.snackbar('devices_title'.tr, 'devices_remove_success'.tr, snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      if (mounted) Get.snackbar('devices_title'.tr, _controller.errorMessage.value ?? 'devices_remove_error'.tr, snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({super.key, required this.device, required this.surface, required this.primary, required this.secondary, required this.isCurrent, this.isRemoving = false, this.onDelete});
  final DeviceInfos device;
  final Color surface, primary, secondary;
  final bool isCurrent, isRemoving;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final platform = device.platform?.trim().toLowerCase();
    final icon = platform == 'ios' ? Icons.phone_iphone_rounded : platform == 'android' ? Icons.phone_android_rounded : Icons.devices_other_rounded;
    final model = device.deviceModel?.trim().isNotEmpty == true ? device.deviceModel!.trim()
      : platform == 'ios' ? 'iPhone / iPad' : platform == 'android' ? 'Android' : 'devices_unknown'.tr;
    final platformLabel = platform == 'ios' ? 'iOS' : platform == 'android' ? 'Android'
      : (device.platform?.trim().isNotEmpty == true ? device.platform!.trim() : 'devices_unknown'.tr);
    final version = device.appVersion?.trim().isNotEmpty == true ? device.appVersion!.trim() : 'devices_unknown'.tr;
    final country = device.detectedCountry?.trim().isNotEmpty == true ? device.detectedCountry!.trim() : 'devices_unknown'.tr;
    final activity = device.lastSeenAt == null ? 'devices_unknown'.tr : _formatDateTime(device.lastSeenAt!);

    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isCurrent ? AppColors.primary.withValues(alpha: .55) : Theme.of(context).dividerColor.withValues(alpha: .35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: AppColors.primary, size: 24)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(model, style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 15))),
            if (isCurrent) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
              child: Text('devices_current_badge'.tr, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 9),
          _InfoLine(label: 'devices_platform'.tr, value: platformLabel, color: secondary),
          _InfoLine(label: 'devices_version'.tr, value: version, color: secondary),
          _InfoLine(label: 'devices_country'.tr, value: country, color: secondary),
          _InfoLine(label: 'devices_last_activity'.tr, value: activity, color: secondary),
        ])),
        if (onDelete != null) IconButton(
          tooltip: 'devices_remove'.tr, onPressed: isRemoving ? null : onDelete,
          icon: isRemoving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.logout_rounded, color: AppColors.error, size: 21),
        ),
      ]),
    );
  }

  String _formatDateTime(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$label: $value', style: TextStyle(color: color, fontSize: 12.5, height: 1.35)),
  );
}
