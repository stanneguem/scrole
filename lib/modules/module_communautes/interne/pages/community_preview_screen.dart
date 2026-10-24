import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/models/community_model.dart';
import '../../centre/services/community_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';
import '../../../../shared/controllers/search_controller.dart';
import 'community_feed_screen.dart';

void showCommunityPreviewSheet(BuildContext context, {required CommunityOpenResult result}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => CommunityPreviewSheet(result: result),
  );
}

class CommunityPreviewSheet extends StatefulWidget {
  final CommunityOpenResult result;

  const CommunityPreviewSheet({
    super.key,
    required this.result,
  });

  @override
  State<CommunityPreviewSheet> createState() => _CommunityPreviewSheetState();
}

class _CommunityPreviewSheetState extends State<CommunityPreviewSheet> {
  final CommunityService _service = Get.isRegistered<CommunityService>()
      ? Get.find<CommunityService>()
      : Get.put(CommunityService());

  bool _isSubmitting = false;
  late bool _isPending;
  late String _currentAction;

  @override
  void initState() {
    super.initState();
    _isPending = widget.result.isPending;
    _currentAction = widget.result.joinAction;
  }

  Future<void> _handleAction() async {
    final communityId = widget.result.id;
    if (_isSubmitting || communityId == null || communityId.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final res = await _service.joinCommunity(communityId);
      final status = (res['status'] ?? res['membership_status'] ?? res['request_status'] ?? '').toString().toLowerCase();

      try {
        if (Get.isRegistered<AppSearchController>()) {
          Get.find<AppSearchController>().invalidateSearchCache();
        }
      } catch (_) {}

      if (status == 'active' || status == 'approved' || status == 'joined' || _currentAction == 'join') {
        if (mounted) {
          Navigator.of(context).pop();
        }
        Get.snackbar(
          'community_join_success'.tr,
          'community_join_success'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
        Get.to(() => CommunityFeedScreen(
              communityId: communityId,
              communityName: widget.result.name ?? 'Communauté',
            ));
      } else {
        if (mounted) {
          setState(() {
            _isPending = true;
            _isSubmitting = false;
          });
        }
        Get.snackbar(
          'community_request_sent'.tr,
          'community_request_success'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      try {
        final refreshedResult = await _service.openCommunity(communityId);
        if (mounted) {
          setState(() {
            _isPending = refreshedResult.isPending;
            _currentAction = refreshedResult.joinAction;
            _isSubmitting = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }

      String msg = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar(
        'community_preview_title'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final res = widget.result;

    final name = res.name ?? 'Communauté';
    final slug = res.slug ?? '';
    final description = res.description ?? '';
    final visibility = res.visibility ?? 'public';
    final photoCover = res.photoCover;
    final photoProfile = res.photoProfile;
    final memberCount = res.memberCount;

    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Modal Header: Close Left, Title Center, Action Text Right
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colorScheme.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'community_preview_title'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildHeaderAction(colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            const Divider(height: 1),

            // Scrollable Content Body
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Banner & Profile Avatar
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 130,
                          width: double.infinity,
                          color: colorScheme.surfaceContainerHighest,
                          child: photoCover != null && photoCover.isNotEmpty
                              ? AppCachedImage(imageUrl: photoCover, fit: BoxFit.cover)
                              : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary.withValues(alpha: 0.7),
                                        colorScheme.tertiary.withValues(alpha: 0.5)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                ),
                        ),
                        Positioned(
                          bottom: -32,
                          left: 20,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.surface,
                              border: Border.all(color: colorScheme.surface, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(36),
                              child: photoProfile != null && photoProfile.isNotEmpty
                                  ? AppCachedImage(imageUrl: photoProfile, fit: BoxFit.cover)
                                  : Container(
                                      color: colorScheme.primaryContainer,
                                      alignment: Alignment.center,
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 42),

                    // Details Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              EntityCertifiedBadge(entityType: 'community', entityId: widget.result.id ?? '', size: 18),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: visibility == 'prive'
                                      ? Colors.orange.withValues(alpha: 0.15)
                                      : colorScheme.primaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      visibility == 'prive' ? Icons.lock_outline_rounded : Icons.public_rounded,
                                      size: 13,
                                      color: visibility == 'prive' ? Colors.orange.shade800 : colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      visibility == 'prive' ? 'Privée' : 'Publique',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: visibility == 'prive' ? Colors.orange.shade800 : colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (slug.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '@$slug',
                              style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                            ),
                          ],

                          if (memberCount != null && memberCount > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.people_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  '$memberCount membres',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              description,
                              style: TextStyle(fontSize: 14.5, height: 1.4, color: colorScheme.onSurface),
                            ),
                          ],

                          // Display Reasons if Non-Eligible
                          if (_currentAction == 'none' && !_isPending && res.reasons.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'community_cannot_join'.tr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...res.reasons.map((reasonCode) {
                                    final translatedReason = 'community_reason_$reasonCode'.tr;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                          Expanded(
                                            child: Text(
                                              translatedReason,
                                              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurface),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAction(ColorScheme colorScheme) {
    if (_isPending) {
      return Text(
        'community_request_pending'.tr,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
        ),
      );
    }

    if (_currentAction == 'join' || _currentAction == 'request') {
      return GestureDetector(
        onTap: _isSubmitting ? null : _handleAction,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSubmitting) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                _currentAction == 'join'
                    ? 'community_join_button'.tr
                    : 'community_request_button'.tr,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _isSubmitting
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
