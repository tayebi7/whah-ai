import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WhahApp());
}

// ======================= ألوان بطراز Claude (أزرق داكن) =======================
const kBg = Color(0xFF0F1419);
const kSide = Color(0xFF151B23);
const kSurface = Color(0xFF1C2430);
const kSurface2 = Color(0xFF243044);
const kText = Color(0xFFE8EEF5);
const kMuted = Color(0xFF8B9BB0);
const kAccent = Color(0xFF3B82F6); // أزرق Claude-like
const kAccentSoft = Color(0xFF2563EB);
const kCyan = Color(0xFF38BDF8);
const kCode = Color(0xFF0B1220);
const kUserBubble = Color(0xFF1E3A5F);
const kBorder = Color(0xFF2A3544);
const kSuccess = Color(0xFF34D399);
const kDanger = Color(0xFFF87171);

const kSystem = '''
أنت whah ai، مساعد ذكي سريع ودقيق بطراز Claude.
- أجب بنفس لغة المستخدم بوضوح وإيجاز مفيد.
- متخصص في: البرمجة (كل اللغات)، Flutter/Kotlin/Android/Gradle، Linux/bash،
  Enigma2 (Python plugins, skin XML, IPK, opkg)، تحليل البيانات، والمستندات.
- اكتب الكود داخل كتل ``` مع اسم اللغة ثم شرح مختصر.
- إذا أُرفق ملف أو صورة: حلّل المحتوى المعطى واستخرج المطلوب بدقة.
- للصور/الفيديو/التطبيقات: اقترح خطوات عملية أو كود توليد/معالجة ضمن قدراتك النصية.
- لا تختلق معلومات؛ إن لم تعرف قل ذلك.
''';

bool isRtl(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

// ======================= النماذج =======================
class AiProvider {
  String id;
  String name;
  String url;
  String key;
  String model;
  String hint;
  bool enabled;
  bool needsKey;
  bool builtIn;
  bool supportsStream;

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
    this.supportsStream = true,
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
        'supportsStream': supportsStream,
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
        supportsStream: j['supportsStream'] != false,
      );
}

List<AiProvider> defaultProviders() => [
      AiProvider(
        id: 'groq',
        name: 'Groq (سريع جداً)',
        url: 'https://api.groq.com/openai/v1/chat/completions',
        model: 'llama-3.3-70b-versatile',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح مجاني: console.groq.com — الأسرع عملياً',
      ),
      AiProvider(
        id: 'cerebras',
        name: 'Cerebras (سريع)',
        url: 'https://api.cerebras.ai/v1/chat/completions',
        model: 'llama-3.3-70b',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: cloud.cerebras.ai',
      ),
      AiProvider(
        id: 'openrouter',
        name: 'OpenRouter (نماذج مجانية)',
        url: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'meta-llama/llama-3.3-70b-instruct:free',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: openrouter.ai/keys — اختر نماذج :free',
      ),
      AiProvider(
        id: 'gemini',
        name: 'Google Gemini',
        url:
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        model: 'gemini-2.0-flash',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: aistudio.google.com',
      ),
      AiProvider(
        id: 'pollinations',
        name: 'Pollinations (بدون مفتاح)',
        url: 'https://text.pollinations.ai/openai',
        model: 'openai',
        needsKey: false,
        builtIn: true,
        supportsStream: false,
        hint: 'يعمل بدون مفتاح — قد يكون أبطأ أو محدوداً',
      ),
      AiProvider(
        id: 'mistral',
        name: 'Mistral',
        url: 'https://api.mistral.ai/v1/chat/completions',
        model: 'mistral-small-latest',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: console.mistral.ai',
      ),
      AiProvider(
        id: 'xai',
        name: 'xAI Grok',
        url: 'https://api.x.ai/v1/chat/completions',
        model: 'grok-2-latest',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: console.x.ai',
      ),
      AiProvider(
        id: 'deepseek',
        name: 'DeepSeek',
        url: 'https://api.deepseek.com/chat/completions',
        model: 'deepseek-chat',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: platform.deepseek.com',
      ),
      AiProvider(
        id: 'openai',
        name: 'OpenAI',
        url: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4o-mini',
        enabled: false,
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح: platform.openai.com/api-keys',
      ),
    ];

