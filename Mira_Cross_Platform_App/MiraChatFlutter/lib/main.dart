import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

const bg = Color(0xFF212121), panel = Color(0xFF171717), green = Color(0xFF19C37D);

void main() => runApp(const MiraApp());

class MiraApp extends StatelessWidget {
  const MiraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mira', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: green, surface: bg),
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF303030),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
    home: const MiraHome());
}

class MiraHome extends StatefulWidget {
  const MiraHome({super.key});
  @override State<MiraHome> createState() => _MiraHomeState();
}

class _MiraHomeState extends State<MiraHome> {
  final input = TextEditingController(), scroll = TextEditingController();
  final listScroll = ScrollController();
  final speech = stt.SpeechToText();
  final tts = FlutterTts();
  final messages = <Map<String,String>>[];
  SharedPreferences? prefs;
  String url = 'http://127.0.0.1:8765', key = '', status = 'ချိတ်ဆက်မထားပါ';
  bool connected = false, busy = false, voice = false, autoSpeak = false;
  Timer? pollTimer, listenTimer;

  @override void initState() {
    super.initState();
    tts.setLanguage('my-MM'); tts.awaitSpeakCompletion(true); _load();
  }
  @override void dispose() {
    pollTimer?.cancel(); listenTimer?.cancel(); speech.cancel(); tts.stop();
    input.dispose(); scroll.dispose(); listScroll.dispose(); super.dispose();
  }
  Uri uri(String path) => Uri.parse(url.replaceFirst(RegExp(r'/+$'), '') + path);
  Map<String,String> get headers => {'X-Mira-Token':key,'Content-Type':'application/json; charset=utf-8'};
  Future<Map<String,dynamic>> decode(http.Response r) async {
    dynamic d;
    try { d = jsonDecode(utf8.decode(r.bodyBytes)); } catch (_) { throw Exception('Server response မဖတ်နိုင်ပါ။'); }
    if (d is! Map<String,dynamic>) throw Exception('Server response format မှားနေပါတယ်။');
    if (r.statusCode < 200 || r.statusCode > 299) throw Exception((d['error'] ?? 'HTTP ' + r.statusCode.toString()).toString());
    return d;
  }
  Future<Map<String,dynamic>> get(String path) async =>
    decode(await http.get(uri(path),headers:headers).timeout(const Duration(seconds:10)));
  Future<Map<String,dynamic>> post(String path, Map<String,dynamic> body) async =>
    decode(await http.post(uri(path),headers:headers,body:jsonEncode(body)).timeout(const Duration(minutes:5)));

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    url = prefs!.getString('mira_url') ?? url;
    key = prefs!.getString('mira_key') ?? '';
    autoSpeak = prefs!.getBool('mira_auto_speak') ?? false;
    try {
      final saved = jsonDecode(prefs!.getString('mira_messages') ?? '[]');
      if (saved is List) messages.addAll(saved.whereType<Map>().map((m)=>Map<String,String>.from(m)));
    } catch (_) {}
    if (!mounted) return; setState((){});
    if (key.isEmpty) { WidgetsBinding.instance.addPostFrameCallback((_)=>settings()); }
    else { await connect(show:false); }
  }
  Future<void> connect({bool show=true}) async {
    if (key.isEmpty) { if(show) await settings(); return; }
    setState(()=>status='Mira ကို ချိတ်ဆက်နေသည်…');
    try {
      final d=await get('/api/status');
      if(!mounted)return;
      setState(()=>_applyState((d['state']??'starting').toString()));
      pollTimer?.cancel();
      pollTimer=Timer.periodic(const Duration(seconds:3),(_)=>refresh());
    } catch(e) {
      if(!mounted)return; setState(()=>_applyState('disconnected'));
      if(show) snack('Mira server ကို မချိတ်နိုင်ပါ။ URL နဲ့ key ကိုစစ်ပါ။');
    }
  }
  void _applyState(String s) {
    connected = s == 'ready';
    status = s == 'ready' ? 'Mira အသင့်ဖြစ်ပြီ' : s == 'thinking' ? 'Mira စဉ်းစားနေသည်…'
      : s == 'starting' ? 'Mira စတင်နေသည်…' : 'Mira server ချိတ်ဆက်မရပါ';
  }
  Future<void> refresh() async {
    try { final d=await get('/api/status'); if(mounted)setState(()=>_applyState((d['state']??'starting').toString())); }
    catch(_){ if(mounted)setState(()=>_applyState('disconnected')); }
  }
  Future<void> settings() async {
    final u=TextEditingController(text:url), k=TextEditingController(text:key);
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Mira ချိတ်ဆက်မှု'),
      content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('PC ပေါ်မှာ Mira server ကိုဖွင့်ထားပါ။ ဖုန်းမှာသုံးလျှင် terminal ထဲက PHONE_URL ကိုထည့်ပါ။',style:TextStyle(color:Colors.white70,height:1.5)),
        const SizedBox(height:14),
        TextField(controller:u,decoration:const InputDecoration(labelText:'Server URL',hintText:'http://192.168.1.10:8765')),
        const SizedBox(height:10),
        TextField(controller:k,obscureText:true,decoration:const InputDecoration(labelText:'Mira Access Key')),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('ပိတ်မည်')),
        FilledButton(onPressed:() async {
          if(!u.text.trim().startsWith('http')||k.text.trim().isEmpty){snack('URL နဲ့ Access Key ထည့်ပါ။');return;}
          url=u.text.trim().replaceFirst(RegExp(r'/+$'),''); key=k.text.trim();
          await prefs?.setString('mira_url',url); await prefs?.setString('mira_key',key);
          if(ctx.mounted)Navigator.pop(ctx); await connect();
        },child:const Text('ချိတ်ဆက်မည်')),
      ]));
    u.dispose(); k.dispose();
  }
  Future<void> saveMessages()=>prefs?.setString('mira_messages',jsonEncode(messages)) ?? Future.value();
  void add(String role,String content) {
    setState(()=>messages.add({'role':role,'content':content}));
    saveMessages();
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(listScroll.hasClients)listScroll.animateTo(listScroll.position.maxScrollExtent,duration:const Duration(milliseconds:200),curve:Curves.easeOut);
    });
  }
  Future<void> send({String? text,bool fromVoice=false}) async {
    final v=(text??input.text).trim(); if(v.isEmpty||busy)return;
    if(!connected){await settings();if(!connected)return;}
    input.clear(); setState(()=>busy=true); add('user',v); setState(()=>status='Mira စဉ်းစားနေသည်…');
    try {
      final d=await post('/api/chat',{'message':v});
      final answer=(d['reply']??'').toString();
      add('assistant',answer.isEmpty?'အဖြေမရရှိသေးပါ။':answer);
      if(fromVoice||autoSpeak)await speak(answer);
    } catch(e) { add('assistant','Mira နဲ့ချိတ်ဆက်မှုမှာ ပြဿနာရှိပါတယ်။\n'+e.toString()); }
    finally {
      if(mounted)setState(()=>busy=false); await refresh();
      if(fromVoice&&voice){listenTimer?.cancel();listenTimer=Timer(const Duration(milliseconds:600),listen);}
    }
  }
  Future<void> newChat() async {
    if(busy)return;
    if(connected) {
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('စကားဝိုင်းအသစ်'),content:const Text('Mira session ကို ပြန်စမလား?'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('မလုပ်တော့ပါ')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ပြန်စမည်'))]));
      if(yes!=true)return;
      setState(()=>busy=true);
      try{await post('/api/reset',{});}catch(e){snack('Session ပြန်စမရပါ: '+e.toString());setState(()=>busy=false);return;}
    }
    setState(()=>messages.clear()); await saveMessages(); if(mounted)setState(()=>busy=false); await refresh();
  }
  Future<void> toggleVoice() async {
    if(voice){setState(()=>voice=false);listenTimer?.cancel();await speech.stop();await tts.stop();snack('Voice mode ပိတ်လိုက်ပါပြီ။');return;}
    if(!connected){await settings();if(!connected)return;}
    final ok=await speech.initialize(
      onStatus:(s){if(voice&&s=='notListening'&&!busy){listenTimer?.cancel();listenTimer=Timer(const Duration(milliseconds:500),listen);}},
      onError:(e){if(e.errorMsg.contains('permission')||e.errorMsg.contains('not_available')){if(mounted)setState(()=>voice=false);snack('Microphone permission ကိုစစ်ပါ။');}});
    if(!ok){snack('ဒီ device မှာ speech recognition မရနိုင်ပါ။');return;}
    setState(()=>voice=true); await listen(); snack('စကားပြောနိုင်ပါပြီ။ ပိတ်ရန် mic ကိုထပ်နှိပ်ပါ။');
  }
  Future<void> listen() async {
    if(!voice||busy||speech.isListening||!mounted)return;
    try {
      final locales=await speech.locales(); String? locale;
      for(final l in locales){if(l.localeId.toLowerCase()=='my_mm'||l.localeId.toLowerCase()=='my-mm'){locale=l.localeId;break;}}
      await speech.listen(localeId:locale,listenFor:const Duration(seconds:45),pauseFor:const Duration(seconds:4),
        onResult:(r){if(r.finalResult&&voice&&!busy&&r.recognizedWords.trim().isNotEmpty)send(text:r.recognizedWords.trim(),fromVoice:true);});
    }catch(e){if(mounted)setState(()=>voice=false);snack('Microphone မစနိုင်ပါ: '+e.toString());}
  }
  Future<void> speak(String text) async {
    try{await tts.stop();await tts.setLanguage('my-MM');await tts.speak(text);}
    catch(_){snack('Device မှာ မြန်မာ TTS voice ရှိမရှိ စစ်ပါ။');}
  }
  void snack(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}
  Widget bubble(Map<String,String> m){
    final user=m['role']=='user';
    return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:820),
      child:Container(margin:const EdgeInsets.symmetric(vertical:7,horizontal:12),padding:const EdgeInsets.all(14),
        decoration:BoxDecoration(color:user?const Color(0xFF343541):bg,borderRadius:BorderRadius.circular(15),border:user?null:Border.all(color:Colors.white10)),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          CircleAvatar(radius:15,backgroundColor:user?Colors.white24:green,child:Text(user?'B':'M',style:TextStyle(color:user?Colors.white:Colors.black,fontWeight:FontWeight.bold))),
          const SizedBox(width:10),Flexible(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(user?'Boss':'Mira',style:const TextStyle(color:Colors.white70,fontSize:12,fontWeight:FontWeight.w600)),
            const SizedBox(height:5),SelectableText(m['content']??'',style:const TextStyle(fontSize:15,height:1.65)),
            if(!user)Align(alignment:Alignment.centerRight,child:IconButton(tooltip:'အသံနဲ့ဖတ်မယ်',visualDensity:VisualDensity.compact,onPressed:()=>speak(m['content']??''),icon:const Icon(Icons.volume_up_outlined,size:19))),
          ])),
        ]))));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(leading:Builder(builder:(ctx)=>IconButton(icon:const Icon(Icons.menu),onPressed:()=>Scaffold.of(ctx).openDrawer())),
      title:const Row(children:[Icon(Icons.auto_awesome,color:green),SizedBox(width:9),Text('Mira',style:TextStyle(fontWeight:FontWeight.bold))]),
      actions:[IconButton(tooltip:'New chat',onPressed:newChat,icon:const Icon(Icons.add_comment_outlined)),IconButton(tooltip:'Connection',onPressed:settings,icon:const Icon(Icons.settings_outlined))]),
    drawer:Drawer(backgroundColor:panel,child:SafeArea(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Padding(padding:EdgeInsets.all(22),child:Row(children:[Icon(Icons.auto_awesome,color:green,size:28),SizedBox(width:12),Text('Mira',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:OutlinedButton.icon(onPressed:newChat,icon:const Icon(Icons.add),label:const Text('New chat'))),
      const Padding(padding:EdgeInsets.fromLTRB(20,25,20,10),child:Text('CURRENT CHAT',style:TextStyle(color:Colors.white54,fontSize:11))),
      const ListTile(leading:Icon(Icons.chat_bubble_outline),title:Text('Current conversation')),
      const Spacer(),
      SwitchListTile(value:autoSpeak,activeColor:green,title:const Text('အဖြေကို အသံဖတ်မယ်'),onChanged:(v)async{setState(()=>autoSpeak=v);await prefs?.setBool('mira_auto_speak',v);}),
      ListTile(leading:Icon(voice?Icons.mic:Icons.mic_none),title:Text(voice?'Voice mode ပိတ်မည်':'Voice mode ဖွင့်မည်'),onTap:toggleVoice),
      ListTile(leading:const Icon(Icons.settings_outlined),title:const Text('Connection settings'),onTap:settings),
      Padding(padding:const EdgeInsets.all(18),child:Text(status,style:TextStyle(color:connected?green:Colors.orangeAccent,fontSize:12))),
    ]))),
    body:Column(children:[
      Expanded(child:messages.isEmpty?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Container(width:58,height:58,decoration:BoxDecoration(color:green,borderRadius:BorderRadius.circular(20)),child:const Icon(Icons.auto_awesome,color:Colors.black,size:30)),
        const SizedBox(height:20),const Text('မင်္ဂလာပါ Boss',style:TextStyle(fontSize:29,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
        const SizedBox(height:12),const Text('Mira ကို မေးပါ၊ ဒါမှမဟုတ် microphone ကိုနှိပ်ပြီး အသံနဲ့ပြောပါ။',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.7)),
      ])) : ListView.builder(controller:listScroll,padding:const EdgeInsets.symmetric(vertical:12),itemCount:messages.length+(busy?1:0),itemBuilder:(ctx,i)=>i==messages.length?const Padding(padding:EdgeInsets.all(18),child:Row(children:[SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2)),SizedBox(width:12),Text('Mira စဉ်းစားနေသည်…')])):bubble(messages[i]))),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(10,8,10,12),child:Column(children:[
        if(voice)const Padding(padding:EdgeInsets.only(bottom:7),child:Text('Voice conversation ဖွင့်ထားသည်',style:TextStyle(color:green))),
        ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          IconButton.filledTonal(onPressed:toggleVoice,icon:Icon(voice?Icons.mic:Icons.mic_none),style:IconButton.styleFrom(backgroundColor:voice?green:const Color(0xFF303030),foregroundColor:voice?Colors.black:Colors.white,minimumSize:const Size(46,46))),
          const SizedBox(width:7),Expanded(child:TextField(controller:input,minLines:1,maxLines:5,enabled:!busy,textInputAction:TextInputAction.send,onSubmitted:(_)=>send(),decoration:InputDecoration(hintText:voice?'ပြောပါ၊ သို့မဟုတ် ရိုက်ထည့်ပါ…':'Mira ကို မေးလိုက်ပါ…',contentPadding:const EdgeInsets.fromLTRB(16,13,16,13)))),
          const SizedBox(width:7),IconButton.filled(onPressed:busy?null:send,icon:const Icon(Icons.arrow_upward),style:IconButton.styleFrom(backgroundColor:green,foregroundColor:Colors.black,minimumSize:const Size(46,46))),
        ])),const SizedBox(height:7),Text(voice?'Mira ပြန်ဖြေပြီးရင် ဆက်နားထောင်မယ်။':'Mira runs on your PC · Enter to send',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white38,fontSize:10)),
      ]))),
    ]),
  );
}
