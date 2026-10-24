import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Badge de certification d'un événement ou d'une communauté.
class EntityCertifiedBadge extends StatelessWidget {
  const EntityCertifiedBadge({
    super.key,
    required this.entityType,
    required this.entityId,
    this.size = 18,
    this.showLabel = false,
  });

  final String entityType; // 'event' ou 'community'
  final String entityId;
  final double size;
  final bool showLabel;

  static final Map<String, _CertificationStatusCache> _cache = {};

  static Future<bool> _isCertified(String entityType, String entityId) {
    final key = '$entityType:$entityId';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < const Duration(minutes: 2)) {
      return cached.value;
    }
    final future = _fetch(entityType, entityId);
    _cache[key] = _CertificationStatusCache(future, DateTime.now());
    return future;
  }

  static Future<bool> _fetch(String entityType, String entityId) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'scrole_get_entity_certification_status',
        params: {'p_entity_type': entityType, 'p_entity_id': entityId},
      );
      if (result is Map) return result['entity_certified'] == true;
      if (result is List && result.isNotEmpty && result.first is Map) {
        return result.first['entity_certified'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (entityId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _isCertified(entityType, entityId),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        final label = entityType == 'community'
            ? 'Communauté certifiée'
            : 'Événement certifié';
        final badge = Icon(
          Icons.verified_rounded,
          size: size,
          color: const Color(0xFF1877F2),
          semanticLabel: label,
        );
        return Tooltip(
          message: label,
          child: showLabel
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1877F2).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF1877F2).withValues(alpha: 0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        badge,
                        const SizedBox(width: 4),
                        Text(
                          'Certifié',
                          style: TextStyle(
                            color: const Color(0xFF1877F2),
                            fontSize: size * 0.68,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : badge,
        );
      },
    );
  }
}

class _CertificationStatusCache {
  const _CertificationStatusCache(this.value, this.createdAt);
  final Future<bool> value;
  final DateTime createdAt;
}
