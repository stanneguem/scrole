import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/utils/supabase_error_mapper.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../controllers/profile_controller.dart';

class UserQrIdentityScreen extends StatefulWidget {
  const UserQrIdentityScreen({super.key});

  @override
  State<UserQrIdentityScreen> createState() => _UserQrIdentityScreenState();
}

class _UserQrIdentityScreenState extends State<UserQrIdentityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController();
  final SocialRepository _socialRepo = SocialRepository();

  Map<String, dynamic>? _activeQrCode;
  bool _isLoadingQr = true;
  bool _isSyncingQr = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadQrCode();
  }

  Future<void> _loadQrCode() async {
    setState(() => _isLoadingQr = true);
    try {
      final qr = await _socialRepo.getOrGenerateUserQrCode();
      if (mounted) {
        setState(() {
          _activeQrCode = qr;
          _isLoadingQr = false;
        });
      }
    } catch (e) {
      debugPrint('[UserQrIdentityScreen] Error loading QR: $e');
      if (mounted) setState(() => _isLoadingQr = false);
    }
  }

  Future<void> _syncCurrentQrCode() async {
    final qr = _activeQrCode;
    if (qr == null || _isSyncingQr) return;
    setState(() => _isSyncingQr = true);
    try {
      await _socialRepo.syncUserQrCode(qr);
      if (!mounted) return;
      setState(() {
        _activeQrCode = {...qr, 'sync_status': 'synced'};
        _isSyncingQr = false;
      });
      Get.snackbar(
        'QR code synchronisé',
        'Ton QR code est maintenant enregistré sur le serveur.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('[UserQrIdentityScreen] QR sync failed: $e');
      if (!mounted) return;
      setState(() => _isSyncingQr = false);
      Get.snackbar(
        'Synchronisation impossible',
        'Le QR code est conservé sur cet appareil. Vérifie ta connexion puis réessaie.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _forceRegenerateQrCode() async {
    setState(() => _isLoadingQr = true);
    try {
      final newUuid = _socialRepo.generateLocalUuid();
      final userId = _socialRepo.currentUserId ?? '';
      final localQr = {
        'id': newUuid,
        'user_id': userId,
        'uses_remaining': 3,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'pending_push',
      };
      await _socialRepo.dao.saveUserQrCodes([localQr]);
      await _socialRepo.dao.enqueueOutbox(
        userId: userId,
        operation: 'generate_user_qr_code',
        payload: {'id': newUuid},
      );
      if (mounted) {
        setState(() {
          _activeQrCode = localQr;
          _isLoadingQr = false;
        });
      }
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      if (mounted) setState(() => _isLoadingQr = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetectBarcode(BarcodeCapture capture) {
    if (_isScanning) return;

    final barcode = capture.barcodes.firstOrNull;
    final String? rawValue = barcode?.rawValue;

    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _isScanning = true);

    if (rawValue.startsWith('scrole_user:')) {
      final userId = rawValue.replaceFirst('scrole_user:', '');
      Get.toNamed(AppPages.externalProfilePath(userId));
      setState(() => _isScanning = false);
      return;
    }

    String qrId = rawValue;
    if (rawValue.startsWith('scrole_qr:')) {
      qrId = rawValue.replaceFirst('scrole_qr:', '');
    }

    _performScan(qrId);
  }

  Future<void> _performScan(String qrId) async {
    try {
      debugPrint('[FOLLOW] personal QR scan p_qr_id=$qrId p_mode=null');
      final result = await _socialRepo.scanQrCode(qrId);
      final friendId = result != null
          ? (result['friend_id'] ?? result['user_id'] ?? result['receiver_id'])?.toString()
          : null;
      if (friendId == null || friendId.isEmpty) {
        throw StateError('follow_action_impossible');
      }
      final displayName = (result?['name'] ?? result?['username'] ?? '').toString();
      Get.snackbar(
        'follow_qr_success_title'.tr,
        'follow_qr_success_message'.trParams({'name': displayName.isEmpty ? friendId : displayName}),
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      await Get.toNamed(AppPages.externalProfilePath(friendId));
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC scan_qr_code exception=$e\\n$stack');
      final raw = e.toString().toLowerCase();
      final key = raw.contains('qr_not_found') || raw.contains('qr code not found') || raw.contains('qr code introuvable')
          ? 'follow_qr_not_found'
          : raw.contains('qr_expired') || raw.contains('qr_invalid') || raw.contains('no longer valid') || raw.contains('plus valide')
              ? 'follow_qr_expired'
              : raw.contains('own_qr') || raw.contains('self') || raw.contains('propre qr')
                  ? 'follow_qr_self'
                  : raw.contains('already_friend') || raw.contains('already friends') || raw.contains('déjà ami')
                      ? 'follow_qr_already_friends'
                      : raw.contains('user_not_found') || raw.contains('utilisateur introuvable')
                          ? 'follow_user_not_found'
                          : 'follow_action_impossible';
      if (mounted) Get.snackbar('error_title'.tr, key.tr);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileController = Get.find<ProfileController>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        centerTitle: true,
        title: _buildPillTabs(context),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyQrCodeTab(profileController),
          _buildScannerTab(context),
        ],
      ),
    );
  }

  Widget _buildPillTabs(BuildContext context) {
    final activeIndex = _tabController.index;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabChip(
            index: 0,
            label: 'follow_qr_tab_my_code'.tr,
            icon: Icons.qr_code_rounded,
            isActive: activeIndex == 0,
          ),
          const SizedBox(width: 4),
          _buildTabChip(
            index: 1,
            label: 'follow_qr_tab_scan'.tr,
            icon: Icons.qr_code_scanner_rounded,
            isActive: activeIndex == 1,
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required int index,
    required String label,
    required IconData icon,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyQrCodeTab(ProfileController controller) {
    if (_isLoadingQr) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final qrData = _activeQrCode;
    final qrId = qrData != null ? (qrData['id'] ?? '').toString() : '';
    final usesRemaining = qrData != null ? (qrData['uses_remaining'] as num?)?.toInt() ?? 0 : 0;
    final syncStatus = qrData != null ? (qrData['sync_status'] ?? 'synced').toString() : 'synced';
    final isSynced = syncStatus == 'synced';

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 300,
                  margin: const EdgeInsets.only(top: 40),
                  padding: const EdgeInsets.fromLTRB(30, 80, 30, 30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isSynced)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'follow_qr_pending_sync'.tr,
                            style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (qrId.isNotEmpty && !isSynced)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: _isSyncingQr ? null : _syncCurrentQrCode,
                            icon: _isSyncingQr
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: Text(_isSyncingQr ? 'Synchronisation…' : 'Synchroniser mon QR code'),
                          ),
                        ),
                      if (qrId.isEmpty)
                        ElevatedButton.icon(
                          onPressed: _forceRegenerateQrCode,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('follow_qr_generate'.tr),
                        )
                      else
                        QrImageView(
                          data: 'scrole_qr:$qrId',
                          version: QrVersions.auto,
                          size: 200.0,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Obx(() => Text(
                        '@${controller.username.value}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      )),
                      const SizedBox(height: 12),
                      if (qrId.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: usesRemaining > 0 ? AppColors.primary.withValues(alpha: 0.15) : AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            usesRemaining > 0 ? '$usesRemaining utilisation(s) restante(s)' : '0 utilisation restante (Expiré)',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: usesRemaining > 0 ? AppColors.primary : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (usesRemaining <= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: _forceRegenerateQrCode,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text('follow_qr_regenerate'.tr),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: -10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF121212),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(45),
                        child: Obx(() => controller.profileImageUrl.value.isNotEmpty
                            ? AppCachedImage(imageUrl: controller.profileImageUrl.value, fit: BoxFit.cover)
                            : Center(
                                child: Text(
                                  controller.initials,
                                  style: AppTextStyles.h3.copyWith(color: Colors.white),
                                ),
                              )),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              'follow_qr_identity_title'.tr,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white54,
                letterSpacing: 2,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerTab(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetectBarcode,
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          left: 20,
          right: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                'follow_qr_scan_hint'.tr,
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
