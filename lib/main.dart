import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const WhahApp());

// ======================= الألوان (على طراز ChatGPT) =======================
const kBg = Color(0xFF212121);
const kSide = Color(0xFF171717);
const kSurface = Color(0xFF2F2F2F);
const kText = Color(0xFFECECEC);
const kMuted = Color(0xFF9B9B9B);
const kAccent = Color(0xFF7C5CFF);
const kCyan = Color(0xFF22D3EE);
const kCode = Color(0xFF0D0D0D);

const kSystem =
    'أنت whah ai، مساعد ذكي خبير. أجب بنفس لغة المستخدم بوضوح وإيجاز. '
    'أنت متخصص أيضاً في البرمجة بكل اللغات، وتطوير أندرويد (Kotlin وFlutter وGradle)، '
    'ولينكس وbash، وأجهزة استقبال Enigma2 (إضافات Python وملفات skin XML وحزم IPK وأوامر opkg). '
    'اكتب الكود داخل كتل ``` مع اسم اللغة، ثم اشرح باختصار.';

bool isRtl(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

// ======================= النماذج =======================
class AiProvider {
  String id;
  String name;
  String url; // الرابط الكامل لـ chat/completions
  String key;
  String model;
  String hint;
  bool enabled;
  bool needsKey;
  bool builtIn;

  AiProvider({
    required this.id,
    required this.name,
    required this.url,
    required this.model,
    this.key = '',
    this.hint = '',
    this.enabled = true,
    this.needsKey = true,
    this.builtIn = false,
  });

  bool get ready => enabled && (!needsKey || key.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'key': key,
        'model': model,
        'hint': hint,
        'enabled': enabled,
        'needsKey': needsKey,
        'builtIn': builtIn,
      };

  factory AiProvider.fromJson(Map<String, dynamic> j) => AiProvider(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        key: (j['key'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        hint: (j['hint'] ?? '').toString(),
        enabled: j['enabled'] != false,
        needsKey: j['needsKey'] != false,
        builtIn: j['builtIn'] == true,
      );
}

List<AiProvider> defaultProviders() => [
      AiProvider(
        id: 'pollinations',
        name: 'Pollinations (مجاني بدون مفتاح)',
        url: 'https://text.pollinations.ai/openai',
        model: 'openai',
        needsKey: false,
        builtIn: true,
        hint: 'يعمل مباشرة بدون مفتاح، وقد يكون أبطأ أو محدوداً.',
      ),
      AiProvider(
        id: 'groq',
        name: 'Groq (مجاني)',
        url: 'https://api.groq.com/openai/v1/chat/completions',
        model: 'llama-3.3-70b-versatile',
        builtIn: true,
        hint: 'مفتاح مجاني من: console.groq.com',
      ),
      AiProvider(
        id: 'gemini',
        name: 'Google Gemini (مجاني)',
        url:
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        model: 'gemini-2.5-flash',
        builtIn: true,
        hint: 'مفتاح مجاني من: aistudio.google.com',
      ),
      AiProvider(
        id: 'openrouter',
        name: 'OpenRouter (نماذج مجانية)',
        url: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'meta-llama/llama-3.3-70b-instruct:free',
        builtIn: true,
        hint: 'مفتاح من: openrouter.ai/keys — النماذج المنتهية بـ :free مجانية.',
      ),
      AiProvider(
        id: 'cerebras',
        name: 'Cerebras (مجاني)',
        url: 'https://api.cerebras.ai/v1/chat/completions',
        model: 'llama-3.3-70b',
        builtIn: true,
        hint: 'مفتاح مجاني من: cloud.cerebras.ai',
      ),
      AiProvider(
        id: 'mistral',
        name: 'Mistral',
        url: 'https://api.mistral.ai/v1/chat/completions',
        model: 'mistral-small-latest',
        builtIn: true,
        hint: 'مفتاح من: console.mistral.ai',
      ),
      AiProvider(
        id: 'openai',
        name: 'OpenAI (مدفوع)',
        url: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4o-mini',
        enabled: false,
        builtIn: true,
        hint: 'مفتاح من: platform.openai.com/api-keys',
      ),
    ];

class Msg {
  String role; // user | assistant
  String text;
  String? via;
  Msg(this.role, this.text, [this.via]);

  Map<String, dynamic> toJson() => {'r': role, 't': text, 'v': via};
  factory Msg.fromJson(Map<String, dynamic> j) =>
      Msg((j['r'] ?? 'user').toString(), (j['t'] ?? '').toString(),
          j['v']?.toString());
}

class Chat {
  String id;
  String title;
  int ts;
  List<Msg> msgs;
  Chat(this.id, this.title, this.ts, this.msgs);

  factory Chat.create() {
    final t = DateTime.now().millisecondsSinceEpoch;
    return Chat(t.toString(), '', t, []);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ts': ts,
        'msgs': msgs.map((m) => m.toJson()).toList(),
      };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        (j['id'] ?? '').toString(),
        (j['title'] ?? '').toString(),
        j['ts'] is int ? j['ts'] as int : 0,
        ((j['msgs'] ?? []) as List)
            .map((e) => Msg.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

// ======================= التخزين =======================
class Store {
  static late SharedPreferences prefs;
  static List<AiProvider> providers = [];
  static List<Chat> chats = [];
  static bool dev = false;

  static Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    dev = prefs.getBool('dev') ?? false;
    try {
      final raw = prefs.getString('providers');
      if (raw != null) {
        providers = (jsonDecode(raw) as List)
            .map((e) => AiProvider.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      providers = [];
    }
    for (final d in defaultProviders()) {
      if (!providers.any((p) => p.id == d.id)) providers.add(d);
    }
    try {
      final raw = prefs.getString('chats');
      if (raw != null) {
        chats = (jsonDecode(raw) as List)
            .map((e) => Chat.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      chats = [];
    }
  }

  static Future<void> saveProviders() async => prefs.setString(
      'providers', jsonEncode(providers.map((e) => e.toJson()).toList()));

  static Future<void> saveChats() async {
    if (chats.length > 100) chats = chats.sublist(0, 100);
    await prefs.setString(
        'chats', jsonEncode(chats.map((e) => e.toJson()).toList()));
  }

  static Future<void> saveDev() async => prefs.setBool('dev', dev);
}

// ======================= البوابة (Gateway) =======================
class Reply {
  final String text;
  final String via;
  Reply(this.text, this.via);
}

class Gateway {
  /// يجرّب المزودات الجاهزة بالترتيب، وينتقل للتالي تلقائياً عند الفشل.
  static Future<Reply> ask(List<Msg> history) async {
    final ready = Store.providers.where((p) => p.ready).toList();
    if (ready.isEmpty) {
      throw 'لا يوجد مزود جاهز. افتح الإعدادات وفعّل مزوداً أو أضف مفتاح API.';
    }
    final clean = history.where((m) => m.via != 'error').toList();
    final recent = clean.length > 20 ? clean.sublist(clean.length - 20) : clean;
    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': kSystem},
      ...recent.map((m) => {'role': m.role, 'content': m.text}),
    ];
    final errors = <String>[];
    for (final p in ready) {
      try {
        final text = await _call(p, msgs);
        return Reply(text, p.name);
      } catch (e) {
        errors.add('• ${p.name}: $e');
      }
    }
    throw 'فشلت كل المزودات:\n${errors.join('\n')}';
  }

  static Future<String> test(AiProvider p) async {
    final text = await _call(p, [
      {'role': 'user', 'content': 'قل مرحباً بكلمة واحدة فقط'}
    ]);
    final t = text.trim();
    return t.length > 60 ? t.substring(0, 60) : t;
  }

  static Future<String> _call(
      AiProvider p, List<Map<String, String>> msgs) async {
    final res = await http
        .post(
          Uri.parse(p.url.trim()),
          headers: {
            'Content-Type': 'application/json',
            if (p.key.trim().isNotEmpty) 'Authorization': 'Bearer ${p.key.trim()}',
          },
          body: jsonEncode({'model': p.model.trim(), 'messages': msgs}),
        )
        .timeout(const Duration(seconds: 60));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      var m = body;
      try {
        final j = jsonDecode(body);
        final e = j['error'];
        m = (e is Map ? e['message'] : (e ?? j['message'] ?? body)).toString();
      } catch (_) {}
      throw 'HTTP ${res.statusCode} ${m.length > 140 ? m.substring(0, 140) : m}';
    }
    final j = jsonDecode(body);
    final c = j['choices']?[0]?['message']?['content'];
    if (c == null || c.toString().trim().isEmpty) throw 'رد فارغ';
    return c.toString();
  }
}

// ======================= التطبيق =======================
class WhahApp extends StatelessWidget {
  const WhahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'whah ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAccent, surface: kBg),
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Boot(),
    );
  }
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Store.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: WhahLogo(size: 64)));
    }
    return const ChatScreen();
  }
}

