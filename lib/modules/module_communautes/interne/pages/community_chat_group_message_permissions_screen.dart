import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupMessagePermissionsScreen extends StatefulWidget {
  const CommunityChatGroupMessagePermissionsScreen({super.key, required this.salonId});
  final String salonId;

  @override
  State<CommunityChatGroupMessagePermissionsScreen> createState() =>
      _CommunityChatGroupMessagePermissionsScreenState();
}

class _CommunityChatGroupMessagePermissionsScreenState
    extends State<CommunityChatGroupMessagePermissionsScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _isAdmin = false;
  bool _textAllowed = true;
  bool _audioAllowed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _db.rpc(
        'get_community_chat_group_settings',
        params: {'p_salon_id': widget.salonId},
      );
      final data = Map<String, dynamic>.from(raw as Map);
      if (!mounted) return;
      setState(() {
        _isAdmin = data['is_salon_admin'] == true || data['my_role'] == 'owner';
        _textAllowed = data['text_messages_allowed'] != false;
        _audioAllowed = data['audio_messages_allowed'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_message_permissions_save_error'.trParams({'error': e.toString()}));
    }
  }

  Future<void> _update({bool? text, bool? audio}) async {
    if (_saving || !_isAdmin) return;
    final oldText = _textAllowed;
    final oldAudio = _audioAllowed;
    setState(() {
      _saving = true;
      if (text != null) _textAllowed = text;
      if (audio != null) _audioAllowed = audio;
    });
    try {
      await _db.rpc('update_salon_message_permissions', params: {
        'p_salon_id': widget.salonId,
        'p_text_messages_allowed': _textAllowed,
        'p_audio_messages_allowed': _audioAllowed,
      });
      if (!mounted) return;
      _toast('community_message_permissions_saved'.tr);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _textAllowed = oldText;
        _audioAllowed = oldAudio;
      });
      _toast('community_message_permissions_save_error'.trParams({'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _permissionCard({
    required ColorScheme colors,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withOpacity(.08)),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.fromLTRB(17, 12, 12, 12),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.primary.withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: colors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(description),
        ),
        value: value,
        onChanged: _saving || !_isAdmin ? null : onChanged,
        activeColor: const Color(0xFFF0642C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_message_permissions_screen_title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Text(
                    'community_message_permissions_screen_intro'.tr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                _permissionCard(
                  colors: colors,
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'community_message_permissions_text_title'.tr,
                  description: 'community_message_permissions_text_description'.tr,
                  value: _textAllowed,
                  onChanged: (value) => _update(text: value),
                ),
                _permissionCard(
                  colors: colors,
                  icon: Icons.mic_none_rounded,
                  title: 'community_message_permissions_audio_title'.tr,
                  description: 'community_message_permissions_audio_description'.tr,
                  value: _audioAllowed,
                  onChanged: (value) => _update(audio: value),
                ),
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Text(
                      'community_message_permissions_admin_only'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  ),
              ],
            ),
    );
  }
}
