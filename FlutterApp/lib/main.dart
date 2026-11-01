import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api/studygo_api.dart';

const apiBaseUrl = String.fromEnvironment('STUDYGO_API_URL', defaultValue: 'https://api.example.com');
void main() => runApp(const StudyGoApp());

class StudyGoApp extends StatelessWidget {
  const StudyGoApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'StudyGo', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0d9488)), useMaterial3: true),
    home: const AppRoot(),
  );
}
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override State<AppRoot> createState() => _AppRootState();
}
class _AppRootState extends State<AppRoot> {
  late final StudyGoApi api = StudyGoApi(baseUrl: apiBaseUrl);
  bool loading = true;
  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    await api.restore();
    if (!apiBaseUrl.contains('example.com')) { try { await api.resume(); } catch (_) {} }
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (apiBaseUrl.contains('example.com')) return const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24),child:Text('Atur STUDYGO_API_URL saat build: --dart-define=STUDYGO_API_URL=https://api.domainanda.id'))));
    return api.user != null ? StudyHome(api:api,onLogout:()=>setState((){})) : LoginPage(api:api,onLogin:()=>setState((){}));
  }
}
class LoginPage extends StatefulWidget {
  const LoginPage({super.key,required this.api,required this.onLogin});
  final StudyGoApi api; final VoidCallback onLogin;
  @override State<LoginPage> createState()=>_LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email=TextEditingController(),password=TextEditingController();
  bool busy=false;String error='';
  Future<void> login() async {
    setState((){busy=true;error='';});
    try{await widget.api.login(email.text.trim(),password.text);widget.onLogin();}
    catch(e){setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.school,size:64,color:Color(0xff0d9488)),const SizedBox(height:12),Text('StudyGo',style:Theme.of(context).textTheme.headlineLarge),const SizedBox(height:24),
    TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',border:OutlineInputBorder())),
    const SizedBox(height:12),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),
    if(error.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(error,style:const TextStyle(color:Colors.red))),
    const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:login,child:busy?const CircularProgressIndicator():const Text('Masuk'))),
    TextButton(onPressed:busy?null:()async{try{await widget.api.forgotPassword(email.text.trim());if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Jika akun terdaftar, tautan reset password akan dikirim.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('Lupa password?')),
  ])))));
}
class StudyHome extends StatefulWidget {
  const StudyHome({super.key,required this.api,required this.onLogout});
  final StudyGoApi api;final VoidCallback onLogout;
  @override State<StudyHome> createState()=>_StudyHomeState();
}
class _StudyHomeState extends State<StudyHome> {
  int tab=0;String output='';bool busy=false;
  final question=TextEditingController(),task=TextEditingController();
  Future<void> run(Future<void> Function() action) async {
    setState(()=>busy=true);
    try{await action();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final pages=[_tutor(),_planner(),_materials(),_notifications()];
    return Scaffold(appBar:AppBar(title:const Text('StudyGo'),actions:[IconButton(onPressed:()=>run(()async{await widget.api.logout();widget.onLogout();}),icon:const Icon(Icons.logout))]),
      body:busy?const Center(child:CircularProgressIndicator()):pages[tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
        NavigationDestination(icon:Icon(Icons.auto_awesome),label:'AI Tutor'),NavigationDestination(icon:Icon(Icons.checklist),label:'Planner'),NavigationDestination(icon:Icon(Icons.folder),label:'Materi'),NavigationDestination(icon:Icon(Icons.notifications),label:'Notifikasi')]));
  }
  Widget _tutor()=>ListView(padding:const EdgeInsets.all(16),children:[
    FutureBuilder<Map<String,dynamic>>(future:widget.api.quota(),builder:(c,s)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Text(s.hasData?'Sisa pertanyaan hari ini: \${s.data!['questionsRemaining']}':'Memuat kuota...')))),
    TextField(controller:question,minLines:3,maxLines:6,decoration:const InputDecoration(labelText:'Tanyakan materi atau soal',border:OutlineInputBorder())),
    const SizedBox(height:12),FilledButton.icon(onPressed:()=>run(()async{output=await widget.api.ask(question.text);}),icon:const Icon(Icons.send),label:const Text('Tanya AI')),
    OutlinedButton.icon(onPressed:()=>run(()async{final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:85);if(x!=null)output=await widget.api.solveImage(File(x.path),x.mimeType??'image/jpeg');}),icon:const Icon(Icons.image_search),label:const Text('Foto soal')),
    if(output.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(16),child:SelectableText(output))),
  ]);
  Widget _planner()=>ListView(padding:const EdgeInsets.all(16),children:[
    Row(children:[Expanded(child:TextField(controller:task,decoration:const InputDecoration(labelText:'Tugas baru',border:OutlineInputBorder()))),IconButton(onPressed:()=>run(()async{await widget.api.createTask(task.text);task.clear();}),icon:const Icon(Icons.add_circle))]),
    const SizedBox(height:12),FutureBuilder<List<dynamic>>(future:widget.api.tasks(),builder:(c,s)=>s.hasError?Text('\${s.error}'):Column(children:(s.data??[]).map((e)=>ListTile(leading:const Icon(Icons.task_alt),title:Text(e['title'].toString()),subtitle:Text(e['status'].toString()))).toList())),
  ]);
  Widget _materials()=>ListView(padding:const EdgeInsets.all(16),children:[
    FilledButton.icon(onPressed:()=>run(()async{final r=await FilePicker.platform.pickFiles(withData:true,type:FileType.custom,allowedExtensions:['pdf','docx','pptx','mp4','webm','jpg','jpeg','png','webp']);if(r!=null)await widget.api.uploadMaterial(r.files.single);}),icon:const Icon(Icons.upload_file),label:const Text('Upload PDF / DOCX / PPTX / Video / Gambar')),
    FutureBuilder<List<dynamic>>(future:widget.api.materials(),builder:(c,s)=>s.hasError?Text('\${s.error}'):Column(children:(s.data??[]).map((e)=>ListTile(leading:const Icon(Icons.insert_drive_file),title:Text(e['title'].toString()),subtitle:Text('\${e['material_type']} • \${e['original_name']}'))).toList())),
  ]);
  Widget _notifications()=>FutureBuilder<List<dynamic>>(future:widget.api.notifications(),builder:(c,s)=>s.hasError?Text('\${s.error}'):ListView(children:(s.data??[]).map((e)=>ListTile(leading:const Icon(Icons.notifications_active),title:Text(e['title'].toString()),subtitle:Text(e['body'].toString()),onTap:()=>run(()async{await widget.api.markNotificationRead(int.parse(e['id'].toString()));setState((){});})).toList()));
}
