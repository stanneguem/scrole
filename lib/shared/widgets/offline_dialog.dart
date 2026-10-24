import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../etats/connectivity_states.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.state});

  final Rx<ConnectionBannerState> state;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = state.value;
      final visible = current != ConnectionBannerState.hidden;
      final isOffline = current == ConnectionBannerState.offline;
      final scheme = Theme.of(context).colorScheme;

      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            offset: visible ? Offset.zero : const Offset(0, -1.2),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: visible ? 1 : 0,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 68),
                      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: Theme.of(context).brightness == Brightness.dark ? .35 : .14,
                            ),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 5),
                          ),
                        ],
                        border: Theme.of(context).brightness == Brightness.dark
                            ? Border.all(color: scheme.outlineVariant, width: .6)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOffline ? 'connection_not_connected'.tr : 'connection_connected'.tr,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 16,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isOffline ? 'connection_reconnecting'.tr : 'connection_restored'.tr,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 14,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              isOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                              key: ValueKey(isOffline),
                              color: isOffline ? scheme.error : scheme.primary,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
