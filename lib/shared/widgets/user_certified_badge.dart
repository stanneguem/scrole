import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CertificationBadgeType { none, basic, pro, premium, event, community }

extension CertificationBadgeTypeStyle on CertificationBadgeType {
  Color get color => switch (this) {
        CertificationBadgeType.none => Colors.transparent,
        CertificationBadgeType.basic => const Color(0xFF1877F2),
        CertificationBadgeType.pro => const Color(0xFF805AD5),
        CertificationBadgeType.premium => const Color(0xFFD4A017),
        CertificationBadgeType.event || CertificationBadgeType.community => const Color(0xFF1877F2),
      };
  String get tooltipKey => 'profile_verified_tooltip';
}

class _CachedCertificationLevel {
  final Future<CertificationBadgeType> value;
  final DateTime createdAt;
  const _CachedCertificationLevel(this.value, this.createdAt);
}

class _CertificationLevelResolver {
  static final Map<String, _CachedCertificationLevel> _cache = {};

  static Future<CertificationBadgeType> resolve(String userId) {
    final cached = _cache[userId];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < const Duration(minutes: 2)) {
      return cached.value;
    }
    final future = _fetch(userId);
    _cache[userId] = _CachedCertificationLevel(future, DateTime.now());
    return future;
  }

  static Future<CertificationBadgeType> _fetch(String userId) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_public_profile_certification_level',
        params: {'p_user_id': userId},
      );
      return switch (result.toString().toLowerCase()) {
        'premium' => CertificationBadgeType.premium,
        'pro' => CertificationBadgeType.pro,
        'basique' => CertificationBadgeType.basic,
        _ => CertificationBadgeType.none,
      };
    } catch (_) {
      // Le type fourni par l'écran reste le fallback en cas d'indisponibilité.
      rethrow;
    }
  }
}

class UserCertifiedBadge extends StatelessWidget {
  final double size;
  final bool showTooltip;
  final CertificationBadgeType type;
  final String? userId;

  const UserCertifiedBadge({
    super.key,
    this.size = 18,
    this.showTooltip = true,
    this.type = CertificationBadgeType.basic,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty) return _buildBadge(type);
    return FutureBuilder<CertificationBadgeType>(
      future: _CertificationLevelResolver.resolve(userId!),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == CertificationBadgeType.none) return const SizedBox.shrink();
        return _buildBadge(snapshot.data ?? type);
      },
    );
  }

  Widget _buildBadge(CertificationBadgeType badgeType) {
    final badge = Icon(
      Icons.verified_rounded,
      size: size,
      color: badgeType.color,
      semanticLabel: badgeType.tooltipKey.tr,
    );
    return showTooltip ? Tooltip(message: badgeType.tooltipKey.tr, child: badge) : badge;
  }
}
