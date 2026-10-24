import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/privacy_service.dart';
import '../../../../shared/models/user_models.dart';

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  final PrivacyService service = Get.find<PrivacyService>();
  bool _loadFailed = false;
  static const _visibilityValues = {'only_me', 'friends', 'followers', 'everyone'};

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    try {
      await service.loadFromBackend();
      if (mounted) setState(() => _loadFailed = false);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('settings_privacy_data'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Obx(() {
        final p = service.privacy.value;
        final visibility = _visibilityValues.contains(p.eventItineraryVisibility)
            ? p.eventItineraryVisibility : 'only_me';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loadFailed)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(CupertinoIcons.wifi_slash, color: colors.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(child: Text('privacy_load_error'.tr, style: TextStyle(color: colors.onErrorContainer))),
                  TextButton(onPressed: _loadPrivacy, child: Text('retry'.tr)),
                ]),
              ),
            _intro(colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_profile'.tr, colors),
            const SizedBox(height: 8),
            _group([
              _switchTile(icon: CupertinoIcons.lock, title: 'follow_profile_private'.tr,
                subtitle: 'follow_profile_private_desc'.tr, value: p.profileVisibility == 'private',
                onChanged: (v) => _save(p.copyWith(profileVisibility: v ? 'private' : 'public')), colors: colors),
              _switchTile(icon: CupertinoIcons.eye, title: 'privacy_show_online_status'.tr,
                subtitle: 'privacy_show_online_status_desc'.tr, value: p.showOnlineStatus,
                onChanged: (v) => _save(p.copyWith(showOnlineStatus: v)), colors: colors),
              _switchTile(icon: CupertinoIcons.globe, title: 'privacy_show_country'.tr,
                subtitle: 'privacy_show_country_desc'.tr, value: p.afficherPays,
                onChanged: (v) => _save(p.copyWith(afficherPays: v)), colors: colors),
              _switchTile(icon: CupertinoIcons.location, title: 'privacy_show_city'.tr,
                subtitle: 'privacy_show_city_desc'.tr, value: p.afficherVille,
                onChanged: (v) => _save(p.copyWith(afficherVille: v)), colors: colors),
              _switchTile(icon: CupertinoIcons.clock, title: 'privacy_show_last_seen'.tr,
                subtitle: 'privacy_show_last_seen_desc'.tr, value: p.afficherDerniereConnexion,
                onChanged: (v) => _save(p.copyWith(afficherDerniereConnexion: v)), colors: colors),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_messages'.tr, colors),
            const SizedBox(height: 8),
            _group([
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                child: Row(children: [
                  Container(width: 34, height: 34, decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)),
                    child: Icon(CupertinoIcons.chat_bubble, color: colors.primary, size: 18)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('privacy_allow_messages'.tr, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('privacy_allow_messages_desc'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
                  ])),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: p.allowMessagesFrom == 'friends' ? 'friends' : 'everyone',
                  children: {
                    'everyone': Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text('privacy_messages_everyone'.tr, textAlign: TextAlign.center)),
                    'friends': Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text('privacy_messages_friends'.tr, textAlign: TextAlign.center)),
                  },
                  onValueChanged: (v) { if (v != null) _save(p.copyWith(allowMessagesFrom: v)); },
                ),
              ),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_event_planning'.tr, colors),
            const SizedBox(height: 8),
            _group([
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(CupertinoIcons.calendar, color: colors.primary, size: 21),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('event_itinerary_visibility_title'.tr, style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('event_itinerary_visibility_desc'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.35)),
                  ])),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 14),
                child: Container(
                  decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: dark ? .45 : .6), borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: visibility, isExpanded: true, borderRadius: BorderRadius.circular(14),
                      items: [
                        DropdownMenuItem(value: 'only_me', child: Text('event_itinerary_visibility_only_me'.tr)),
                        DropdownMenuItem(value: 'friends', child: Text('event_itinerary_visibility_friends'.tr)),
                        DropdownMenuItem(value: 'followers', child: Text('event_itinerary_visibility_followers'.tr)),
                        DropdownMenuItem(value: 'everyone', child: Text('event_itinerary_visibility_everyone'.tr)),
                      ],
                      onChanged: (v) { if (v != null && v != visibility) _save(p.copyWith(eventItineraryVisibility: v)); },
                    ),
                  ),
                ),
              ),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_data'.tr, colors),
            const SizedBox(height: 8),
            _group([
              _actionTile(icon: CupertinoIcons.doc_text, title: 'privacy_request_all'.tr,
                subtitle: 'privacy_export_unavailable'.tr, colors: colors, enabled: false),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_policies_disclosures'.tr, colors),
            const SizedBox(height: 8),
            _group([
              _actionTile(icon: CupertinoIcons.doc_text, title: 'terms'.tr,
                subtitle: 'privacy_link_unavailable'.tr, colors: colors, enabled: false),
              _actionTile(icon: CupertinoIcons.info, title: 'privacy_policy'.tr,
                subtitle: 'privacy_link_unavailable'.tr, colors: colors, enabled: false),
            ], colors),
            const SizedBox(height: 20),
            Text('privacy_footer_notice'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.45)),
          ],
        );
      }),
    );
  }

  Future<void> _save(AppPrivacy next) async {
    try {
      await service.saveToBackend(next);
      if (!mounted) return;
      Get.snackbar('privacy_saved_title'.tr, 'privacy_saved_message'.tr, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[PRIVACY] save failed: $e');
      if (mounted) Get.snackbar('error_title'.tr, 'follow_action_failed'.tr, snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _intro(ColorScheme colors) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [colors.primary.withValues(alpha: .13), colors.primary.withValues(alpha: .04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20), border: Border.all(color: colors.primary.withValues(alpha: .12))),
    child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: Icon(CupertinoIcons.lock, color: colors.primary, size: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('privacy_intro_title'.tr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface)),
        const SizedBox(height: 4),
        Text('privacy_intro_desc'.tr, style: TextStyle(fontSize: 13, height: 1.35, color: colors.onSurfaceVariant)),
      ])),
    ]),
  );

  Widget _sectionLabel(String title, ColorScheme colors) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(title.toUpperCase(), style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, letterSpacing: 1.05, fontWeight: FontWeight.w700)));

  Widget _group(List<Widget> children, ColorScheme colors) => Container(
    decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: .35))),
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, indent: 54, endIndent: 14, color: colors.outlineVariant.withValues(alpha: .35)),
        children[i],
      ],
    ]),
  );

  Widget _switchTile({required IconData icon, required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged, required ColorScheme colors}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Row(children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: colors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: colors.primary)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
      ])),
      const SizedBox(width: 8),
      CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: colors.primary),
    ]),
  );

  Widget _actionTile({required IconData icon, required String title, String? subtitle,
    required ColorScheme colors, required bool enabled}) => Opacity(
    opacity: enabled ? 1 : .65,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12))],
        ])),
        Icon(CupertinoIcons.chevron_right, size: 16, color: colors.onSurfaceVariant),
      ]),
    ),
  );
}
