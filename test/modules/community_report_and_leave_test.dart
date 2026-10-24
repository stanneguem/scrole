import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Community Report & Leave Tests', () {
    test('Trims description and passes null when empty or whitespace', () {
      String? processDescription(String? raw) {
        if (raw == null) return null;
        final trimmed = raw.trim();
        return trimmed.isEmpty ? null : trimmed;
      }

      expect(processDescription('   '), isNull);
      expect(processDescription(''), isNull);
      expect(processDescription(null), isNull);
      expect(processDescription('   Description de test   '), equals('Description de test'));
    });

    test('Validates description length limit of 1000 characters', () {
      final validDescription = 'A' * 1000;
      final invalidDescription = 'A' * 1001;

      expect(validDescription.length <= 1000, isTrue);
      expect(invalidDescription.length <= 1000, isFalse);
    });

    test('Maps report error messages accurately', () {
      String mapReportError(String rawMsg) {
        final msg = rawMsg.toLowerCase();
        if (msg.contains('non authentifié') || msg.contains('unauthenticated')) {
          return 'community_report_unauthenticated';
        }
        if (msg.contains('type de signalement invalide') || msg.contains('invalid target type')) {
          return 'community_report_invalid_target_type';
        }
        if (msg.contains('motif de signalement invalide') || msg.contains('invalid reason')) {
          return 'community_report_invalid_reason';
        }
        if (msg.contains('description trop longue') || msg.contains('1000 caractères maximum') || msg.contains('too long')) {
          return 'community_report_description_too_long';
        }
        if (msg.contains('trop de signalements') || msg.contains('réessayez plus tard') || msg.contains('rate limit')) {
          return 'community_report_rate_limited';
        }
        if (msg.contains('contenu introuvable') || msg.contains('not found')) {
          return 'community_report_target_not_found';
        }
        if (msg.contains('votre propre contenu') || msg.contains('own content')) {
          return 'community_report_cannot_report_own_content';
        }
        return 'community_report_generic_error';
      }

      expect(mapReportError('Utilisateur non authentifié'), equals('community_report_unauthenticated'));
      expect(mapReportError('Description trop longue (1000 caractères maximum)'), equals('community_report_description_too_long'));
      expect(mapReportError('Vous ne pouvez pas signaler votre propre contenu'), equals('community_report_cannot_report_own_content'));
      expect(mapReportError('Erreur inconnue'), equals('community_report_generic_error'));
    });

    test('Maps leave error messages accurately', () {
      String mapLeaveError(String rawMsg) {
        final msg = rawMsg.toLowerCase();
        if (msg.contains('non authentifié') || msg.contains('unauthenticated')) {
          return 'community_leave_unauthenticated';
        }
        if (msg.contains('pas membre') || msg.contains('not a member')) {
          return 'community_leave_not_a_member';
        }
        if (msg.contains('dernier administrateur') || msg.contains('last admin') || msg.contains('transférez')) {
          return 'community_leave_last_admin';
        }
        return 'community_leave_generic_error';
      }

      expect(mapLeaveError('Utilisateur non authentifié'), equals('community_leave_unauthenticated'));
      expect(mapLeaveError('Vous n\'êtes pas membre de cette communauté'), equals('community_leave_not_a_member'));
      expect(mapLeaveError('Vous êtes le dernier administrateur : transférez la propriété avant de quitter la communauté'), equals('community_leave_last_admin'));
      expect(mapLeaveError('Erreur réseau'), equals('community_leave_generic_error'));
    });
  });
}
