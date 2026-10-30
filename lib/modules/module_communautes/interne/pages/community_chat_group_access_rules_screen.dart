import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityChatGroupAccessRulesScreen extends StatefulWidget {
  const CommunityChatGroupAccessRulesScreen({super.key,required this.salonId,required this.initialData});
  final String salonId;
  final Map<String,dynamic> initialData;
  @override
  State<CommunityChatGroupAccessRulesScreen> createState()=>_CommunityChatGroupAccessRulesScreenState();
}

class _CommunityChatGroupAccessRulesScreenState extends State<CommunityChatGroupAccessRulesScreen>{
  final _db=Supabase.instance.client;
  bool _countriesEnabled=false,_citiesEnabled=false,_certification=false,_saving=false;
  List<String> _countries=[],_cities=[];
  List<Map<String,dynamic>> _countryOptions=[],_cityOptions=[];
  String? _gender;
  final _minAge=TextEditingController(),_maxAge=TextEditingController();
  Map<String,dynamic> get _rules=>Map<String,dynamic>.from(widget.initialData['access_rules']??{});

  @override
  void initState(){
    super.initState();
    _countriesEnabled=_rules['countries_enabled']==true;
    _citiesEnabled=_rules['cities_enabled']==true;
    _certification=_rules['certification_required']==true;
    _countries=List<String>.from(_rules['allowed_countries']??[]);
    _cities=List<String>.from(_rules['allowed_cities']??[]);
    _gender=_rules['gender_restriction']?.toString();
    _minAge.text=_rules['age_min']?.toString()??'';
    _maxAge.text=_rules['age_max']?.toString()??'';
    _loadOptions();
  }

  @override
  void dispose(){_minAge.dispose();_maxAge.dispose();super.dispose();}

  Future<void> _loadOptions()async{
    try{
      final countries=await _db.from('countries').select('id,nom,code_iso').eq('is_active',true).order('nom');
      final cities=await _db.from('cities').select('id,nom,country_id').eq('is_active',true).order('nom');
      if(!mounted)return;
      setState((){
        _countryOptions=(countries as List).map((e)=>Map<String,dynamic>.from(e)).toList();
        _cityOptions=(cities as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      });
    }catch(e){_toast('Impossible de charger les pays et villes : $e');}
  }

  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}