class Attachment {
  String name;
  String path;
  String mime;
  int size;
  String? textPreview; // للنصوص/الكود

  Attachment({
    required this.name,
    required this.path,
    required this.mime,
    required this.size,
    this.textPreview,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'mime': mime,
        'size': size,
        'textPreview': textPreview,
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        name: (j['name'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        mime: (j['mime'] ?? '').toString(),
        size: j['size'] is int ? j['size'] as int : 0,
        textPreview: j['textPreview']?.toString(),
      );

  String describe() {
    final kb = (size / 1024).toStringAsFixed(1);
    if (textPreview != null && textPreview!.isNotEmpty) {
      final t = textPreview!.length > 4000
          ? '${textPreview!.substring(0, 4000)}\n…'
          : textPreview!;
      return '[ملف: $name ($kb KB)]\n```\n$t\n```';
    }
    return '[مرفق: $name — نوع: $mime — حجم: $kb KB] '
        '(المحتوى الثنائي غير مقروء هنا؛ صف المطلوب منه)';
  }
}

class Msg {
  String role; // user | assistant
  String text;
  String? via;
  List<Attachment> files;

  Msg(this.role, this.text, [this.via, List<Attachment>? files])
      : files = files ?? [];

  Map<String, dynamic> toJson() => {
        'r': role,
        't': text,
        'v': via,
        'f': files.map((e) => e.toJson()).toList(),
      };

  factory Msg.fromJson(Map<String, dynamic> j) => Msg(
        (j['r'] ?? 'user').toString(),
        (j['t'] ?? '').toString(),
        j['v']?.toString(),
        ((j['f'] ?? []) as List)
            .map((e) => Attachment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Chat {
  String id;
  String title;
  int ts;
  List<Msg> msgs;
  String linkedApp; // اسم تطبيق مرتبط

  Chat(this.id, this.title, this.ts, this.msgs, {this.linkedApp = ''});

  factory Chat.create() {
    final t = DateTime.now().millisecondsSinceEpoch;
    return Chat(const Uuid().v4(), '', t, []);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ts': ts,
        'msgs': msgs.map((m) => m.toJson()).toList(),
        'linkedApp': linkedApp,
      };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        (j['id'] ?? '').toString(),
        (j['title'] ?? '').toString(),
        j['ts'] is int ? j['ts'] as int : 0,
        ((j['msgs'] ?? []) as List)
            .map((e) => Msg.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        linkedApp: (j['linkedApp'] ?? '').toString(),
      );
}

// ======================= التخزين =======================
class Store {
  static late SharedPreferences prefs;
  static List<AiProvider> providers = [];
  static List<Chat> chats = [];
  static bool dev = false;
  static String githubUser = '';
  static String preferredProviderId = '';

  static Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    dev = prefs.getBool('dev') ?? false;
    githubUser = prefs.getString('githubUser') ?? '';
    preferredProviderId = prefs.getString('preferredProviderId') ?? '';
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
      if (!providers.any((p) => p.id == d.id)) {
        providers.add(d);
      } else {
        // تحديث تلميحات/عناوين المزودات المدمجة دون مسح المفاتيح
        final i = providers.indexWhere((p) => p.id == d.id);
        if (i >= 0 && providers[i].builtIn) {
          providers[i].name = d.name;
          providers[i].url = d.url;
          providers[i].hint = d.hint;
          providers[i].supportsStream = d.supportsStream;
          if (providers[i].model.isEmpty) providers[i].model = d.model;
        }
      }
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
    if (chats.length > 120) chats = chats.sublist(0, 120);
    await prefs.setString(
        'chats', jsonEncode(chats.map((e) => e.toJson()).toList()));
  }

  static Future<void> saveDev() async => prefs.setBool('dev', dev);

  static Future<void> saveGithub() async =>
      prefs.setString('githubUser', githubUser);

  static Future<void> savePreferred() async =>
      prefs.setString('preferredProviderId', preferredProviderId);
}

// ======================= البوابة مع Streaming =======================
class Reply {
  final String text;
  final String via;
  Reply(this.text, this.via);
}

class ApiError implements Exception {
  final int status;
  final String msg;
  ApiError(this.status, this.msg);
  @override
  String toString() => 'HTTP $status $msg';
}

class Gateway {
  static String lastGood = '';
  static final Map<String, int> _cool = {};

  static String chatUrl(String raw) {
    final u = raw.trim().replaceFirst(RegExp(r'/+$'), '');
    if (u.contains('/chat/completions')) return u;
    if (u.contains('pollinations')) return u;
    return '$u/chat/completions';
  }

  static Future<List<String>> listModels(AiProvider p) async {
    var u = chatUrl(p.url);
    u = u.contains('/chat/completions')
        ? u.replaceFirst('/chat/completions', '/models')
        : '$u/models';
    final res = await http.get(Uri.parse(u), headers: {
      if (p.key.trim().isNotEmpty) 'Authorization': 'Bearer ${p.key.trim()}',
    }).timeout(const Duration(seconds: 20));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw ApiError(
          res.statusCode, body.length > 280 ? body.substring(0, 280) : body);
    }
    final j = jsonDecode(body);
    final list = j is Map ? (j['data'] ?? j['models'] ?? []) : j;
    final out = <String>[];
    for (final e in (list as List)) {
      if (e is Map) {
        final id = (e['id'] ?? e['name'] ?? '').toString();
        if (id.isNotEmpty) out.add(id);
      } else if (e is String) {
        out.add(e);
      }
    }
    const bad = [
      'embed', 'whisper', 'tts', 'audio', 'image', 'guard', 'moderation',
      'rerank', 'imagen', 'veo', 'dall', 'speech', 'transcri',
    ];
    out.removeWhere((id) => bad.any((b) => id.toLowerCase().contains(b)));
    out.sort();
    return out;
  }

  static String? pickModel(AiProvider p, List<String> models) {
    if (models.isEmpty) return null;
    var pool = models;
    if (p.url.contains('openrouter')) {
      final f = models.where((m) => m.endsWith(':free')).toList();
      if (f.isNotEmpty) pool = f;
    }
    const order = [
      'flash', 'llama-3.3-70b', '70b', 'instruct', 'small', 'mini', 'latest',
    ];
    for (final k in order) {
      for (final m in pool) {
        if (m.toLowerCase().contains(k)) return m;
      }
    }
    return pool.first;
  }

  static Future<String> _callOnce(
    AiProvider p,
    List<Map<String, dynamic>> msgs, {
    void Function(String delta)? onDelta,
  }) async {
    final useStream = p.supportsStream && onDelta != null;
    final bodyMap = <String, dynamic>{
      'model': p.model.trim(),
      'messages': msgs,
      if (useStream) 'stream': true,
    };
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': useStream ? 'text/event-stream' : 'application/json',
      if (p.key.trim().isNotEmpty) 'Authorization': 'Bearer ${p.key.trim()}',
      // OpenRouter يفضّل هذه العناوين
      if (p.url.contains('openrouter')) ...{
        'HTTP-Referer': 'https://whah.ai',
        'X-Title': 'whah ai',
      },
    };

    if (!useStream) {
      final res = await http
          .post(
            Uri.parse(chatUrl(p.url)),
            headers: headers,
            body: jsonEncode(bodyMap),
          )
          .timeout(const Duration(seconds: 55));
      final body = utf8.decode(res.bodyBytes);
      if (res.statusCode != 200) {
        throw ApiError(res.statusCode, _extractErr(body));
      }
      final j = jsonDecode(body);
      final c = j['choices']?[0]?['message']?['content'];
      if (c == null || c.toString().trim().isEmpty) throw 'رد فارغ';
      return c.toString();
    }

    // Streaming SSE
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(chatUrl(p.url)));
      req.headers.addAll(headers);
      req.body = jsonEncode(bodyMap);
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 60));
      if (streamed.statusCode != 200) {
        final errBody = await streamed.stream.bytesToString();
        throw ApiError(streamed.statusCode, _extractErr(errBody));
      }
      final buf = StringBuffer();
      final lineBuf = StringBuffer();
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        lineBuf.write(chunk);
        var raw = lineBuf.toString();
        final parts = raw.split('\n');
        lineBuf.clear();
        if (!raw.endsWith('\n')) {
          lineBuf.write(parts.removeLast());
        }
        for (final line in parts) {
          final t = line.trim();
          if (t.isEmpty || !t.startsWith('data:')) continue;
          final data = t.substring(5).trim();
          if (data == '[DONE]') break;
          try {
            final j = jsonDecode(data);
            final delta = j['choices']?[0]?['delta']?['content'];
            if (delta != null) {
              final s = delta.toString();
              buf.write(s);
              onDelta(s);
            }
          } catch (_) {}
        }
      }
      final out = buf.toString();
      if (out.trim().isEmpty) throw 'رد فارغ (stream)';
      return out;
    } finally {
      client.close();
    }
  }

  static String _extractErr(String body) {
    try {
      final j = jsonDecode(body);
      final e = j['error'];
      final m = (e is Map ? e['message'] : (e ?? j['message'] ?? body)).toString();
      return m.length > 300 ? m.substring(0, 300) : m;
    } catch (_) {
      return body.length > 300 ? body.substring(0, 300) : body;
    }
  }

  static Future<String> _callRepair(
    AiProvider p,
    List<Map<String, dynamic>> msgs, {
    void Function(String delta)? onDelta,
  }) async {
    try {
      return await _callOnce(p, msgs, onDelta: onDelta);
    } on ApiError catch (e) {
      final low = e.msg.toLowerCase();
      final modelIssue = (e.status == 404) ||
          ((e.status == 400 || e.status == 422) && low.contains('model'));
      if (!modelIssue) rethrow;
      if (p.needsKey && p.key.trim().isEmpty) rethrow;
      final models = await listModels(p);
      final pick = pickModel(p, models);
      if (pick == null || pick == p.model) rethrow;
      final old = p.model;
      p.model = pick;
      try {
        final t = await _callOnce(p, msgs, onDelta: onDelta);
        await Store.saveProviders();
        return t;
      } catch (_) {
        p.model = old;
        rethrow;
      }
    }
  }

  static List<Map<String, dynamic>> _buildMessages(List<Msg> history) {
    final clean = history.where((m) => m.via != 'error').toList();
    final recent = clean.length > 24 ? clean.sublist(clean.length - 24) : clean;
    final msgs = <Map<String, dynamic>>[
      {'role': 'system', 'content': kSystem},
    ];
    for (final m in recent) {
      var content = m.text;
      if (m.files.isNotEmpty) {
        final extra = m.files.map((f) => f.describe()).join('\n\n');
        content = content.isEmpty ? extra : '$content\n\n$extra';
      }
      msgs.add({'role': m.role, 'content': content});
    }
    return msgs;
  }

  /// يجرّب المزودات بالترتيب مع بث تدريجي إن أمكن
  static Future<Reply> ask(
    List<Msg> history, {
    void Function(String partial, String via)? onPartial,
  }) async {
    final ready = Store.providers.where((p) => p.ready).toList();
    if (ready.isEmpty) {
      throw 'لا يوجد مزود جاهز. افتح الإعدادات وفعّل مزوداً أو أضف مفتاح API.';
    }
    final msgs = _buildMessages(history);
    final now = DateTime.now().millisecondsSinceEpoch;

    // المفضّل ثم lastGood ثم الباقي
    final preferred = Store.preferredProviderId;
    final ordered = <AiProvider>[
      ...ready.where((p) => p.id == preferred),
      ...ready.where((p) => p.id == lastGood && p.id != preferred),
      ...ready.where((p) => p.id != preferred && p.id != lastGood),
    ];
    var queue = ordered.where((p) => (_cool[p.id] ?? 0) < now).toList();
    if (queue.isEmpty) queue = ordered;

    final errors = <String>[];
    for (final p in queue) {
      try {
        final buf = StringBuffer();
        final text = await _callRepair(
          p,
          msgs,
          onDelta: (d) {
            buf.write(d);
            onPartial?.call(buf.toString(), p.name);
          },
        );
        lastGood = p.id;
        _cool.remove(p.id);
        return Reply(text, p.name);
      } catch (e) {
        var s = e.toString();
        var wait = 45000;
        if (e is ApiError) {
          if (e.status == 401 || e.status == 403) {
            s = '$s\n   (المفتاح غير صحيح أو محجوب)';
            wait = 400000;
          } else if (e.status == 429) {
            s = '$s\n   (تجاوزت حد الاستخدام)';
            wait = 180000;
          }
        }
        _cool[p.id] = DateTime.now().millisecondsSinceEpoch + wait;
        errors.add('• ${p.name}: ${s.length > 200 ? s.substring(0, 200) : s}');
      }
    }
    throw 'فشلت كل المزودات:\n${errors.join('\n')}';
  }

  static Future<String> test(AiProvider p) async {
    final text = await _callRepair(p, [
      {'role': 'user', 'content': 'قل مرحباً بكلمة واحدة فقط'}
    ]);
    final t = text.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
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
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          surface: kBg,
          secondary: kCyan,
        ),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: kSurface2,
          contentTextStyle: TextStyle(color: kText),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: kSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kAccent, width: 1.4),
          ),
        ),
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
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: WhahLogo(size: 72)),
      );
    }
    return const ChatScreen();
  }
}

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
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          colors: [kAccent, kCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kAccent.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        'W',
        style: TextStyle(
          fontSize: size * 0.55,
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: kCode,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
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
                  const Text('code',
                      style: TextStyle(color: kMuted, fontSize: 11)),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'نسخ الكود',
                    icon: const Icon(Icons.copy_rounded, size: 16, color: kMuted),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('تم نسخ الكود'),
                              duration: Duration(seconds: 1)),
                        );
                      }
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

