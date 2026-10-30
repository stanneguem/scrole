import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupMembersScreen extends StatefulWidget {
  const CommunityChatGroupMembersScreen({super.key, required this.salonId, required this.groupName});
  final String salonId, groupName;
  @override
  State<CommunityChatGroupMembersScreen> createState() => _CommunityChatGroupMembersScreenState();
}
class _CommunityChatGroupMembersScreenState extends State<CommunityChatGroupMembersScreen> {
  final _db = Supabase.instance.client;
  List<Map<String,dynamic>> _members = [];
  String _myRole = 'member', _filter = 'all';
  bool _loading = true;
  String get _myId => _db.auth.currentUser?.id ?? '';
  bool get _owner => _myRole == 'owner';
  bool get _admin => _owner || _myRole == 'moderator';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final raw = await _db.rpc('get_community_chat_group_settings', params: {'p_salon_id': widget.salonId});
      final data = Map<String,dynamic>.from(raw as Map);
      final list = (data['members'] as List? ?? const []).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() { _members = list; _myRole = (data['my_role'] ?? 'member').toString(); _loading = false; });
    } catch(e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('community_members_load_error'.trParams({'error': e.toString()}));
    }
  }
  void _toast(String s) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating)); }
  String _role(String r) => r == 'owner' ? 'community_member_role_owner'.tr : r == 'moderator' ? 'community_member_role_admin'.tr : 'community_member_role_member'.tr;
  List<Map<String,dynamic>> get _visible => _members.where((m) {
    final r = (m['role'] ?? 'member').toString();
    return _filter == 'all' || (_filter == 'admins' && r == 'owner') || (_filter == 'moderators' && r == 'moderator') || (_filter == 'members' && r == 'member');
  }).toList();

  Future<bool> _confirm(String title, String body, String action) async =>
    await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(body),
      actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: Text('community_members_cancel'.tr)),
        FilledButton(onPressed: () => Navigator.pop(c,true), child: Text(action))])) ?? false;

  Future<void> _roleAction(Map<String,dynamic> m, String role) async {
    try {
      await _db.rpc('set_community_chat_group_member_role', params: {'p_salon_id':widget.salonId,'p_user_id':m['user_id'],'p_role':role});
      _toast((role == 'moderator' ? 'community_member_promoted' : 'community_member_demoted').tr);
      await _load();
    } catch(e) { _toast('community_member_action_error'.trParams({'error':e.toString()})); }
  }
  Future<void> _remove(Map<String,dynamic> m) async {
    final name = (m['display_name'] ?? 'community_member_fallback'.tr).toString();
    if (!await _confirm('community_member_remove_title'.tr,'community_member_remove_body'.trParams({'name':name}),'community_member_remove_action'.tr)) return;
    try {
      await _db.rpc('remove_community_chat_group_member',params:{'p_salon_id':widget.salonId,'p_user_id':m['user_id']});
      _toast('community_member_removed'.tr); await _load();
    } catch(e) { _toast('community_member_action_error'.trParams({'error':e.toString()})); }
  }
  Future<void> _transfer(Map<String,dynamic> m) async {
    final name = (m['display_name'] ?? '').toString();
    if (!await _confirm('community_member_transfer_title'.tr,'community_member_transfer_body'.trParams({'name':name}),'community_member_transfer_action'.tr)) return;
    try {
      await _db.rpc('transfer_community_chat_group_ownership',params:{'p_salon_id':widget.salonId,'p_new_owner_id':m['user_id']});
      _toast('community_member_transferred'.tr); await _load();
    } catch(e) { _toast('community_member_action_error'.trParams({'error':e.toString()})); }
  }
  void _profile(Map<String,dynamic> m) {
    final id = (m['user_id'] ?? '').toString();
    if(id.isNotEmpty && id != _myId) Get.toNamed(AppPages.externalProfilePath(id));
  }
  void _actions(Map<String,dynamic> m) {
    final r = (m['role'] ?? 'member').toString(), self = m['user_id'] == _myId;
    final promote = _owner && r == 'member', demote = _owner && r == 'moderator';
    final remove = !self && r != 'owner' && (_owner || (_myRole == 'moderator' && r == 'member'));
    showModalBottomSheet(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(16,4,16,20),child:Column(mainAxisSize:MainAxisSize.min,children:[
        _identity(m,large:true),const SizedBox(height:12),
        if(!self) ListTile(leading:const Icon(Icons.person_outline),title:Text('community_member_view_profile'.tr),onTap:(){Navigator.pop(ctx);_profile(m);}),
        if(self) Padding(padding:const EdgeInsets.all(8),child:Text('community_member_self_profile_hint'.tr)),
        if(promote) ListTile(leading:const Icon(Icons.admin_panel_settings_outlined),title:Text('community_member_promote'.tr),onTap:(){Navigator.pop(ctx);_roleAction(m,'moderator');}),
        if(demote) ListTile(leading:const Icon(Icons.person_outline),title:Text('community_member_demote'.tr),onTap:(){Navigator.pop(ctx);_roleAction(m,'member');}),
        if(_owner && !self && r != 'owner') ListTile(leading:const Icon(Icons.swap_horiz),title:Text('community_member_transfer_action'.tr),onTap:(){Navigator.pop(ctx);_transfer(m);}),
        if(remove) ListTile(leading:Icon(Icons.person_remove_outlined,color:Theme.of(ctx).colorScheme.error),title:Text('community_member_remove_action'.tr,style:TextStyle(color:Theme.of(ctx).colorScheme.error)),onTap:(){Navigator.pop(ctx);_remove(m);}),
      ]))));
  }
  Widget _identity(Map<String,dynamic> m,{bool large=false}) {
    final id=(m['user_id']??'').toString(), photo=(m['photo_url']??'').toString(), role=(m['role']??'member').toString();
    final radius=large?30.0:25.0;
    return Row(children:[
      SizedBox(width:radius*2,height:radius*2,child:ClipOval(child:photo.isEmpty
        ? ColoredBox(color:Theme.of(context).colorScheme.surfaceContainerHighest,child:Icon(Icons.person_outline,size:radius))
        : AppCachedImage(imageUrl:photo,fit:BoxFit.cover))),
      const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Flexible(child:Text((m['display_name']??'community_member_fallback'.tr).toString(),overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700))),
          if(id.isNotEmpty) ...[const SizedBox(width:5),UserCertifiedBadge(size:16,userId:id)]]),
        const SizedBox(height:5),Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:3),
          decoration:BoxDecoration(color:role=='owner'?const Color(0xFFFFF1D6):Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(18)),
          child:Text(_role(role),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600))),
      ]))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c=Theme.of(context).colorScheme;
    final owners=_members.where((m)=>m['role']=='owner').length, mods=_members.where((m)=>m['role']=='moderator').length, regular=_members.where((m)=>(m['role']??'member')=='member').length;
    final filters=[('all','community_members_filter_all'.tr),('admins','community_members_filter_admins'.tr),('moderators','community_members_filter_moderators'.tr),('members','community_members_filter_members'.tr)];
    return Scaffold(appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('community_members_title'.tr),Text(widget.groupName,style:Theme.of(context).textTheme.bodySmall)]),
      actions:[IconButton(tooltip:'community_members_search'.tr,icon:const Icon(Icons.search),onPressed:(){
        showSearch(context:context,delegate:_MembersSearch(_members,_myId,(m)=>_actions(m)));
      })]),
      body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,28),children:[
        Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:c.primaryContainer.withOpacity(.45),borderRadius:BorderRadius.circular(20)),
          child:Row(children:[CircleAvatar(backgroundColor:c.primaryContainer,child:Icon(Icons.groups_rounded,color:c.primary)),const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('community_members_count'.trParams({'count':_members.length.toString()}),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16)),
              Text('community_members_breakdown'.trParams({'owners':'$owners','moderators':'$mods','members':'$regular'}),style:TextStyle(color:c.onSurfaceVariant,fontSize:12))
            ]))])),
        const SizedBox(height:14),SizedBox(height:42,child:ListView(scrollDirection:Axis.horizontal,children:filters.map((f)=>Padding(padding:const EdgeInsets.only(right:7),
          child:ChoiceChip(label:Text(f.$2),selected:_filter==f.$1,onSelected:(_)=>setState(()=>_filter=f.$1)))).toList())),
        const SizedBox(height:8),
        if(_visible.isEmpty) Padding(padding:const EdgeInsets.all(30),child:Center(child:Text('community_members_empty'.tr))),
        ..._visible.map((m){final self=m['user_id']==_myId, role=(m['role']??'member').toString();
          return Column(children:[ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:4,vertical:7),
            leading:SizedBox(width:52,height:52,child:ClipOval(child:(m['photo_url']??'').toString().isEmpty
              ?ColoredBox(color:c.surfaceContainerHighest,child:Icon(Icons.person_outline,color:c.onSurfaceVariant))
              :AppCachedImage(imageUrl:m['photo_url'].toString(),fit:BoxFit.cover))),
            title:Row(children:[Flexible(child:Text((m['display_name']??'community_member_fallback'.tr).toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600))),
              if((m['user_id']??'').toString().isNotEmpty)...[const SizedBox(width:5),UserCertifiedBadge(size:16,userId:m['user_id'].toString())]]),
            subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Wrap(spacing:6,children:[
              Text('@'+(m['username']??'').toString(),style:TextStyle(color:c.onSurfaceVariant,fontSize:12)),
              Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),decoration:BoxDecoration(color:role=='owner'?const Color(0xFFFFF1D6):role=='moderator'?c.primaryContainer:c.surfaceContainerHighest,borderRadius:BorderRadius.circular(14)),
                child:Text(_role(role),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)))
            ])),
            trailing:_admin&&!self&&role!='owner'?IconButton(icon:const Icon(Icons.more_horiz),tooltip:'community_member_actions'.tr,onPressed:()=>_actions(m)):Icon(Icons.chevron_right,color:c.onSurfaceVariant),
            onTap:()=>self?_actions(m):_profile(m)),
            Divider(height:1,indent:68,color:c.outlineVariant.withOpacity(.45))]);
        })
      ])));
  }
}

class _MembersSearch extends SearchDelegate<void> {
  _MembersSearch(this.members,this.selfId,this.onSelect);
  final List<Map<String,dynamic>> members; final String selfId; final ValueChanged<Map<String,dynamic>> onSelect;
  @override String get searchFieldLabel=>'community_members_search_hint'.tr;
  @override List<Widget> buildActions(BuildContext c)=>[IconButton(icon:const Icon(Icons.clear),onPressed:()=>query='')];
  @override Widget buildLeading(BuildContext c)=>IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>close(c,null));
  @override Widget buildResults(BuildContext c)=>_list(c);
  @override Widget buildSuggestions(BuildContext c)=>_list(c);
  Widget _list(BuildContext c){final q=query.toLowerCase();final rows=members.where((m)=>(m['display_name']??'').toString().toLowerCase().contains(q)||(m['username']??'').toString().toLowerCase().contains(q));
    return ListView(children:rows.map((m)=>ListTile(title:Text((m['display_name']??'').toString()),subtitle:Text('@'+(m['username']??'').toString()),onTap:(){close(c,null);onSelect(m);})).toList());}
}
