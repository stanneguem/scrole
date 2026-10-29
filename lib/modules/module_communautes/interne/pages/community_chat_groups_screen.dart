import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discussions textuelles d'une communauté : groupes publics/privés et demandes d'accès.
class CommunityChatGroupsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  const CommunityChatGroupsScreen({super.key, required this.communityId, required this.communityName});

  @override
  State<CommunityChatGroupsScreen> createState() => _CommunityChatGroupsScreenState();
}

class _CommunityChatGroupsScreenState extends State<CommunityChatGroupsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _client.rpc('list_community_chat_groups', params: {'p_community_id': widget.communityId});
      if (!mounted) return;
      setState(() {
        _groups = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de charger les discussions : $e')));
    }
  }

  Future<void> _createGroup() async {
    final name = TextEditingController();
    final description = TextEditingController();
    var visibility = 'public';
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Créer une discussion'),
        content: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Nom du groupe'), validator: (v) => (v == null || v.trim().length < 2) ? 'Saisis au moins 2 caractères' : null),
          TextFormField(controller: description, maxLength: 300, decoration: const InputDecoration(labelText: 'Description (facultatif)')),
          const SizedBox(height: 12),
          RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'public', groupValue: visibility, title: const Text('Public'), subtitle: const Text('Les membres autorisés peuvent entrer directement'), onChanged: (v) => setDialogState(() => visibility = v!)),
          RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'private', groupValue: visibility, title: const Text('Privé'), subtitle: const Text('L’accès nécessite une approbation'), onChanged: (v) => setDialogState(() => visibility = v!)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Créer')),
        ],
      )),
    );
    if (accepted != true) return;
    setState(() => _creating = true);
    try {
      await _client.rpc('create_community_chat_group', params: {
        'p_id': _client.auth.currentUser == null ? null : _newUuid(),
        'p_community_id': widget.communityId,
        'p_name': name.text.trim(),
        'p_description': description.text.trim(),
        'p_visibility': visibility,
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Discussion créée')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Création impossible : $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _newUuid() {
    // UUID v4 generated with a cryptographically secure random source.
    final secureRandom = math.Random.secure();
    final random = List<int>.generate(16, (_) => secureRandom.nextInt(256));
    random[6] = (random[6] & 0x0f) | 0x40;
    random[8] = (random[8] & 0x3f) | 0x80;
    final hex = random.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  Future<void> _openOrRequest(Map<String, dynamic> group) async {
    try {
      final result = await _client.rpc('request_community_chat_group_access', params: {'p_salon_id': group['id']});
      final status = result is Map ? result['status']?.toString() : 'accepted';
      if (status == 'accepted') {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityChatGroupConversation(
          salonId: group['id'].toString(), name: group['name']?.toString() ?? 'Discussion',
          communityName: widget.communityName,
        )));
        await _load();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée. Elle attend l’approbation des responsables.')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Accès impossible : $e')));
    }
  }

  Future<void> _showRequests(Map<String, dynamic> group) async {
    try {
      final data = await _client.rpc('get_community_chat_group_requests', params: {'p_salon_id': group['id']});
      if (!mounted) return;
      final requests = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => SafeArea(
        child: SizedBox(height: MediaQuery.of(context).size.height * .65, child: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Demandes d’accès', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          Expanded(child: requests.isEmpty ? const Center(child: Text('Aucune demande en attente')) : ListView.builder(
            itemCount: requests.length,
            itemBuilder: (_, i) {
              final request = requests[i];
              final username = (request['username'] ?? 'Utilisateur').toString();
              return ListTile(
                leading: CircleAvatar(child: Text(username.isEmpty ? '?' : username[0].toUpperCase())),
                title: Text(username),
                subtitle: Text('Demandé le ${request['requested_at'] ?? ''}'),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(tooltip: 'Refuser', icon: const Icon(Icons.close, color: Colors.red), onPressed: () async { await _review(request['request_id'].toString(), 'rejected'); if (sheetContext.mounted) Navigator.pop(sheetContext); }),
                  IconButton(tooltip: 'Accepter', icon: const Icon(Icons.check, color: Colors.green), onPressed: () async { await _review(request['request_id'].toString(), 'accepted'); if (sheetContext.mounted) Navigator.pop(sheetContext); }),
                ]),
              );
            },
          )),
        ])),
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de charger les demandes : $e')));
    }
  }

  Future<void> _review(String id, String decision) async {
    try {
      await _client.rpc('review_community_chat_group_request', params: {'p_request_id': id, 'p_decision': decision});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(decision == 'accepted' ? 'Demande acceptée' : 'Demande refusée')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Discussions'),
        Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]), actions: [IconButton(onPressed: _creating ? null : _createGroup, tooltip: 'Créer une discussion', icon: const Icon(Icons.add_comment_outlined))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: _groups.isEmpty ? ListView(children: const [
          SizedBox(height: 130), Icon(Icons.forum_outlined, size: 58), SizedBox(height: 16),
          Center(child: Text('Aucune discussion pour le moment')),
          Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Crée un groupe pour démarrer une conversation.', textAlign: TextAlign.center))),
        ]) : ListView.separated(
          padding: const EdgeInsets.all(12), itemCount: _groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final group = _groups[i];
            final isPrivate = group['visibility'] == 'private';
            final status = (group['my_status'] ?? 'none').toString();
            final canManage = group['can_manage'] == true;
            final isMember = status == 'member' || group['created_by'] == _client.auth.currentUser?.id;
            final pending = status == 'pending';
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: colors.primaryContainer, child: Icon(isPrivate ? Icons.lock_outline : Icons.forum_outlined, color: colors.onPrimaryContainer)),
              title: Text((group['name'] ?? 'Discussion').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((group['description'] ?? '').toString().isNotEmpty) Text(group['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(isPrivate ? 'Groupe privé' : 'Groupe public'),
                if (group['member_count'] != null) Text('${group['member_count']} membre(s)'),
                if (pending) const Text('Demande en attente'),
              ]),
              isThreeLine: (group['description'] ?? '').toString().isNotEmpty,
              onTap: pending ? null : () => _openOrRequest(group),
              trailing: canManage && isPrivate ? IconButton(icon: const Icon(Icons.group_add_outlined), tooltip: 'Gérer les demandes', onPressed: () => _showRequests(group)) : Icon(isMember ? Icons.chevron_right : (pending ? Icons.hourglass_top : Icons.lock_open_outlined)),
            ));
          },
        ),
      ),
    );
  }
}