// ======================= شاشة الشات (الأولوية) =======================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Chat _chat = Chat.create();
  bool _loading = false;
  String _streamText = '';
  String _streamVia = '';
  final List<Attachment> _pending = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _newChat() {
    setState(() {
      _chat = Chat.create();
      _pending.clear();
      _streamText = '';
      _loading = false;
    });
  }

  Future<void> _pickFiles() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'رفع الملفات سيُفعَّل في التحديث القادم. حالياً الصق النص من الحافظة.',
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الحافظة فارغة')),
        );
      }
      return;
    }
    final cur = _ctrl.text;
    final sel = _ctrl.selection;
    if (sel.isValid) {
      final newText = cur.replaceRange(sel.start, sel.end, t);
      _ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + t.length),
      );
    } else {
      _ctrl.text = cur.isEmpty ? t : '$cur$t';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
    setState(() {});
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _loading) return;
    final files = List<Attachment>.from(_pending);
    _ctrl.clear();
    _pending.clear();
    final chat = _chat;
    chat.msgs.add(Msg('user', text, null, files));
    if (chat.title.isEmpty) {
      final base = text.isNotEmpty
          ? text
          : (files.isNotEmpty ? 'مرفقات: ${files.first.name}' : 'محادثة');
      chat.title = base.length > 42 ? base.substring(0, 42) : base;
    }
    if (!Store.chats.any((c) => c.id == chat.id)) {
      Store.chats.insert(0, chat);
    }
    setState(() {
      _loading = true;
      _streamText = '';
      _streamVia = '';
    });
    _toBottom();

    // رسالة assistant مؤقتة للبث
    final assistantIdx = chat.msgs.length;
    chat.msgs.add(Msg('assistant', '', '…'));

    try {
      final r = await Gateway.ask(
        chat.msgs.sublist(0, assistantIdx),
        onPartial: (partial, via) {
          if (!mounted) return;
          setState(() {
            _streamText = partial;
            _streamVia = via;
            chat.msgs[assistantIdx] = Msg('assistant', partial, via);
          });
          _toBottom();
        },
      );
      chat.msgs[assistantIdx] = Msg('assistant', r.text, r.via);
    } catch (e) {
      chat.msgs[assistantIdx] = Msg('assistant', '⚠️ $e', 'error');
    }
    chat.ts = DateTime.now().millisecondsSinceEpoch;
    // ترتيب المحادثات حسب آخر نشاط
    Store.chats.removeWhere((c) => c.id == chat.id);
    Store.chats.insert(0, chat);
    await Store.saveChats();
    if (mounted) {
      setState(() {
        _loading = false;
        _streamText = '';
      });
    }
    _toBottom();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 240,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _deleteChat(Chat c) async {
    Store.chats.removeWhere((x) => x.id == c.id);
    if (c.id == _chat.id) _chat = Chat.create();
    await Store.saveChats();
    if (mounted) setState(() {});
  }

  Future<void> _exportChat() async {
    final buf = StringBuffer();
    buf.writeln('# ${_chat.title.isEmpty ? "محادثة" : _chat.title}');
    if (_chat.linkedApp.isNotEmpty) {
      buf.writeln('التطبيق المرتبط: ${_chat.linkedApp}');
    }
    buf.writeln();
    for (final m in _chat.msgs) {
      buf.writeln('## ${m.role == "user" ? "أنت" : "whah ai"}');
      buf.writeln(m.text);
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ المحادثة إلى الحافظة')),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _linkAppDialog() async {
    final c = TextEditingController(text: _chat.linkedApp);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('ربط محادثة بتطبيق'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: 'مثال: Enigma2 — IPTV Manager',
            labelText: 'اسم التطبيق',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      _chat.linkedApp = c.text.trim();
      if (!Store.chats.any((x) => x.id == _chat.id)) {
        Store.chats.insert(0, _chat);
      }
      await Store.saveChats();
      if (mounted) setState(() {});
    }
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
        title: Column(
          children: [
            const Text('whah ai',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            if (_chat.linkedApp.isNotEmpty)
              Text(_chat.linkedApp,
                  style: const TextStyle(fontSize: 11, color: kMuted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تصدير / مشاركة',
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: _chat.msgs.isEmpty ? null : _exportChat,
          ),
          IconButton(
            tooltip: 'محادثة جديدة',
            icon: const Icon(Icons.edit_square, size: 20),
            onPressed: _newChat,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Expanded(child: _body()),
              _attachmentsBar(),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_chat.msgs.isEmpty && !_loading) return _welcome();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _chat.msgs.length + (_loading && _streamText.isEmpty ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _chat.msgs.length) return _typing();
        return _msg(_chat.msgs[i]);
      },
    );
  }

  Widget _welcome() {
    final noProvider = !Store.providers.any((p) => p.ready);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WhahLogo(size: 72),
            const SizedBox(height: 22),
            const Text('كيف يمكنني مساعدتك؟',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text(
              'شات سريع • كود • ملفات • تحليل\nمزودات متعددة مع بث مباشر للإجابات',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _chip('اكتب كود Flutter', 'اكتب مثالاً لتطبيق Flutter بسيط'),
                _chip('حلّل ملف', 'كيف أرفع ملفاً وأطلب تحليله؟'),
                _chip('Enigma2', 'اشرح عمل إضافة Python لـ Enigma2'),
                _chip('أوامر Linux', 'أوامر bash مفيدة لإدارة السيرفر'),
              ],
            ),
            if (noProvider) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
                label: const Text('لا يوجد مزود جاهز — الإعدادات'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String prompt) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      backgroundColor: kSurface,
      side: const BorderSide(color: kBorder),
      onPressed: () {
        _ctrl.text = prompt;
        setState(() {});
        _focus.requestFocus();
      },
    );
  }

  Widget _msg(Msg m) {
    final dir = isRtl(m.text) ? TextDirection.rtl : TextDirection.ltr;
    if (m.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: kUserBubble,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: m.files
                        .map((f) => Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.attach_file, size: 14),
                              label: Text(f.name,
                                  style: const TextStyle(fontSize: 11)),
                              backgroundColor: kSurface2,
                            ))
                        .toList(),
                  ),
                ),
              Directionality(
                textDirection: dir,
                child: SelectableText(
                  m.text.isEmpty && m.files.isNotEmpty
                      ? '(مرفقات فقط)'
                      : m.text,
                  style:
                      const TextStyle(fontSize: 15.5, height: 1.45, color: kText),
                ),
              ),
            ],
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
                      data: m.text.isEmpty ? '…' : m.text,
                      selectable: true,
                      builders: {'pre': CodeBlockBuilder(context)},
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 15.5,
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
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: m.text));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم النسخ'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child:
                            Icon(Icons.copy_rounded, size: 16, color: kMuted),
                      ),
                    ),
                    if (m.via != null && !isError && m.via != '…')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('via ${m.via}',
                            style: const TextStyle(
                                color: kMuted, fontSize: 11)),
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
            SizedBox(width: 10),
            Text('يكتب…', style: TextStyle(color: kMuted, fontSize: 13)),
          ],
        ),
      );

  Widget _attachmentsBar() {
    if (_pending.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _pending.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InputChip(
                  label: Text(_pending[i].name,
                      style: const TextStyle(fontSize: 12)),
                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                  onDeleted: () => setState(() => _pending.removeAt(i)),
                  backgroundColor: kSurface2,
                  side: const BorderSide(color: kBorder),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    final can =
        (_ctrl.text.trim().isNotEmpty || _pending.isNotEmpty) && !_loading;
    final dir = _ctrl.text.isEmpty
        ? TextDirection.rtl
        : (isRtl(_ctrl.text) ? TextDirection.rtl : TextDirection.ltr);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'إرفاق ملف',
                icon: const Icon(Icons.attach_file_rounded, color: kMuted),
                onPressed: _loading ? null : _pickFiles,
              ),
              IconButton(
                tooltip: 'لصق من الحافظة',
                icon: const Icon(Icons.content_paste_rounded, color: kMuted),
                onPressed: _loading ? null : _pasteFromClipboard,
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 7,
                  textDirection: dir,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (can) _send();
                  },
                  style: const TextStyle(fontSize: 15.5, color: kText),
                  decoration: const InputDecoration(
                    hintText: 'اسأل whah ai…',
                    hintStyle: TextStyle(color: kMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: GestureDetector(
                  onTap: can ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: can ? kAccent : const Color(0xFF3A4555),
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 22,
                      color: can ? Colors.white : kMuted,
                    ),
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
                  WhahLogo(size: 34),
                  SizedBox(width: 10),
                  Text('whah ai',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_square),
              title: const Text('محادثة جديدة'),
              onTap: () {
                Navigator.pop(context);
                _newChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('ربط بتطبيق'),
              subtitle: _chat.linkedApp.isEmpty
                  ? null
                  : Text(_chat.linkedApp,
                      style: const TextStyle(fontSize: 12, color: kMuted)),
              onTap: () {
                Navigator.pop(context);
                _linkAppDialog();
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('السجل',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ),
            ),
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
                          selected: c.id == _chat.id,
                          selectedTileColor: kSurface,
                          title: Text(
                            c.title.isEmpty ? 'بدون عنوان' : c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: c.linkedApp.isEmpty
                              ? null
                              : Text(c.linkedApp,
                                  style: const TextStyle(
                                      fontSize: 11, color: kMuted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: kMuted),
                            onPressed: () => _deleteChat(c),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _chat = c;
                              _pending.clear();
                            });
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

// ======================= الإعدادات =======================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _githubCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _githubCtrl.text = Store.githubUser;
  }

  @override
  void dispose() {
    _githubCtrl.dispose();
    super.dispose();
  }

  String _status(AiProvider p) {
    if (!p.enabled) return 'معطّل';
    if (p.needsKey && p.key.trim().isEmpty) return 'يحتاج مفتاح API';
    return 'جاهز';
  }

  Future<void> _edit(AiProvider p, {bool isNew = false}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ProviderSheet(p: p, isNew: isNew),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openGithub() async {
    final u = Store.githubUser.trim();
    final link = u.isEmpty ? 'https://github.com' : 'https://github.com/$u';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم نسخ الرابط: $link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('الإعدادات'),
        actions: [
          if (Store.dev)
            IconButton(
              tooltip: 'إضافة مزود',
              icon: const Icon(Icons.add),
              onPressed: () {
                final p = AiProvider(
                  id: const Uuid().v4(),
                  name: '',
                  url: '',
                  model: '',
                  builtIn: false,
                );
                _edit(p, isNew: true);
              },
            ),
        ],
      ),
      body: ReorderableListView(
        padding: const EdgeInsets.only(bottom: 24),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: const Text('وضع المطور (Gateway)'),
              subtitle: const Text(
                  'إضافة مزودات مخصصة وتعديل الروابط والنماذج'),
              value: Store.dev,
              activeTrackColor: kAccent,
              onChanged: (v) async {
                Store.dev = v;
                await Store.saveDev();
                if (mounted) setState(() {});
              },
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'يُفضَّل تفعيل Groq أو Cerebras لأقصى سرعة. '
                'الإجابات تُبث حرفاً بحرف عند دعم الـ stream. '
                'اسحب لإعادة ترتيب أولوية المزودات.',
                style: TextStyle(color: kMuted, fontSize: 13, height: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _githubCtrl,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'مستخدم GitHub (اختياري)',
                  hintText: 'username',
                  prefixIcon: Icon(Icons.code),
                ),
                onChanged: (v) async {
                  Store.githubUser = v.trim();
                  await Store.saveGithub();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _openGithub,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('فتح GitHub'),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('المزودات',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        onReorder: (a, b) {
          // header لا يدخل في القائمة — الفهارس على providers فقط
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
              leading: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle,
                      size: 12, color: p.ready ? kSuccess : kMuted),
                  if (Store.preferredProviderId == p.id)
                    const Icon(Icons.star, size: 12, color: kAccent),
                ],
              ),
              title: Text(p.name),
              subtitle: Text('${p.model}\n${_status(p)}',
                  style: const TextStyle(color: kMuted, fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تفضيل للسرعة',
                    icon: Icon(
                      Store.preferredProviderId == p.id
                          ? Icons.star
                          : Icons.star_border,
                      color: kAccent,
                      size: 20,
                    ),
                    onPressed: () async {
                      Store.preferredProviderId =
                          Store.preferredProviderId == p.id ? '' : p.id;
                      await Store.savePreferred();
                      setState(() {});
                    },
                  ),
                  Switch(
                    value: p.enabled,
                    activeTrackColor: kAccent,
                    onChanged: (v) {
                      p.enabled = v;
                      Store.saveProviders();
                      setState(() {});
                    },
                  ),
                ],
              ),
              onTap: () => _edit(p),
            ),
        ],
      ),
    );
  }
}

