/// Maps backend relationship errors to stable localization keys.
/// Backend text is only inspected; it is never displayed directly.
class FollowErrorMapper {
  static const String fallbackKey = 'follow_action_impossible';

  static String keyFor(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('vous ne pouvez pas vous suivre vous-même') || raw.contains('cannot follow yourself')) {
      return 'follow_error_self';
    }
    if (raw.contains('utilisateur introuvable') || raw.contains('user_not_found') || raw.contains('user not found')) {
      return 'follow_user_not_found';
    }
    if (raw.contains('compte indisponible') || raw.contains('account unavailable')) return 'follow_error_unavailable';
    if (raw.contains('action impossible') || raw.contains('blocked') || raw.contains('blocking')) return 'follow_action_impossible';
    if (raw.contains('200 nouveaux abonnements') || raw.contains('daily follow limit')) return 'follow_error_limit_daily';
    if (raw.contains('5000 abonnements') || raw.contains('maximum follow limit')) return 'follow_error_limit_total';
    if (raw.contains('demande introuvable') || raw.contains('request_not_found') || raw.contains('request not found')) {
      return 'follow_error_request_missing';
    }
    if (raw.contains('ne vous est pas destinée') || raw.contains('not addressed to you')) return 'follow_error_request_not_for_you';
    if (raw.contains('déjà été traitée') || raw.contains('already processed')) return 'follow_error_request_processed';
    if (raw.contains('pas ami') || raw.contains('not friends')) return 'follow_error_not_friend';
    if (raw.contains('réservée aux abonnés') || raw.contains('approved followers')) return 'follow_error_private_list';
    if (raw.contains('direction invalide') || raw.contains('invalid direction')) return 'follow_error_direction';
    return fallbackKey;
  }
}
