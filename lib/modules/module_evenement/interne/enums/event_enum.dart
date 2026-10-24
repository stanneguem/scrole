enum EventVisibility { public, private, communityOnly }

enum EventStatus { draft, published, cancelled, pendingDeletion, deleted, completed, postponed }

extension EventVisibilityExt on EventVisibility {
  String get value {
    switch (this) {
      case EventVisibility.public: return 'public';
      case EventVisibility.private: return 'private';
      case EventVisibility.communityOnly: return 'community_only';
    }
  }

  static EventVisibility fromString(String s) {
    return EventVisibility.values.firstWhere(
      (e) => e.value == s,
      orElse: () => EventVisibility.public,
    );
  }
}

extension EventStatusExt on EventStatus {
  String get value {
    switch (this) {
      case EventStatus.draft: return 'en_attente';
      case EventStatus.published: return 'active';
      case EventStatus.cancelled: return 'rejected';
      case EventStatus.pendingDeletion: return 'pending_deletion';
      case EventStatus.deleted: return 'deleted';
      case EventStatus.completed: return 'completed';
      case EventStatus.postponed: return 'postponed';
    }
  }

  static EventStatus fromString(String s) {
    final lower = s.toLowerCase().trim();
    switch (lower) {
      case 'active':
      case 'publie':
      case 'published':
      case 'validee':
      case 'valide':
        return EventStatus.published;

      case 'en_attente':
      case 'draft':
      case 'pending':
        return EventStatus.draft;

      case 'pending_deletion':
      case 'en_attente_suppression':
        return EventStatus.pendingDeletion;

      case 'rejected':
      case 'rejetee':
      case 'refusee':
      case 'refuse':
      case 'cancelled':
        return EventStatus.cancelled;

      case 'deleted':
      case 'purged':
      case 'purgable':
        return EventStatus.deleted;

      case 'completed':
      case 'terminee':
        return EventStatus.completed;

      case 'postponed':
      case 'reporte':
        return EventStatus.postponed;

      default:
        return EventStatus.draft;
    }
  }
}