// ======================= تعديل مزود =======================
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
  bool _stream = true;
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
    _stream = p.supportsStream;
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
        supportsStream: _stream,
        builtIn: widget.p.builtIn,
        hint: widget.p.hint,
      );

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        suffixIcon: suffix,
      );

  Future<void> _pickModel() async {
    final t = _temp();
    if (t.url.isEmpty) {
      setState(() => _result = '❌ أدخل الرابط أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final list = await Gateway.listModels(t);
      if (!mounted) return;
      setState(() => _busy = false);
      if (list.isEmpty) {
        setState(() => _result = '❌ لا توجد نماذج');
        return;
      }
      final sel = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: kSurface,
        builder: (c) => ListView(
          children: [
            for (final m in list)
              ListTile(
                dense: true,
                title: Text(m, textDirection: TextDirection.ltr),
                onTap: () => Navigator.pop(c, m),
              ),
          ],
        ),
      );
      if (sel != null && mounted) setState(() => _model.text = sel);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _result = '❌ $e';
        });
      }
    }
  }

  Future<void> _test() async {
    final t = _temp();
    if (t.url.isEmpty || t.model.isEmpty) {
      setState(() => _result = '❌ أدخل الرابط والنموذج');
      return;
    }
    setState(() {
      _busy = true;
      _result = '';
    });
    String msg;
    try {
      msg = '✅ يعمل: ${await Gateway.test(t)}';
      _model.text = t.model;
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
    p.name = t.name.isEmpty ? p.name : t.name;
    p.url = t.url.isEmpty ? p.url : t.url;
    p.model = t.model.isEmpty ? p.model : t.model;
    p.key = t.key;
    p.needsKey = t.needsKey;
    p.supportsStream = t.supportsStream;
    if (widget.isNew && !Store.providers.any((x) => x.id == p.id)) {
      Store.providers.add(p);
    }
    await Store.saveProviders();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    Store.providers.removeWhere((x) => x.id == widget.p.id);
    await Store.saveProviders();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final dev = Store.dev || widget.isNew;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'مزود جديد' : p.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (p.hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(p.hint,
                  style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
          if (dev) ...[
            TextField(controller: _name, decoration: _dec('الاسم')),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              textDirection: TextDirection.ltr,
              decoration: _dec('رابط API (chat/completions)'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _model,
            textDirection: TextDirection.ltr,
            decoration: _dec('النموذج (Model)'),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy ? null : _pickModel,
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('جلب النماذج من المزود'),
            ),
          ),
          TextField(
            controller: _key,
            obscureText: _hide,
            enableSuggestions: false,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: _dec(
              'مفتاح API',
              suffix: IconButton(
                icon: Icon(
                    _hide ? Icons.visibility : Icons.visibility_off,
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
              activeTrackColor: kAccent,
              onChanged: (v) => setState(() => _needsKey = v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('بث مباشر (Streaming)'),
            subtitle: const Text('يظهر الرد تدريجياً — أسرع إحساساً'),
            value: _stream,
            activeTrackColor: kAccent,
            onChanged: (v) => setState(() => _stream = v),
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
                  style: TextStyle(color: kDanger)),
            ),
        ],
      ),
    );
  }
}
