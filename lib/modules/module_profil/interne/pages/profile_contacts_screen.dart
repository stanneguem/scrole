import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/routes/app_pages.dart';

class ProfileContactsScreen extends StatelessWidget {
  const ProfileContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('follow_lists_title'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.people_alt_rounded, color: scheme.primary),
              title: Text('follow_lists_title'.tr),
              subtitle: Text('follow_tab_followers'.tr + ' · ' + 'follow_tab_following'.tr + ' · ' + 'follow_tab_friends'.tr),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Get.toNamed(AppPages.followLists),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.person_add_alt_1_rounded, color: scheme.primary),
              title: Text('follow_requests_title'.tr),
              subtitle: Text('follow_requests_received'.tr + ' · ' + 'follow_requests_sent'.tr),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Get.toNamed(AppPages.followRequests),
            ),
          ),
        ],
      ),
    );
  }
}
