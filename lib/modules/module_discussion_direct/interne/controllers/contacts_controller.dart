import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/repositories/social_repository.dart';

class ContactModel {
  final String id;
  final String name;
  final String username;
  final String? avatarUrl;
  final bool isOnline;
  final bool isCertified;
  final bool isBlockedByMe;

  ContactModel({
    required this.id,
    required this.name,
    required this.username,
    this.avatarUrl,
    this.isOnline = false,
    this.isCertified = false,
    this.isBlockedByMe = false,
  });
}

class ContactsController extends GetxController {
  final SocialRepository _socialRepository = SocialRepository();
  final AppDatabase _db = Get.find<AppDatabase>();
  final SupabaseClient _client = Supabase.instance.client;

  final RxList<ContactModel> contacts = <ContactModel>[].obs;
  final RxString searchQuery = ''.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    unawaited(loadContacts());
  }

  Future<void> loadContacts() async {
    final uid = _userId;
    if (uid == null) return;

    error.value = '';
    final cached = await _restoreCachedContacts(uid);

    if (cached.isNotEmpty) {
      isLoading.value = false;
      unawaited(_refreshContactsInBackground(uid));
      return;
    }

    isLoading.value = true;
    await _refreshContactsInBackground(uid, showErrors: true);
    isLoading.value = false;
  }

  Future<List<ContactModel>> _restoreCachedContacts(String uid) async {
    try {
      final db = await _db.database;
      final rows = await db.query('direct_chat_contacts', where: 'user_id = ?', whereArgs: [uid], orderBy: 'name COLLATE NOCASE ASC');
      final cached = rows.map((row) => ContactModel(
        id: row['contact_id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        username: row['username']?.toString() ?? '',
        avatarUrl: row['avatar_url']?.toString(),
        isOnline: (row['is_online'] as num?)?.toInt() == 1,
        isCertified: (row['is_certified'] as num?)?.toInt() == 1 || row['is_certified'] == true,
      )).where((contact) => contact.id.isNotEmpty).toList();
      contacts.assignAll(cached);
      return cached;
    } catch (e) {
      debugPrint('[Contacts] local cache load failed: $e');
      return [];
    }
  }

  Future<void> _refreshContactsInBackground(String uid, {bool showErrors = false}) async {
    try {
      final list = await _socialRepository.getAcceptedConnections();
      final blockedList = await _client.rpc('scrole_get_direct_blocked_users');
      final merged = <String, ContactModel>{};

      for (final row in list) {
        final contact = _fromJson(row);
        if (contact.id.isNotEmpty) merged[contact.id] = contact;
      }
      if (blockedList is List) {
        for (final item in blockedList.whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final contact = _fromJson(row, isBlockedByMe: true);
          if (contact.id.isNotEmpty) merged[contact.id] = contact;
        }
      }

      final fresh = merged.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete('direct_chat_contacts', where: 'user_id = ?', whereArgs: [uid]);
        for (final contact in fresh) {
          await txn.insert('direct_chat_contacts', {
            'user_id': uid,
            'contact_id': contact.id,
            'name': contact.name,
            'username': contact.username,
            'avatar_url': contact.avatarUrl,
            'is_online': contact.isOnline ? 1 : 0,
            'is_certified': contact.isCertified ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      contacts.assignAll(fresh);
      error.value = '';
    } catch (e) {
      debugPrint('[Contacts] background refresh failed: $e');
      if (showErrors && contacts.isEmpty) error.value = 'Impossible de charger les connexions.';
    }
  }

  ContactModel _fromJson(Map<String, dynamic> json, {bool isBlockedByMe = false}) {
    final first = (json['first_name'] as String? ?? '').trim();
    final last = (json['last_name'] as String? ?? '').trim();
    final username = (json['username'] as String? ?? '').trim();
    final name = '$first $last'.trim();
    final isCertified = json['is_certified'] == true || json['is_verified'] == true || json['is_certified'] == 1 || json['is_verified'] == 1;
    return ContactModel(
      id: json['user_id'] as String,
      name: name.isEmpty ? username : name,
      username: username,
      avatarUrl: json['photo_url'] as String?,
      isCertified: isCertified,
      isBlockedByMe: isBlockedByMe,
    );
  }

  List<ContactModel> get filteredContacts {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return contacts.toList();
    return contacts.where((c) => c.name.toLowerCase().contains(query) || c.username.toLowerCase().contains(query)).toList();
  }

  Future<void> unblockContact(String contactId) async {
    try {
      await _client.rpc(
        'scrole_unblock_direct_user',
        params: {'p_other_user_id': contactId},
      );
      await loadContacts();
      Get.snackbar(
        'Utilisateur débloqué',
        'Cette personne peut de nouveau apparaître parmi vos connexions.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('[Contacts] unblock failed: $e');
      Get.snackbar(
        'Erreur',
        'Impossible de débloquer cet utilisateur. Réessayez.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void onBack() => Get.back();
}
