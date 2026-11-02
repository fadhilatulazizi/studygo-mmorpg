import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api/studygo_api.dart';

const apiBaseUrl = String.fromEnvironment('STUDYGO_API_URL', defaultValue: 'https://api.studygo.turaja.id');
const teal = Color(0xFF0D9488);
const pageBg = Color(0xFFF5F8F7);

void main() => runApp(const StudyGoApp());

class StudyGoApp extends StatefulWidget {
  const StudyGoApp({super.key});
  @override State<StudyGoApp> createState() => _StudyGoAppState();
}

class _StudyGoAppState extends State<StudyGoApp> {
  ThemeMode mode = ThemeMode.light;
  ThemeData makeTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: teal, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF101A22) : pageBg,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF101A22) : pageBg,
        foregroundColor: dark ? Colors.white : const Color(0xFF172B3A),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF192630) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF22323D) : const Color(0xFFF1F5F4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: teal, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: teal, foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: dark ? const Color(0xFF192630) : Colors.white,
        indicatorColor: teal.withValues(alpha: .13),
      ),
    );
  }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'StudyGo', debugShowCheckedModeBanner: false,
    theme: makeTheme(Brightness.light), darkTheme: makeTheme(Brightness.dark), themeMode: mode,
    home: AppRoot(isDark: mode == ThemeMode.dark, toggleTheme: () => setState(() => mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light)),
  );
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.isDark, required this.toggleTheme});
  final bool isDark; final VoidCallback toggleTheme;
  @override State<AppRoot> createState() => _AppRootState();
}
class _AppRootState extends State<AppRoot> {
  late final StudyGoApi api = StudyGoApi(baseUrl: apiBaseUrl);
  bool loading = true;
  bool forceLogin = false;
  @override void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    await api.restore();
    try { await api.resume(); } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (api.user != null) return StudyHome(api: api, onLogout: () => setState(() {}), onAccount: () => setState(() => forceLogin = true), isDark: widget.isDark, toggleTheme: widget.toggleTheme);
    if (api.isGuest && !forceLogin) return StudyHome(api: api, onLogout: () => setState(() {}), onAccount: () => setState(() => forceLogin = true), isDark: widget.isDark, toggleTheme: widget.toggleTheme);
    return LoginPage(api: api, onLogin: () => setState(() => forceLogin = false), isDark: widget.isDark, toggleTheme: widget.toggleTheme);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, required this.onLogin, required this.isDark, required this.toggleTheme});
  final StudyGoApi api; final VoidCallback onLogin; final bool isDark; final VoidCallback toggleTheme;
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController();
  bool busy = false, registering = false, hidePassword = true;
  String error = '';
  @override void dispose() { name.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  Future<void> submit() async {
    setState(() { busy = true; error = ''; });
    try {
      if (registering) {
        if (name.text.trim().isEmpty || password.text.length < 10) throw Exception('Nama wajib diisi dan password minimal 10 karakter.');
        await widget.api.register(name.text.trim(), email.text.trim(), password.text);
        if (!mounted) return;
        setState(() => registering = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akun berhasil dibuat. Silakan masuk.')));
      } else {
        await widget.api.login(email.text.trim(), password.text);
        widget.onLogin();
      }
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(body: SafeArea(child: Stack(children: [
      Positioned(top: -90, right: -70, child: Container(width: 230, height: 230, decoration: BoxDecoration(color: teal.withValues(alpha: .09), shape: BoxShape.circle))),
      Align(alignment: Alignment.topRight, child: IconButton(onPressed: widget.toggleTheme, icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode))),
      Center(child: SingleChildScrollView(padding: const EdgeInsets.all(26), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 72, height: 72, alignment: Alignment.center, decoration: BoxDecoration(color: teal.withValues(alpha: .12), borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.school_rounded, color: teal, size: 38)),
        const SizedBox(height: 24),
        Text(registering ? 'Mulai perjalananmu.' : 'Belajar lebih terarah.', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.7)),
        const SizedBox(height: 8),
        Text('Teman belajar digital untuk memahami materi dan mengatur tugas.', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45)),
        const SizedBox(height: 26),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          if (registering) ...[TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama lengkap', prefixIcon: Icon(Icons.person_outline))), const SizedBox(height: 13)],
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
          const SizedBox(height: 13),
          TextField(controller: password, obscureText: hidePassword, decoration: InputDecoration(labelText: 'Password', helperText: registering ? 'Minimal 10 karakter' : null, prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => hidePassword = !hidePassword), icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
          if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit, child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(registering ? 'Buat akun' : 'Masuk'))),
          TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = ''; }), child: Text(registering ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar')),
          if (!registering) TextButton(onPressed: busy ? null : () async {
            if (email.text.trim().isEmpty) { setState(() => error = 'Masukkan email terlebih dahulu.'); return; }
            final messenger = ScaffoldMessenger.of(context);
            try { await widget.api.forgotPassword(email.text.trim()); if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Jika akun terdaftar, tautan reset password akan dikirim.'))); }
            catch (e) { if (mounted) setState(() => error = e.toString()); }
          }, child: const Text('Lupa password?')),
          const SizedBox(height: 6),
          OutlinedButton.icon(onPressed: busy ? null : () async { await widget.api.startGuest(); widget.onLogin(); }, icon: const Icon(Icons.explore_outlined), label: const Text('Coba tanpa akun')),
        ]))),
        const SizedBox(height: 20),
        Text('STUDYGO  •  BELAJAR DENGAN LEBIH BAIK', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
      ])))),
    ])));
  }
}

