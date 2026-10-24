/// Type d'action de synchronisation
enum SyncAction {
  insert,
  update,
  delete;

  static SyncAction fromString(String value) {
    return SyncAction.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => SyncAction.update,
    );
  }
}

/// Représente un changement unitaire reçu du serveur
class SyncChange {
  final String entityType;
  final String entityId;
  final SyncAction action;
  final Map<String, dynamic>? payload;

  SyncChange({
    required this.entityType,
    required this.entityId,
    required this.action,
    this.payload,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      entityType: json['entity_type'] ?? '',
      entityId: json['entity_id'] ?? '',
      action: SyncAction.fromString(json['action'] ?? 'update'),
      payload: json['payload'] != null ? Map<String, dynamic>.from(json['payload']) : null,
    );
  }
}

/// Résultat global d'un appel à sync_changes
class SyncResult {
  final List<SyncChange> changes;
  final int newCursor;

  SyncResult({
    required this.changes,
    required this.newCursor,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> changesJson = json['changes'] ?? [];
    return SyncResult(
      changes: changesJson.map((e) => SyncChange.fromJson(e)).toList(),
      newCursor: json['new_cursor'] ?? 0,
    );
  }
}