class CommunityChatGroupConversation extends StatefulWidget {
  final String salonId;
  final String name;
  final String communityName;
  const CommunityChatGroupConversation({super.key, required this.salonId, required this.name, required this.communityName});
  @override
  State<CommunityChatGroupConversation> createState() => _CommunityChatGroupConversationState();
}

class _CommunityChatGroupConversationState extends State<CommunityChatGroupConversation> {
  final _client = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _client.channel('community-chat-${widget.salonId}')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'community_salon_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'salon_id', value: widget.salonId), callback: (_) => _loadMessages())
      .subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _client.rpc('get_salon_messages', params: {'p_salon_id': widget.salonId, 'p_limit': 100});
      if (!mounted) return;
      final messages = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
      setState(() { _messages = messages; _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chargement des messages impossible : $e')));
    }
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.rpc('send_salon_message', params: {'p_id': _newUuid(), 'p_salon_id': widget.salonId, 'p_content': content, 'p_type': 'texte'});
      _input.clear();
      await _loadMessages();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : $e')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  String _newUuid() {
    final secureRandom = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  @override
  void dispose() {
    _input.dispose(); _scroll.dispose();
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _client.auth.currentUser?.id;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(widget.communityName, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ])),
      body: Column(children: [
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _messages.isEmpty
          ? const Center(child: Text('Soyez le premier à écrire dans ce groupe.'))
          : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) {
            final message = _messages[i];
            final mine = message['sender_id']?.toString() == uid;
            final deleted = message['is_deleted'] == true;
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(color: mine ? colors.primaryContainer : colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!mine) Text((message['sender_id'] ?? 'Membre').toString().substring(0, (message['sender_id'] ?? 'Membre').toString().length.clamp(0, 8)), style: TextStyle(fontSize: 10, color: colors.primary, fontWeight: FontWeight.bold)),
                Text(deleted ? 'Message supprimé' : (message['content'] ?? '').toString(), style: TextStyle(color: colors.onSurface)),
                const SizedBox(height: 3),
                Text((message['sent_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first, style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant)),
              ]),
            ));
          })),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 8), child: Row(children: [
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'Écrire un message…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)), onSubmitted: (_) => _send())),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
        ]))),
      ]),
    );
  }
}
