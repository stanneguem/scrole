import 'package:flutter/material.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupMembersScreen extends StatefulWidget {
  const CommunityChatGroupMembersScreen({super.key,required this.salonId,required this.groupName});
  final String salonId;
  final String groupName;
  @override
  State<CommunityChatGroupMembersScreen> createState()=>_CommunityChatGroupMembersScreenState();
}

class _CommunityChatGroupMembersScreenState extends State<CommunityChatGroupMembersScreen>{
  final _db=Supabase.instance.client;
  List<Map<String,dynamic>> _members=[];
  String _myRole='member';
  bool _loading=true;
  @override
  void initState(){super.initState();_load();}

  Future<void> _load()async{
    try{
      final raw=await _db.rpc('get_community_chat_group_settings',params:{'p_salon_id':widget.salonId});
      final data=Map<String,dynamic>.from(raw as Map);
      final members=(data['members'] as List? ??const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      if(!mounted)return;
      setState(()=>{_members=members,_myRole=(data['my_role']??'member').toString(),_loading=false});
    }catch(e){if(!mounted)return;setState(()=>_loading=false);_toast('Impossible de charger les membres : $e');}
  }

  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}

  Future<void> _setRole(Map<String,dynamic> member,String role)async{
    try{
      await _db.rpc('set_community_chat_group_member_role',params:{
        'p_salon_id':widget.salonId,'p_user_id':member['user_id'],'p_role':role,
      });
      _toast(role=='moderator'?'Administrateur du salon ajouté.':'Rôle administrateur retiré.');
      await _load();
    }catch(e){_toast('Impossible de modifier le rôle : $e');}
  }

  Future<void> _remove(Map<String,dynamic> member)async{
    final name=(member['display_name']??'ce membre').toString();
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Retirer ce membre ?'),
      content:Text('$name ne pourra plus accéder à cette discussion.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Annuler')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Retirer'))],
    ));
    if(yes!=true)return;
    try{
      await _db.rpc('remove_community_chat_group_member',params:{'p_salon_id':widget.salonId,'p_user_id':member['user_id']});
      _toast('Membre retiré de la discussion.');
      await _load();
    }catch(e){_toast('Impossible de retirer ce membre : $e');}
  }

  Widget _menu(Map<String,dynamic> member){
    final role=(member['role']??'member').toString();
    if(role=='owner')return const SizedBox.shrink();
    final canPromote=_myRole=='owner';
    final canRemove=_myRole=='owner'||(_myRole=='moderator'&&role=='member');
    if(!canPromote&&!canRemove)return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip:'Gérer ce membre',
      onSelected:(action){if(action=='promote')_setRole(member,'moderator');if(action=='demote')_setRole(member,'member');if(action=='remove')_remove(member);},
      itemBuilder:(_)=>[
        if(canPromote&&role=='member')const PopupMenuItem(value:'promote',child:ListTile(dense:true,leading:Icon(Icons.admin_panel_settings_outlined),title:Text('Nommer administrateur'))),
        if(canPromote&&role=='moderator')const PopupMenuItem(value:'demote',child:ListTile(dense:true,leading:Icon(Icons.person_outline),title:Text('Retirer le rôle admin'))),
        if(canRemove)const PopupMenuItem(value:'remove',child:ListTile(dense:true,leading:Icon(Icons.person_remove_outlined,color:Colors.red),title:Text('Retirer du salon',style:TextStyle(color:Colors.red)))),
      ],
    );
  }

  @override
  Widget build(BuildContext context){
    final c=Theme.of(context).colorScheme;
    return Scaffold(appBar:AppBar(title:Text('Membres • ${widget.groupName}')),
      body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(
        onRefresh:_load,child:ListView.separated(physics:const AlwaysScrollableScrollPhysics(),
          itemCount:_members.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:76),
          itemBuilder:(context,index){
            final member=_members[index];
            final photo=member['photo_url']?.toString();
            final role=(member['role']??'member').toString();
            return ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:5),
              leading:CircleAvatar(radius:24,backgroundColor:c.surfaceContainerHighest,
                child:ClipOval(child:photo==null||photo.isEmpty?Icon(Icons.person_outline,color:c.onSurfaceVariant):AppCachedImage(imageUrl:photo,fit:BoxFit.cover))),
              title:Text((member['display_name']??'Membre').toString(),style:const TextStyle(fontWeight:FontWeight.w600)),
              subtitle:Text('@${member['username']??''}'),
              trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                if(role=='owner'||role=='moderator')Text(role=='owner'?'Propriétaire':'Admin du salon',
                  style:TextStyle(fontSize:11,color:c.primary,fontWeight:FontWeight.w600)),
                if(_myRole=='owner'&&role!='owner'||_myRole=='moderator'&&role=='member')_menu(member),
              ]),
            );
          },
        ),
      ),
    );
  }
}
