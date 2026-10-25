import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app_controller.dart';

class WelcomeOnboardingScreen extends StatefulWidget {
  const WelcomeOnboardingScreen({super.key});
  @override
  State<WelcomeOnboardingScreen> createState() => _WelcomeOnboardingScreenState();
}

class _WelcomeOnboardingScreenState extends State<WelcomeOnboardingScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  int _step = 0;
  bool _loading = true;
  String? _loadError;
  final Set<String> _busy = {};
  final Set<String> _followed = {};
  final Set<String> _joined = {};
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _communities = [];

  @override
  void initState() {
    super.initState();
    _startPersistentOnboarding();
  }

  Future<void> _startPersistentOnboarding() async {
    try {
      final state = await _db.rpc('start_social_discovery_onboarding');
      if (state is Map && state['completed'] == true) {
        if (mounted && Get.isRegistered<AppController>()) {
          Get.find<AppController>().finishOnboarding();
        }
        return;
      }
    } catch (e) {
      debugPrint('[ONBOARDING] persistent start failed: $e');
      if (mounted) {
        setState(() => _loadError = 'La configuration de cette étape doit être finalisée. Réessaie plus tard.');
      }
    }
    if (mounted) await _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw StateError('Session utilisateur absente');
      final profiles = await _db.from('user_profiles')
          .select('user_id, username, first_name, last_name, photo_url, account_status, deleted_at')
          .neq('user_id', uid)
          .eq('account_status', 'active')
          .isFilter('deleted_at', null)
          .limit(20);
      final communities = await _db.from('communities')
          .select('id, name, slug, description, photo_profile, visibility, status, require_manual_approval')
          .eq('visibility', 'public').eq('status', 'active').limit(20);
      if (!mounted) return;
      _users = (profiles as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _communities = (communities as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      _loadError = 'Impossible de charger les suggestions pour le moment.';
      debugPrint('[ONBOARDING] suggestions loading failed: $e');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _follow(Map<String, dynamic> user) async {
    final id = user['user_id']?.toString();
    if (id == null || id.isEmpty || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await _db.rpc('follow_user', params: {'p_user_id': id});
      if (mounted) setState(() => _followed.add(id));
    } catch (e) {
      if (mounted) _message('Impossible de suivre ce profil. Réessaie.');
      debugPrint('[ONBOARDING] follow failed for $id: $e');
    } finally { if (mounted) setState(() => _busy.remove(id)); }
  }

  Future<void> _join(Map<String, dynamic> community) async {
    final id = community['id']?.toString();
    if (id == null || id.isEmpty || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final response = await _db.rpc('join_community', params: {'p_community_id': id});
      final decoded = response is String ? jsonDecode(response) : response;
      final result = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      final pending = result['status']?.toString() == 'pending' ||
          result['status']?.toString() == 'en_attente' ||
          result['membership_status']?.toString() == 'pending' ||
          result['request_status']?.toString() == 'en_attente';
      if (mounted) {
        setState(() => _joined.add(id));
        _message(pending ? 'Demande envoyée.' : 'Communauté rejointe.');
      }
    } catch (e) {
      if (mounted) _message('Impossible de rejoindre cette communauté. Réessaie.');
      debugPrint('[ONBOARDING] join community failed for $id: $e');
    } finally { if (mounted) setState(() => _busy.remove(id)); }
  }

  void _next() {
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    try {
      await _db.rpc('complete_social_discovery_onboarding');
    } catch (e) {
      debugPrint('[ONBOARDING] persistent completion failed: $e');
      if (mounted) {
        _message('Impossible d’enregistrer la fin de cette étape. Réessaie.');
      }
      return;
    }
    if (Get.isRegistered<AppController>()) {
      Get.find<AppController>().finishOnboarding();
    }
  }
  void _message(String message) => Get.snackbar('Information', message, snackPosition: SnackPosition.BOTTOM);

  String _userName(Map<String, dynamic> user) {
    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    return name.isEmpty ? '@${user['username'] ?? 'utilisateur'}' : name;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Row(children: [
            for (var i = 0; i < 2; i++) ...[
              Container(width: 42, height: 5, decoration: BoxDecoration(
                color: _step == i ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(9))),
              if (i == 0) const SizedBox(width: 6),
            ],
            const Spacer(),
            TextButton(onPressed: _finish, child: Text('Passer', style: TextStyle(color: colors.onSurfaceVariant))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_step == 0 ? Icons.people_alt_outlined : Icons.groups_2_outlined, size: 34, color: colors.primary),
            const SizedBox(height: 12),
            Text(_step == 0 ? 'Trouve des personnes à suivre' : 'Rejoins tes communautés',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_step == 0
              ? 'Découvre des profils et commence à créer ton fil. Tu peux aussi le faire plus tard.'
              : 'Choisis les communautés qui correspondent à tes centres d’intérêt.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ]),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && (_step == 0 ? _users.isEmpty : _communities.isEmpty)
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 38), const SizedBox(height: 12),
                Text(_loadError!, textAlign: TextAlign.center), const SizedBox(height: 12),
                OutlinedButton(onPressed: _loadSuggestions, child: const Text('Réessayer')),
              ])))
            : _step == 0 ? _buildUsers(colors) : _buildCommunities(colors)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
          child: SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_step == 0 ? 'Continuer' : 'Terminer et découvrir Scrole'))),
        ),
      ])),
    );
  }

  Widget _buildUsers(ColorScheme colors) {
    if (_users.isEmpty) return const Center(child: Text('Aucun profil à suggérer pour le moment.'));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: _users.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.outlineVariant.withValues(alpha: .5)),
      itemBuilder: (context, index) {
        final user = _users[index]; final id = user['user_id']?.toString() ?? '';
        final followed = _followed.contains(id); final avatar = user['photo_url']?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          leading: CircleAvatar(radius: 25, backgroundColor: colors.surfaceContainerHighest,
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty ? const Icon(Icons.person_outline) : null),
          title: Text(_userName(user), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('@${user['username'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: FilledButton.tonal(
            onPressed: followed || _busy.contains(id) ? null : () => _follow(user),
            child: _busy.contains(id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(followed ? 'Suivi' : 'Suivre')),
        );
      },
    );
  }

  Widget _buildCommunities(ColorScheme colors) {
    if (_communities.isEmpty) return const Center(child: Text('Aucune communauté publique à suggérer pour le moment.'));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: _communities.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.outlineVariant.withValues(alpha: .5)),
      itemBuilder: (context, index) {
        final community = _communities[index]; final id = community['id']?.toString() ?? '';
        final joined = _joined.contains(id); final avatar = community['photo_profile']?.toString() ?? '';
        final description = community['description']?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          leading: CircleAvatar(radius: 25, backgroundColor: colors.surfaceContainerHighest,
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty ? const Icon(Icons.groups_outlined) : null),
          title: Text(community['name']?.toString() ?? 'Communauté', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(description.trim().isNotEmpty ? description : (community['require_manual_approval'] == true ? 'Communauté avec validation des demandes' : 'Communauté publique'),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: FilledButton.tonal(
            onPressed: joined || _busy.contains(id) ? null : () => _join(community),
            child: _busy.contains(id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(joined ? 'Ajoutée' : 'Rejoindre')),
        );
      },
    );
  }
}