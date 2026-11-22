import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupVisibilityScreen extends StatefulWidget {
  const CommunityChatGroupVisibilityScreen({
    super.key,
    required this.salonId,
    required this.initialData,
  });

  final String salonId;
  final Map<String, dynamic> initialData;

  @override
  State<CommunityChatGroupVisibilityScreen> createState() =>
      _CommunityChatGroupVisibilityScreenState();
}

class _CommunityChatGroupVisibilityScreenState
    extends State<CommunityChatGroupVisibilityScreen> {
  String _visibility = 'public';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = widget.initialData['visibility']?.toString();
    _visibility = current == 'private' ? 'private' : 'public';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'update_community_chat_group_settings',
        params: {
          'p_salon_id': widget.salonId,
          'p_name': widget.initialData['name'],
          'p_description': widget.initialData['description'] ?? '',
          'p_visibility': _visibility,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('community_visibility_save_error'.trParams({
            'error': error.toString(),
          })),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice({
    required BuildContext context,
    required String value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = _visibility == value;
    return Material(
      color: selected
          ? colors.primary.withOpacity(.075)
          : colors.surfaceContainerHighest.withOpacity(.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _saving ? null : () => setState(() => _visibility = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant.withOpacity(.55),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? colors.primary.withOpacity(.13) : colors.surface,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: selected ? colors.primary : colors.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(description, style: TextStyle(fontSize: 12.5, height: 1.35, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.primary : Colors.transparent,
                  border: Border.all(color: selected ? colors.primary : colors.outline, width: 1.5),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('community_visibility_title'.tr),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('community_visibility_save'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Text('community_visibility_intro'.tr,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.45)),
          const SizedBox(height: 22),
          _choice(
            context: context,
            value: 'public',
            icon: CupertinoIcons.globe,
            title: 'community_visibility_public'.tr,
            description: 'community_visibility_public_description'.tr,
          ),
          const SizedBox(height: 13),
          _choice(
            context: context,
            value: 'private',
            icon: CupertinoIcons.lock,
            title: 'community_visibility_private'.tr,
            description: 'community_visibility_private_description'.tr,
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withOpacity(.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: colors.onSurfaceVariant, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('community_visibility_note'.tr,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.onSurfaceVariant))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
