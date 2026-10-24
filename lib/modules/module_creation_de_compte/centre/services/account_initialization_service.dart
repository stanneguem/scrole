import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import '../../../../app/service_global/notification_service.dart';
import '../../../../app/service_global/session_service.dart';
import '../../externe/repositories/account_repository.dart';

class AccountInitializationService extends GetxService {
  final AccountRepository _repository = AccountRepository();
  final SessionService _sessionService = Get.find<SessionService>();

  Future<void> initializeAccount({
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    required String countryId,
    required DateTime birthDate,
    String? cityId,
    String? gender,
    String? bio,
    String? avatarUrl,
    String? coverUrl,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    
    // Récupérer le token de notification si disponible
    String? deviceToken;
    try {
      deviceToken = await NotificationService.instance.getDeviceToken();
    } catch (e) {
      debugPrint('Impossible de récupérer le FCM token: $e');
    }
    
    final params = {
      'p_username': username.trim().toLowerCase(),
      'p_first_name': firstName.trim(),
      'p_last_name': lastName.trim(),
      'p_birth_date': _formatDate(birthDate),
      'p_country_id': countryId,
      if (cityId != null) 'p_city_id': cityId,
      if (gender != null) 'p_gender': gender,
      if (bio != null) 'p_bio': bio,
      if (avatarUrl != null) 'p_avatar_url': avatarUrl,
      if (coverUrl != null) 'p_cover_url': coverUrl,
      'p_platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web'),
      'p_app_version': packageInfo.version,
      'p_device_token': deviceToken,
    };

    final result = await _repository.initializeAccount(params);
    
    // Distribuer les données aux services via SessionService
    _sessionService.applySessionData(result);
  }

  String _formatDate(DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}-"
           "${date.month.toString().padLeft(2, '0')}-"
           "${date.day.toString().padLeft(2, '0')}";
  }
}