// ======================= الشعار =======================
class WhahLogo extends StatelessWidget {
  final double size;
  const WhahLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          colors: [kAccent, kCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        'W',
        style: TextStyle(
          fontSize: size * 0.58,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

// ======================= عارض الكود =======================
class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext ctx;
  CodeBlockBuilder(this.ctx);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trimRight();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: kCode,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 0),
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy, size: 16, color: kMuted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الكود')),
                      );
                    },
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                  color: kText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= شاشة الشات =======================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Chat _chat = Chat.create();
  bool _loading = false;

  void _newChat() => setState(() => _chat = Chat.create());

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    final chat = _chat;
    chat.msgs.add(Msg('user', text));
    if (chat.title.isEmpty) {
      chat.title = text.length > 40 ? text.substring(0, 40) : text;
    }
    if (!Store.chats.contains(chat)) Store.chats.insert(0, chat);
    setState(() => _loading = true);
    _toBottom();
    try {
      final r = await Gateway.ask(chat.msgs);
      chat.msgs.add(Msg('assistant', r.text, r.via));
    } catch (e) {
      chat.msgs.add(Msg('assistant', '⚠️ $e', 'error'));
    }
    chat.ts = DateTime.now().millisecondsSinceEpoch;
    await Store.saveChats();
    if (mounted) setState(() => _loading = false);
    _toBottom();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 300,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _deleteChat(Chat c) async {
    Store.chats.remove(c);
    if (identical(c, _chat)) _chat = Chat.create();
    await Store.saveChats();
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text('whah ai',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'محادثة جديدة',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _newChat,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Expanded(child: _body()),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_chat.msgs.isEmpty) return _welcome();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _chat.msgs.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) =>
          i == _chat.msgs.length ? _typing() : _msg(_chat.msgs[i]),
    );
  }

  Widget _welcome() {
    final noProvider = !Store.providers.any((p) => p.ready);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WhahLogo(size: 64),
            const SizedBox(height: 18),
            const Text('كيف أساعدك اليوم؟',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('اكتب سؤالك أو طلبك، وسأتولى الباقي تلقائياً',
                style: TextStyle(color: kMuted, fontSize: 15)),
            if (noProvider) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: _openSettings,
                child: const Text('لا يوجد مزود جاهز — افتح الإعدادات'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _msg(Msg m) {
    final dir = isRtl(m.text) ? TextDirection.rtl : TextDirection.ltr;
    if (m.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Directionality(
            textDirection: dir,
            child: SelectableText(
              m.text,
              style: const TextStyle(fontSize: 16, height: 1.45, color: kText),
            ),
          ),
        ),
      );
    }
    final isError = m.via == 'error';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WhahLogo(size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Directionality(
                    textDirection: dir,
                    child: MarkdownBody(
                      data: m.text,
                      selectable: true,
                      builders: {'pre': CodeBlockBuilder(context)},
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 16,
                          height: 1.55,
                          color: isError ? const Color(0xFFFFB4A9) : kText,
                        ),
                        code: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13.5,
                          color: kText,
                          backgroundColor: kCode,
                        ),
                        a: const TextStyle(color: kCyan),
                        listBullet: const TextStyle(color: kText),
                        h1: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                        h2: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                        h3: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: m.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ')),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.copy, size: 16, color: kMuted),
                      ),
                    ),
                    if (Store.dev && m.via != null && !isError)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('via ${m.via}',
                            style:
                                const TextStyle(color: kMuted, fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typing() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            WhahLogo(size: 28),
            SizedBox(width: 12),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kMuted),
            ),
          ],
        ),
      );

  Widget _inputBar() {
    final can = _ctrl.text.trim().isNotEmpty && !_loading;
    final dir = _ctrl.text.isEmpty
        ? TextDirection.rtl
        : (isRtl(_ctrl.text) ? TextDirection.rtl : TextDirection.ltr);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 6,
                  textDirection: dir,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16, color: kText),
                  decoration: const InputDecoration(
                    hintText: 'اسأل whah ai',
                    hintStyle: TextStyle(color: kMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: can ? _send : null,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: can ? Colors.white : const Color(0xFF5A5A5A),
                    ),
                    child: const Icon(Icons.arrow_upward,
                        size: 22, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawer() {
    return Drawer(
      backgroundColor: kSide,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  WhahLogo(size: 32),
                  SizedBox(width: 10),
                  Text('whah ai',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('محادثة جديدة'),
              onTap: () {
                Navigator.pop(context);
                _newChat();
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: Store.chats.isEmpty
                  ? const Center(
                      child: Text('لا توجد محادثات بعد',
                          style: TextStyle(color: kMuted)),
                    )
                  : ListView.builder(
                      itemCount: Store.chats.length,
                      itemBuilder: (_, i) {
                        final c = Store.chats[i];
                        return ListTile(
                          dense: true,
                          selected: identical(c, _chat),
                          selectedTileColor: kSurface,
                          title: Text(c.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: kMuted),
                            onPressed: () => _deleteChat(c),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _chat = c);
                            _toBottom();
                          },
                        );
                      },
                    ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('الإعدادات والمزودات'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= شاشة الإعدادات =======================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _status(AiProvider p) {
    if (!p.needsKey) return 'مجاني بدون مفتاح';
    return p.key.trim().isEmpty ? 'يحتاج مفتاح API' : 'المفتاح مضاف ✓';
  }

  Future<void> _edit(AiProvider p, {bool isNew = false}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ProviderSheet(p: p, isNew: isNew),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text('الإعدادات والمزودات'),
      ),
      floatingActionButton: Store.dev
          ? FloatingActionButton.extended(
              onPressed: () => _edit(
                AiProvider(id: DateTime.now().millisecondsSinceEpoch.toString(), name: '', url: '', model: ''),
                isNew: true,
              ),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مزود'),
            )
          : null,
      body: ReorderableListView(
        padding: const EdgeInsets.only(bottom: 100),
        header: Column(
          children: [
            SwitchListTile(
              title: const Text('وضع المطور (Gateway)'),
              subtitle: const Text(
                  'إضافة مواقع ذكاء اصطناعي ومفاتيحها، وتعديل الروابط والنماذج'),
              value: Store.dev,
              onChanged: (v) async {
                Store.dev = v;
                await Store.saveDev();
                if (mounted) setState(() {});
              },
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'يجرّب التطبيق المزودات المفعّلة بالترتيب، وينتقل للتالي تلقائياً '
                'إذا فشل الأول. اضغط مطولاً واسحب لتغيير الترتيب، واضغط على مزود لإضافة مفتاحه.',
                style: TextStyle(color: kMuted, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
        onReorder: (a, b) {
          if (b > a) b -= 1;
          final it = Store.providers.removeAt(a);
          Store.providers.insert(b, it);
          Store.saveProviders();
          setState(() {});
        },
        children: [
          for (final p in Store.providers)
            ListTile(
              key: ValueKey(p.id),
              isThreeLine: true,
              leading: Icon(Icons.circle,
                  size: 12,
                  color: p.ready ? const Color(0xFF3DDC84) : kMuted),
              title: Text(p.name),
              subtitle: Text('${p.model}\n${_status(p)}',
                  style: const TextStyle(color: kMuted, fontSize: 12)),
              trailing: Switch(
                value: p.enabled,
                onChanged: (v) {
                  p.enabled = v;
                  Store.saveProviders();
                  setState(() {});
                },
              ),
              onTap: () => _edit(p),
            ),
        ],
      ),
    );
  }
}

// ======================= نافذة تعديل المزود =======================
class ProviderSheet extends StatefulWidget {
  final AiProvider p;
  final bool isNew;
  const ProviderSheet({super.key, required this.p, required this.isNew});
  @override
  State<ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends State<ProviderSheet> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _model;
  late final TextEditingController _key;
  bool _hide = true;
  bool _busy = false;
  bool _needsKey = true;
  String _result = '';

  @override
  void initState() {
    super.initState();
    final p = widget.p;
    _name = TextEditingController(text: p.name);
    _url = TextEditingController(text: p.url);
    _model = TextEditingController(text: p.model);
    _key = TextEditingController(text: p.key);
    _needsKey = p.needsKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  AiProvider _temp() => AiProvider(
        id: widget.p.id,
        name: _name.text.trim(),
        url: _url.text.trim(),
        model: _model.text.trim(),
        key: _key.text.trim(),
        needsKey: _needsKey,
      );

  Future<void> _test() async {
    final t = _temp();
    if (t.url.isEmpty || t.model.isEmpty) {
      setState(() => _result = '❌ أدخل الرابط واسم النموذج أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _result = '';
    });
    String msg;
    try {
      msg = '✅ يعمل: ${await Gateway.test(t)}';
    } catch (e) {
      msg = '❌ $e';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = msg;
      });
    }
  }

  Future<void> _save() async {
    final t = _temp();
    if (Store.dev || widget.isNew) {
      if (t.name.isEmpty || t.url.isEmpty || t.model.isEmpty) {
        setState(() => _result = '❌ الاسم والرابط والنموذج مطلوبة');
        return;
      }
    }
    final p = widget.p;
    if (Store.dev || widget.isNew) {
      p.name = t.name;
      p.url = t.url;
      p.needsKey = _needsKey;
    }
    p.model = t.model;
    p.key = t.key;
    if (widget.isNew) Store.providers.add(p);
    await Store.saveProviders();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    Store.providers.removeWhere((e) => e.id == widget.p.id);
    await Store.saveProviders();
    if (mounted) Navigator.pop(context);
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: kBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final dev = Store.dev || widget.isNew;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isNew ? 'إضافة مزود جديد' : p.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (p.hint.isNotEmpty && !widget.isNew) ...[
              const SizedBox(height: 6),
              Text(p.hint,
                  style: const TextStyle(color: kMuted, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            if (dev) ...[
              TextField(controller: _name, decoration: _dec('اسم المزود')),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: _dec('الرابط الكامل (Endpoint)',
                    hint: 'https://.../v1/chat/completions'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _model,
              textDirection: TextDirection.ltr,
              decoration: _dec('النموذج (Model)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _hide,
              enableSuggestions: false,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: _dec(
                'مفتاح API',
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off,
                      size: 20),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
            if (dev)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('يتطلب مفتاح API'),
                value: _needsKey,
                onChanged: (v) => setState(() => _needsKey = v),
              ),
            if (_result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_result, style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _test,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('اختبار'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('حفظ'),
                  ),
                ),
              ],
            ),
            if (Store.dev && !p.builtIn && !widget.isNew)
              TextButton(
                onPressed: _delete,
                child: const Text('حذف المزود',
                    style: TextStyle(color: Color(0xFFFF6B6B))),
              ),
          ],
        ),
      ),
    );
  }
}