  Future<void> _choose({required bool countries})async{
    final options=countries?_countryOptions:_cityOptions;
    final selected=(countries?_countries:_cities).toSet();
    final result=await showDialog<Set<String>>(context:context,builder:(ctx){
      final temp=Set<String>.from(selected);
      return StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
        title:Text(countries?'Pays autorisés':'Villes autorisées'),
        content:SizedBox(width:double.maxFinite,height:420,child:options.isEmpty
          ?const Center(child:CircularProgressIndicator())
          :ListView(children:options.map((item){
            final id=item['id'].toString();
            final name=(item['nom']??'').toString();
            final label=countries&&item['code_iso']!=null?'$name (${item['code_iso']})':name;
            return CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,title:Text(label),
              value:temp.contains(id),onChanged:(v)=>setDialog(()=>v==true?temp.add(id):temp.remove(id)));
          }).toList())),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),
          TextButton(onPressed:()=>setDialog(()=>temp.clear()),child:const Text('Tout effacer')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,temp),child:const Text('Valider')),
        ],
      ));
    });
    if(result==null)return;
    setState(() { if (countries) { _countries=result.toList(); } else { _cities=result.toList(); } });
  }

  Future<void> _save()async{
    int? min,max;
    if(_minAge.text.trim().isNotEmpty)min=int.tryParse(_minAge.text.trim());
    if(_maxAge.text.trim().isNotEmpty)max=int.tryParse(_maxAge.text.trim());
    if(_minAge.text.trim().isNotEmpty&&min==null||_maxAge.text.trim().isNotEmpty&&max==null){_toast('Saisis un âge valide.');return;}
    if(min!=null&&(min<13||min>120)||max!=null&&(max<13||max>120)||min!=null&&max!=null&&min>max){_toast('La tranche d’âge doit être comprise entre 13 et 120 ans et rester cohérente.');return;}
    if(_countriesEnabled&&_countries.isEmpty){_toast('Sélectionne au moins un pays ou désactive cette restriction.');return;}
    if(_citiesEnabled&&_cities.isEmpty){_toast('Sélectionne au moins une ville ou désactive cette restriction.');return;}
    setState(()=>_saving=true);
    try{
      await _db.rpc('update_community_chat_group_advanced_settings',params:{
        'p_salon_id':widget.salonId,
        'p_audio_messages_allowed':widget.initialData['audio_messages_allowed']==true,
        'p_countries_enabled':_countriesEnabled,'p_allowed_countries':_countries,
        'p_cities_enabled':_citiesEnabled,'p_allowed_cities':_cities,
        'p_certification_required':_certification,'p_gender_restriction':_gender,
        'p_age_min':min,'p_age_max':max,
      });
      if(mounted)Navigator.pop(context,true);
    }catch(e){_toast('Impossible d’enregistrer les conditions : $e');}
    finally{if(mounted)setState(()=>_saving=false);}
  }

  String _names(List<String> ids,List<Map<String,dynamic>> options){
    final names=options.where((e)=>ids.contains(e['id'].toString())).map((e)=>e['nom'].toString()).toList();
    return names.isEmpty?'Aucune sélection':names.join(', ');
  }

  @override
  Widget build(BuildContext context){
    final c=Theme.of(context).colorScheme;
    return Scaffold(appBar:AppBar(title:const Text('Conditions d’accès')),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,28),children:[
        Text('Définis les profils autorisés à rejoindre cette discussion. Les restrictions ne peuvent pas être moins strictes que celles de la communauté.',style:Theme.of(context).textTheme.bodyMedium?.copyWith(color:c.onSurfaceVariant)),
        const SizedBox(height:16),
        Card(child:Column(children:[
          SwitchListTile(value:_countriesEnabled,title:const Text('Limiter par pays'),subtitle:const Text('Seuls les membres des pays sélectionnés pourront rejoindre le salon'),onChanged:(v)=>setState(()=>_countriesEnabled=v)),
          if(_countriesEnabled)ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18),title:Text(_countries.isEmpty?'Choisir les pays':_names(_countries,_countryOptions),maxLines:3,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right),onTap:()=>_choose(countries:true)),
          const Divider(height:1),
          SwitchListTile(value:_citiesEnabled,title:const Text('Limiter par ville'),subtitle:const Text('Seuls les membres des villes sélectionnées pourront rejoindre le salon'),onChanged:(v)=>setState(()=>_citiesEnabled=v)),
          if(_citiesEnabled)ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18),title:Text(_cities.isEmpty?'Choisir les villes':_names(_cities,_cityOptions),maxLines:3,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right),onTap:()=>_choose(countries:false)),
        ])),
        const SizedBox(height:12),
        Card(child:Column(children:[
          SwitchListTile(value:_certification,title:const Text('Certification obligatoire'),subtitle:const Text('Réserver le salon aux profils certifiés'),onChanged:(v)=>setState(()=>_certification=v)),
          const Divider(height:1),
          ListTile(title:const Text('Restriction de genre'),subtitle:const Text(''),
            trailing:DropdownButton<String?>(value:_gender,hint:const Text('Aucune'),underline:const SizedBox.shrink(),
              items:const[DropdownMenuItem<String?>(value:null,child:Text('Aucune')),DropdownMenuItem<String?>(value:'homme',child:Text('Hommes')),DropdownMenuItem<String?>(value:'femme',child:Text('Femmes'))],
              onChanged:(v)=>setState(()=>_gender=v))),
          const Divider(height:1),
          Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Tranche d’âge',style:TextStyle(fontWeight:FontWeight.w600)),
            const SizedBox(height:10),
            Row(children:[
              Expanded(child:TextField(controller:_minAge,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Âge minimum',border:OutlineInputBorder()))),
              const SizedBox(width:12),
              Expanded(child:TextField(controller:_maxAge,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Âge maximum',border:OutlineInputBorder()))),
            ]),
          ])),
        ])),
        const SizedBox(height:22),
        FilledButton(onPressed:_saving?null:_save,child:_saving?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('Enregistrer les conditions')),
      ]));
  }
}
