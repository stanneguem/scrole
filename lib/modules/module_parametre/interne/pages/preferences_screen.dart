import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/service_global/preferences_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final PreferencesService preferencesService;

  @override
  void initState() {
    super.initState();
    preferencesService = Get.find<PreferencesService>();
    preferencesService.syncInitialSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('settings_preferences_title'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _intro(colors),
          const SizedBox(height: 24),
          _section('settings_preferences_video_section'.tr, colors),
          const SizedBox(height: 8),
          _group([
            Obx(() => _switchTile(
              icon: CupertinoIcons.play_rectangle,
              title: 'settings_autoplay_videos'.tr,
              subtitle: 'settings_autoplay_videos_desc'.tr,
              value: preferencesService.preferences.value.autoPlayVideos,
              onChanged: (value) => preferencesService.update({'auto_play_videos': value}),
              colors: colors,
            )),
          ], colors),
          const SizedBox(height: 24),
          _section('settings_preferences_notifications_section'.tr, colors),
          const SizedBox(height: 8),
          _group([
            Obx(() => _switchTile(
              icon: CupertinoIcons.bell,
              title: 'settings_notifications_enabled'.tr,
              subtitle: 'settings_notifications_enabled_desc'.tr,
              value: preferencesService.preferences.value.notificationsEnabled,
              onChanged: (value) => preferencesService.update({'notifications_enabled': value}),
              colors: colors,
            )),
            Obx(() => _switchTile(
              icon: CupertinoIcons.bell_fill,
              title: 'settings_notif_push'.tr,
              subtitle: 'settings_notif_push_desc'.tr,
              value: preferencesService.preferences.value.notifPush,
              onChanged: (value) => preferencesService.update({'notif_push': value}),
              colors: colors,
            )),
            Obx(() => _switchTile(
              icon: CupertinoIcons.chat_bubble,
              title: 'settings_notif_messages'.tr,
              subtitle: 'settings_notif_messages_desc'.tr,
              value: preferencesService.preferences.value.notifMessages,
              onChanged: (value) => preferencesService.update({'notif_messages': value}),
              colors: colors,
            )),
            Obx(() => _switchTile(
              icon: CupertinoIcons.calendar,
              title: 'settings_notif_events'.tr,
              subtitle: 'settings_notif_events_desc'.tr,
              value: preferencesService.preferences.value.notifEvenements,
              onChanged: (value) => preferencesService.update({'notif_evenements': value}),
              colors: colors,
            )),
            Obx(() => _switchTile(
              icon: CupertinoIcons.person_2,
              title: 'settings_notif_communities'.tr,
              subtitle: 'settings_notif_communities_desc'.tr,
              value: preferencesService.preferences.value.notifCommunautes,
              onChanged: (value) => preferencesService.update({'notif_communautes': value}),
              colors: colors,
            )),
            Obx(() => _switchTile(
              icon: CupertinoIcons.heart,
              title: 'settings_notif_social'.tr,
              subtitle: 'settings_notif_social_desc'.tr,
              value: preferencesService.preferences.value.notifSocial,
              onChanged: (value) => preferencesService.update({'notif_social': value}),
              colors: colors,
            )),
          ], colors),
          const SizedBox(height: 16),
          Text('settings_preferences_footer'.tr,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  Widget _intro(ColorScheme colors) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [colors.primary.withValues(alpha: .13), colors.primary.withValues(alpha: .04)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.primary.withValues(alpha: .12)),
    ),
    child: Row(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: Icon(CupertinoIcons.slider_horizontal_3, color: colors.primary, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('settings_preferences_title'.tr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface)),
        const SizedBox(height: 4),
        Text('settings_preferences_desc'.tr, style: TextStyle(fontSize: 13, height: 1.35, color: colors.onSurfaceVariant)),
      ])),
    ]),
  );

  Widget _section(String title, ColorScheme colors) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(title.toUpperCase(), style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, letterSpacing: 1.05, fontWeight: FontWeight.w700)),
  );

  Widget _group(List<Widget> children, ColorScheme colors) => Container(
    decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.outlineVariant.withValues(alpha: .35))),
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, indent: 54, endIndent: 14, color: colors.outlineVariant.withValues(alpha: .35)),
        children[i],
      ],
    ]),
  );

  Widget _switchTile({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged, required ColorScheme colors}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Row(children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: colors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: colors.primary)),
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
}
