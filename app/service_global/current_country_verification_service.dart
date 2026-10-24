import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:scrole/app/service_global/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Détecte le pays de présence via GPS et une Edge Function côté serveur.
/// Cette détection ne modifie jamais le pays ou la ville déclarés sur le profil.
class CurrentCountryVerificationService {
  CurrentCountryVerificationService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> verify() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');

    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!gpsEnabled) {
      throw StateError('Active la localisation GPS puis réessaie.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      throw StateError(
        'La permission GPS est nécessaire pour vérifier le pays.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    final deviceToken = await NotificationService.instance.getDeviceToken();
    if (deviceToken == null || deviceToken.isEmpty) {
      throw StateError(
        'Cet appareil doit être enregistré avant la vérification.',
      );
    }

    final device = await _client
        .from('user_devices')
        .select('id')
        .eq('user_id', user.id)
        .eq('device_token', deviceToken)
        .maybeSingle();
    final deviceId = device?['id']?.toString();
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError(
        'Appareil introuvable. Réessaie après la synchronisation.',
      );
    }

    final response = await _client.functions.invoke(
      'verify-current-country',
      body: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_m': position.accuracy,
        'captured_at': position.timestamp.toUtc().toIso8601String(),
        'device_id': deviceId,
        'request_id': _newUuidV4(),
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final body = response.data;
      final message = body is Map
          ? (body['error']?.toString() ?? 'La vérification du pays a échoué.')
          : 'La vérification du pays a échoué.';
      throw StateError(_friendlyError(message));
    }

    final data = response.data;
    if (data is! Map || data['status'] != 'verified') {
      throw StateError('Le serveur n’a pas confirmé le pays.');
    }
    return Map<String, dynamic>.from(data);
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'country_verification_not_configured':
        return 'La vérification du pays n’est pas encore configurée sur le serveur.';
      case 'gps_accuracy_insufficient':
        return 'La précision GPS est insuffisante. Réessaie dans un endroit dégagé.';
      case 'gps_fix_too_old':
        return 'La position GPS est trop ancienne. Réessaie.';
      case 'geolocation_provider_unavailable':
      case 'geolocation_provider_failed':
        return 'Le service de vérification géographique est momentanément indisponible.';
      case 'country_could_not_be_resolved':
        return 'Impossible de déterminer le pays depuis cette position GPS.';
      case 'device_not_owned_by_user':
        return 'Cet appareil n’est pas associé à ton compte.';
      default:
        return 'Vérification du pays impossible ($code).';
    }
  }

  String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