class StudyHome extends StatefulWidget {
  const StudyHome({super.key, required this.api, required this.onLogout, required this.onAccount, required this.isDark, required this.toggleTheme});
  final StudyGoApi api; final VoidCallback onLogout; final VoidCallback onAccount; final bool isDark; final VoidCallback toggleTheme;
  @override State<StudyHome> createState() => _StudyHomeState();
}
class _StudyHomeState extends State<StudyHome> {
  int tab = 0; bool busy = false, loading = true;
  String answer = '';
  Map<String, dynamic>? quota;
  List<dynamic> tasks = [], materials = [], notifications = [];
  final question = TextEditingController(), taskInput = TextEditingController();
  @override void initState() { super.initState(); loadData(); }
  @override void dispose() { question.dispose(); taskInput.dispose(); super.dispose(); }
  Future<void> loadData() async {
    if (widget.api.isGuest) {
      try {
        final local = await widget.api.tasks();
        quota = await widget.api.quota();
        if (mounted) setState(() { tasks = local; loading = false; });
      } catch (_) { if (mounted) setState(() => loading = false); }
      return;
    }
    try {
      final r = await Future.wait([widget.api.quota(), widget.api.tasks(), widget.api.materials(), widget.api.notifications()]);
      if (!mounted) return;
      setState(() { quota = r[0] as Map<String,dynamic>; tasks = r[1] as List; materials = r[2] as List; notifications = r[3] as List; loading = false; });
    } catch (_) { if (mounted) setState(() => loading = false); }
  }
  Future<void> run(Future<void> Function() action) async {
    if (busy) return; setState(() => busy = true);
    try { await action(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> ask() async {
    if (question.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tuliskan pertanyaan terlebih dahulu.'))); return; }
    await run(() async {
      final value = await widget.api.ask(question.text.trim());
      if (mounted) setState(() => answer = value);
      if (widget.api.isGuest) quota = await widget.api.quota();
      if (mounted) setState(() {});
    });
  }
  Future<void> photoQuestion() async {
    if (widget.api.isGuest) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Analisis foto memerlukan akun. Masuk atau daftar terlebih dahulu.'))); widget.onAccount(); return; }
    await run(() async {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1800);
      if (image == null) return;
      final value = await widget.api.solveImage(File(image.path), image.mimeType ?? 'image/jpeg');
      if (mounted) setState(() => answer = value);
    });
  }
  Future<void> addTask() async {
    if (taskInput.text.trim().isEmpty) return;
    await run(() async {
      await widget.api.createTask(taskInput.text.trim());
      tasks = await widget.api.tasks();
      taskInput.clear(); if (mounted) setState(() {});
    });
  }
  Future<void> upload() async {
    if (widget.api.isGuest) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penyimpanan materi cloud memerlukan akun.'))); widget.onAccount(); return; }
    await run(() async {
      final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['pdf','docx','pptx','mp4','webm','jpg','jpeg','png','webp']);
      if (result == null) return;
      await widget.api.uploadMaterial(result.files.single);
      materials = await widget.api.materials(); if (mounted) setState(() {});
    });
  }
  Future<void> logout() async { await run(() async { await widget.api.logout(); widget.onLogout(); }); }

  @override Widget build(BuildContext context) {
    final pages = [dashboard(), tutor(), planner(), library(), inbox()];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [Container(width: 35, height: 35, decoration: BoxDecoration(color: teal.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.school_rounded, color: teal, size: 21)), const SizedBox(width: 10), const Text('StudyGo', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [if (widget.api.isGuest) IconButton(tooltip: 'Masuk atau daftar', onPressed: widget.onAccount, icon: const Icon(Icons.account_circle_outlined)), IconButton(tooltip: 'Ganti tema', onPressed: widget.toggleTheme, icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined)), IconButton(tooltip: 'Keluar', onPressed: busy ? null : logout, icon: const Icon(Icons.logout_rounded)), const SizedBox(width: 5)],
      ),
      body: Stack(children: [IndexedStack(index: tab, children: pages), if (busy) Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .07), child: const Center(child: CircularProgressIndicator())))]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Beranda'),
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Tutor AI'),
        NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Planner'),
        NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder), label: 'Materi'),
        NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Inbox'),
      ]),
    );
  }

  Widget pageTitle(String title, String sub) => Padding(padding: const EdgeInsets.only(bottom: 17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
    const SizedBox(height: 5), Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
  ]));
  Widget section(String title, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    const SizedBox(height: 3), Text(sub, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
  Widget dashboard() {
    final displayName = widget.api.user?['displayName']?.toString() ?? 'Pelajar';
    return RefreshIndicator(onRefresh: loadData, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
      Text('Halo, $displayName 👋', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), Text('Siap membuat hari ini lebih produktif?', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(21), decoration: BoxDecoration(borderRadius: BorderRadius.circular(23), gradient: const LinearGradient(colors: [Color(0xFF087F76), Color(0xFF13A58F)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: teal.withValues(alpha: .18), blurRadius: 20, offset: const Offset(0,8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('Ruang belajarmu', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)), child: const Text('STUDYGO AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)))]),
        const SizedBox(height: 13), const Text('Belajar sedikit demi sedikit, hasilkan kemajuan besar.', style: TextStyle(color: Colors.white, fontSize: 21, height: 1.25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16), Row(children: [const Icon(Icons.auto_awesome, color: Colors.white, size: 18), const SizedBox(width: 8), Text(widget.api.isGuest ? 'Mode tamu • kuota AI 5 pertanyaan/hari' : (loading ? 'Memuat kuota AI…' : 'Sisa pertanyaan hari ini: ${quota?['questionsRemaining'] ?? '—'}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 17), SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF087F76)), onPressed: () => setState(() => tab = 1), child: const Text('Mulai belajar'))),
      ])),
      const SizedBox(height: 23), section('Mulai belajar', 'Pilih aktivitasmu'), const SizedBox(height: 11),
      Row(children: [Expanded(child: quick(Icons.auto_awesome, 'Tanya AI', 'Pahami materi', teal, 1)), const SizedBox(width: 11), Expanded(child: quick(Icons.checklist_rounded, 'Atur tugas', 'Kelola target', const Color(0xFF7180DE), 2))]),
      const SizedBox(height: 11), Row(children: [Expanded(child: quick(Icons.folder_copy_outlined, 'Materi', 'Simpan file', const Color(0xFFE49A42), 3)), const SizedBox(width: 11), Expanded(child: quick(Icons.notifications_none, 'Notifikasi', 'Lihat kabar', const Color(0xFFCC718B), 4))]),
      const SizedBox(height: 23), section('Ringkasan', 'Aktivitas belajarmu'), const SizedBox(height: 11),
      Row(children: [Expanded(child: stat(Icons.task_alt, tasks.length, 'Tugas')), const SizedBox(width: 9), Expanded(child: stat(Icons.folder_outlined, materials.length, 'Materi')), const SizedBox(width: 9), Expanded(child: stat(Icons.notifications_none, notifications.length, 'Inbox'))]),
      if (tasks.isNotEmpty) ...[const SizedBox(height: 22), section('Tugas terbaru', 'Tetap selangkah lebih maju'), const SizedBox(height: 8), ...tasks.take(3).map(taskTile)],
    ]));
  }
  Widget quick(IconData icon, String title, String sub, Color color, int destination) => Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => setState(() => tab = destination), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
    Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)),
    const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(sub, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
  ]))));
  Widget stat(IconData icon, int value, String label) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6), child: Column(children: [Icon(icon, color: teal, size: 19), const SizedBox(height: 7), Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)), Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))])));
  Widget tutor() => ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 28), children: [
    pageTitle('Tutor AI', 'Tanyakan materi atau kirim foto soal.'),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: teal.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_awesome, color: teal)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('StudyGo AI siap membantu', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('Sisa pertanyaan: ${quota?['questionsRemaining'] ?? '—'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))]))]))),
    const SizedBox(height: 14), TextField(controller: question, minLines: 4, maxLines: 7, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Contoh: Jelaskan hukum Newton dengan contoh sederhana…', alignLabelWithHint: true)),
    const SizedBox(height: 11), FilledButton.icon(onPressed: busy ? null : ask, icon: const Icon(Icons.send_rounded), label: const Text('Kirim pertanyaan')),
    const SizedBox(height: 9), OutlinedButton.icon(onPressed: busy ? null : photoQuestion, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Tanyakan dari foto soal')),
    if (answer.isNotEmpty) ...[const SizedBox(height: 20), section('Jawaban StudyGo AI', 'Baca dan pahami langkahnya'), const SizedBox(height: 9), Card(child: Padding(padding: const EdgeInsets.all(18), child: SelectableText(answer, style: const TextStyle(height: 1.65, fontSize: 15))))],
  ]);
  Widget planner() => RefreshIndicator(onRefresh: () async { tasks = await widget.api.tasks(); if (mounted) setState(() {}); }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20,14,20,28), children: [
    pageTitle('Planner belajar', 'Atur tugas agar belajar terasa lebih ringan.'),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Tambah tugas', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 11),
      TextField(controller: taskInput, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Misalnya: Belajar matematika bab 2')),
      const SizedBox(height: 11), FilledButton.icon(onPressed: busy ? null : addTask, icon: const Icon(Icons.add), label: const Text('Simpan tugas')),
      const SizedBox(height: 7), OutlinedButton.icon(onPressed: busy ? null : () { if (widget.api.isGuest) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengingat cloud memerlukan akun. Masuk atau daftar terlebih dahulu.'))); widget.onAccount(); } else { run(() async { await widget.api.createReminder(taskInput.text.trim().isEmpty ? 'Waktunya belajar' : taskInput.text.trim(), DateTime.now().add(const Duration(hours: 1)), message: 'Pengingat dari StudyGo'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengingat berhasil dibuat.'))); }); } }, icon: const Icon(Icons.alarm_add_outlined), label: const Text('Ingatkan 1 jam lagi')),
    ]))),
    const SizedBox(height: 21), section('Daftar tugas', '${tasks.length} tugas tersimpan'), const SizedBox(height: 9),
    if (tasks.isEmpty) empty(Icons.event_note_outlined, 'Belum ada tugas', 'Tambahkan tugas pertamamu di atas.') else ...tasks.map(taskTile),
  ]));
  Widget taskTile(dynamic item) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4), leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: teal.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.task_alt, color: teal)), title: Text(item['title']?.toString() ?? 'Tugas', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(item['status']?.toString() ?? 'Belum ada status')));
  Widget library() => RefreshIndicator(onRefresh: () async { if (!widget.api.isGuest) materials = await widget.api.materials(); if (mounted) setState(() {}); }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20,14,20,28), children: [
    pageTitle('Materi belajar', 'Simpan bahan belajar dalam satu tempat.'),
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      Container(width: 58, height: 58, decoration: BoxDecoration(color: teal.withValues(alpha: .11), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.cloud_upload_outlined, color: teal, size: 30)),
      const SizedBox(height: 11), const Text('Tambahkan materi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 5), Text('PDF, DOCX, PPTX, video, atau gambar.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : upload, icon: const Icon(Icons.upload_file), label: const Text('Pilih file'))),
    ]))),
    const SizedBox(height: 21), section('Koleksi materi', '${materials.length} file tersimpan'), const SizedBox(height: 9),
    if (materials.isEmpty) empty(Icons.folder_open_outlined, 'Belum ada materi', 'File yang kamu unggah akan muncul di sini.') else ...materials.map((m) => Card(child: ListTile(leading: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFFE49A42)), title: Text(m['title']?.toString() ?? m['original_name']?.toString() ?? 'Materi'), subtitle: Text('${m['material_type'] ?? 'File'} • ${m['original_name'] ?? ''}')))),
  ]));
  Widget inbox() => RefreshIndicator(onRefresh: () async { if (!widget.api.isGuest) notifications = await widget.api.notifications(); if (mounted) setState(() {}); }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20,14,20,28), children: [
    pageTitle('Notifikasi', 'Informasi dan pengingat belajarmu.'),
    if (notifications.isEmpty) empty(Icons.notifications_none, 'Belum ada notifikasi', 'Notifikasi baru akan muncul di sini.') else ...notifications.map((n) => Card(child: ListTile(leading: const Icon(Icons.notifications_active_outlined, color: Color(0xFFCC718B)), title: Text(n['title']?.toString() ?? 'Notifikasi', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(n['body']?.toString() ?? ''), onTap: busy ? null : () => run(() async { await widget.api.markNotificationRead(int.parse(n['id'].toString())); notifications = await widget.api.notifications(); if (mounted) setState(() {}); })))),
  ]));
  Widget empty(IconData icon, String title, String sub) => Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28), child: Column(children: [Icon(icon, size: 38, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(sub, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))])));
}
