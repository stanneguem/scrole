import 'package:flutter/material.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_edit_info_screen.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_chat_group_members_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_chat_group_access_rules_screen.dart';

class CommunityChatGroupManagementScreen extends StatefulWidget {
  const CommunityChatGroupManagementScreen({super.key, required this.salonId, required this.groupName});
  final String salonId;
  final String groupName;
  @override
  State<CommunityChatGroupManagementScreen> createState() => _CommunityChatGroupManagementScreenState();
}

class _CommunityChatGroupManagementScreenState extends State<CommunityChatGroupManagementScreen> {
  final _db = Supabase.instance.client;
  Map<String,dynamic> _data = {};
  int _pending = 0;
  bool _loading = true, _saving = false;
  bool get _owner => _data['my_role']=='owner';

  @override
  void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final raw=await _db.rpc('get_community_chat_group_settings',params:{'p_salon_id':widget.salonId});
      final data=Map<String,dynamic>.from(raw as Map);
      final requests=await _db.rpc('get_community_chat_group_requests',params:{'p_salon_id':widget.salonId});
      if(!mounted)return;
      setState(()=>{_data=data,_pending=(requests as List).length,_loading=false});
    } catch(e) {
      if(!mounted)return;
      setState(()=>_loading=false);
      _toast('Impossible de charger les options : $e');
    }
  }

  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}

  Future<void> _visibility(String value) async {
    if(_saving)return;
    setState(()=>_saving=true);
    try {
      await _db.rpc('update_community_chat_group_settings',params:{
        'p_salon_id':widget.salonId,'p_name':_data['name'],
        'p_description':_data['description']??'','p_visibility':value,
      });
      await _load(); _toast('Visibilité mise à jour.');
    } catch(e){_toast('Impossible de modifier la visibilité : $e');}
    finally{if(mounted)setState(()=>_saving=false);}
  }

  Future<void> _audio(bool value) async {
    if(_saving)return;
    final rules=Map<String,dynamic>.from(_data['access_rules']??{});
    setState(()=>_saving=true);
    try {
      await _db.rpc('update_community_chat_group_advanced_settings',params:{
        'p_salon_id':widget.salonId,
        'p_audio_messages_allowed':value,
        'p_countries_enabled':rules['countries_enabled']==true,
        'p_allowed_countries':List<String>.from(rules['allowed_countries']??[]),
        'p_cities_enabled':rules['cities_enabled']==true,
        'p_allowed_cities':List<String>.from(rules['allowed_cities']??[]),
        'p_certification_required':rules['certification_required']==true,
        'p_gender_restriction':rules['gender_restriction'],
        'p_age_min':rules['age_min'],'p_age_max':rules['age_max'],
      });
      await _load();
    }catch(e){_toast('Impossible de modifier les messages audio : $e');}
    finally{if(mounted)setState(()=>_saving=false);}
  }

  Future<void> _requests() async {
    try {
      final raw=await _db.rpc('get_community_chat_group_requests',params:{'p_salon_id':widget.salonId});
      final requests=(raw as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      if(!mounted)return;
      await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(
        child:SizedBox(height:MediaQuery.of(ctx).size.height*.72,child:Column(children:[
          Padding(padding:const EdgeInsets.all(18),child:Text('Demandes d’adhésion (${requests.length})',style:Theme.of(ctx).textTheme.titleLarge)),
          Expanded(child:requests.isEmpty?const Center(child:Text('Aucune demande en attente.')):ListView.separated(
            itemCount:requests.length,separatorBuilder:(_,__)=>const Divider(height:1),
            itemBuilder:(ctx,i){
              final item=requests[i];
              final username=(item['username']??'Utilisateur').toString();
              final photo=item['photo_url']?.toString();
              return ListTile(
                leading:CircleAvatar(backgroundImage:photo==null||photo.isEmpty?null:NetworkImage(photo),child:photo==null||photo.isEmpty?const Icon(Icons.person_outline):null),
                title:Text(username),subtitle:Text('Demande du ${item['requested_at']??''}'),
                trailing:Wrap(spacing:0,children:[
                  IconButton(tooltip:'Refuser',icon:const Icon(Icons.close,color:Colors.red),onPressed:()=>_review(item['request_id'].toString(),'rejected',ctx)),
                  IconButton(tooltip:'Accepter',icon:const Icon(Icons.check,color:Colors.green),onPressed:()=>_review(item['request_id'].toString(),'accepted',ctx)),
                ]),
              );
            },
          )),
        ])),
      ));
      await _load();
    }catch(e){_toast('Impossible de charger les demandes : $e');}
  }

  Future<void> _review(String id,String decision,BuildContext sheet) async {
    try {
      await _db.rpc('review_community_chat_group_request',params:{'p_request_id':id,'p_decision':decision});
      if(sheet.mounted)Navigator.pop(sheet);
      _toast(decision=='accepted'?'Demande acceptée.':'Demande refusée.');
      await _load();
    }catch(e){_toast('Action impossible : $e');}
  }

  Future<void> _delete() async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Éliminer la discussion ?'),
      content:const Text('La discussion, ses messages et ses membres seront supprimés définitivement. Cette action est irréversible.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Annuler')),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(ctx).colorScheme.error),onPressed:()=>Navigator.pop(ctx,true),child:const Text('Éliminer'))],
    ));
    if(yes!=true)return;
    try{await _db.rpc('delete_community_chat_group',params:{'p_salon_id':widget.salonId});if(mounted)Navigator.pop(context,'deleted');}
    catch(e){_toast('Suppression impossible : $e');}
  }

  Widget _section(ColorScheme c,List<Widget> children)=>Container(
    margin:const EdgeInsets.symmetric(horizontal:16),decoration:BoxDecoration(
      color:c.surfaceContainerHighest.withOpacity(.28),borderRadius:BorderRadius.circular(18),
      border:Border.all(color:c.outline.withOpacity(.08))),clipBehavior:Clip.antiAlias,child:Column(children:children));

  Widget _tile(ColorScheme c,IconData icon,String title,String subtitle,VoidCallback tap,{Color? color,String? trailing})=>ListTile(
    leading:Icon(icon,color:color??c.onSurfaceVariant),title:Text(title,style:TextStyle(fontWeight:FontWeight.w600,color:color)),
    subtitle:Text(subtitle),trailing:trailing==null?const Icon(Icons.chevron_right_rounded):Text(trailing,style:TextStyle(color:c.primary,fontWeight:FontWeight.w600)),
    onTap:tap);

  @override
  Widget build(BuildContext context){
    final c=Theme.of(context).colorScheme;
    if(_loading)return Scaffold(appBar:AppBar(title:const Text('Gestion de la discussion')),body:const Center(child:CircularProgressIndicator()));
    final visibility=(_data['visibility']??'public').toString();
    return Scaffold(appBar:AppBar(title:const Text('Gestion de la discussion')),
      body:ListView(padding:const EdgeInsets.only(top:14,bottom:32),children:[
        _section(c,[
          _tile(c,Icons.edit_outlined,'Modifier les informations','Nom, description et photo du salon',()async{
            final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>CommunityChatGroupEditInfoScreen(salonId:widget.salonId,initialData:_data)));
            if(changed==true)_load();
          }),
          _tile(c,Icons.people_alt_outlined,'Gérer les membres','Promouvoir, rétrograder ou retirer des membres',()async{
            await Navigator.push(context,MaterialPageRoute(builder:(_)=>CommunityChatGroupMembersScreen(salonId:widget.salonId,groupName:widget.groupName)));
            _load();
          }),
          _tile(c,Icons.person_add_alt_1_outlined,'Demandes d’adhésion','Examiner les demandes pour rejoindre le salon',_requests,trailing:_pending==0?'':_pending.toString()),
        ]),
        const SizedBox(height:16),
        _section(c,[
          ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:17,vertical:4),
            leading:Icon(Icons.lock_outline_rounded,color:c.onSurfaceVariant),
            title:const Text('Visibilité du salon',style:TextStyle(fontWeight:FontWeight.w600)),
            subtitle:const Text('Qui peut trouver et rejoindre cette discussion'),
            trailing:DropdownButton<String>(value:visibility=='private'?'private':'public',underline:const SizedBox.shrink(),
              items:const[DropdownMenuItem(value:'public',child:Text('Publique')),DropdownMenuItem(value:'private',child:Text('Privée'))],
              onChanged:_saving?null:(v){if(v!=null)_visibility(v);})),
          SwitchListTile.adaptive(contentPadding:const EdgeInsets.symmetric(horizontal:17),
            secondary:Icon(Icons.mic_none_rounded,color:c.onSurfaceVariant),
            title:const Text('Messages audio',style:TextStyle(fontWeight:FontWeight.w600)),
            subtitle:const Text('Autoriser les membres à envoyer des messages vocaux'),
            value:_data['audio_messages_allowed']==true,onChanged:_saving?null:_audio,activeColor:const Color(0xFFF0642C)),
          _tile(c,Icons.admin_panel_settings_outlined,'Conditions d’accès','Pays, villes, certification, genre et âge',()async{
            final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>CommunityChatGroupAccessRulesScreen(salonId:widget.salonId,initialData:_data)));
            if(changed==true)_load();
          }),
        ]),
        const SizedBox(height:16),
        if(_owner)_section(c,[
          _tile(c,Icons.delete_forever_outlined,'Éliminer la discussion','Supprimer définitivement le salon et son contenu',_delete,color:c.error),
        ]),
        const SizedBox(height:20),
        Padding(padding:const EdgeInsets.symmetric(horizontal:22),child:Text(
          _owner?'Tu es propriétaire de cette discussion.': 'Tu es administrateur de cette discussion.',
          style:Theme.of(context).textTheme.bodySmall?.copyWith(color:c.onSurfaceVariant))),
      ]));
  }
}
