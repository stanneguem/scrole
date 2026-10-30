import 'package:flutter/material.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupMembersScreen extends StatefulWidget {
  const CommunityChatGroupMembersScreen({
    super.key,
    required this.salonId,
    required this.groupName,
  });
  final String salonId;
  final String groupName;

  @override
  State<CommunityChatGroupMembersScreen> createState() =>
      _CommunityChatGroupMembersScreenState();
}

class _CommunityChatGroupMembersScreenState
    extends State<CommunityChatGroupMembersScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_community_chat_group_settings',
        params: {'p_salon_id': widget.salonId},
      );
      final data = Map<String, dynamic>.from(result as Map);
      final members = (data['members'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de charger les membres : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Membres • ${widget.groupName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _members.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final photo = member['photo_url']?.toString();
                  final role = (member['role'] ?? 'member').toString();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.surfaceContainerHighest,
                      child: ClipOval(
                        child: photo == null || photo.isEmpty
                            ? Icon(Icons.person_outline, color: colors.onSurfaceVariant)
                            : AppCachedImage(imageUrl: photo, fit: BoxFit.cover),
                      ),
                    ),
                    title: Text((member['display_name'] ?? 'Membre').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('@${member['username'] ?? ''}'),
                    trailing: role == 'owner' || role == 'moderator'
                        ? Text(role == 'owner' ? 'Propriétaire' : 'Admin du groupe',
                            style: TextStyle(fontSize: 11, color: colors.primary))
                        : null,
                  );
                },
              ),
            ),
    );
  }
}
