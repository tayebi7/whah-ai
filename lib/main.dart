import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'ai_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WahaAI());
}

// ───────────────────────────── الثيم (أزرق خفيف مثل Claude) ─────────────────────────────

class AppColors {
  static const primary = Color(0xFF3B82F6); // أزرق
  static const primaryLight = Color(0xFF60A5FA);
  static const bg = Color(0xFFF0F7FF); // خلفية زرقاء فاتحة جداً
  static const surface = Color(0xFFFFFFFF);
  static const userBubble = Color(0xFFDBEAFE);
  static const assistantBubble = Color(0xFFFFFFFF);
  static const border = Color(0xFFBFDBFE);
  static const sidebar = Color(0xFFE0F2FE);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
}

class WahaAI extends StatelessWidget {
  const WahaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WHAH AI',
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: AppColors.primary,
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: AppColors.sidebar,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const ChatPage(),
    );
  }
}

// ───────────────────────────── النماذج ─────────────────────────────

class AttachedFile {
  final String name;
  final String path;
  final int size;

  const AttachedFile({
    required this.name,
    required this.path,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'size': size,
      };

  factory AttachedFile.fromJson(Map<String, dynamic> json) {
    return AttachedFile(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse(json['size']?.toString() ?? '') ?? 0,
    );
  }

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ChatMessage {
  final String id;
  final String role; // user | assistant | system
  String content;
  final DateTime createdAt;
  final List<AttachedFile> files;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    List<AttachedFile>? files,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        files = files ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'files': files.map((f) => f.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return ChatMessage(
      id: json['id']?.toString(),
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((f) => AttachedFile.fromJson(Map<String, dynamic>.from(f)))
              .toList()
          : [],
    );
  }
}

class ChatHistory {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;

  ChatHistory({
    String? id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return ChatHistory(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? 'محادثة جديدة',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map>()
              .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : [],
    );
  }
}

class ProviderConfig {
  String name;
  String endpoint;
  String apiKey;
  String model;

  ProviderConfig({
    required this.name,
    required this.endpoint,
    this.apiKey = '',
    this.model = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      name: json['name']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
    );
  }
}

class WahaSettings {
  /// single = مزود واحد | gateway = تبديل تلقائي
  String mode;
  String provider;
  String endpoint;
  String apiKey;
  String model;
  bool streamEnabled;
  String systemPrompt;
  /// مزودون يدويون محفوظون بالاسم
  List<ProviderConfig> customProviders;
  /// مفاتيح البوابة لكل مزود مدمج
  Map<String, String> gatewayKeys;
  /// ترتيب تجربة البوابة
  List<String> gatewayOrder;

  WahaSettings({
    this.mode = 'gateway',
    this.provider = 'WHAH Gateway',
    this.endpoint = 'https://api.groq.com/openai/v1',
    this.apiKey = '',
    this.model = 'llama-3.3-70b-versatile',
    this.streamEnabled = true,
    this.systemPrompt =
        'أنت WHAH AI — مساعد ذكي متعدد القدرات. تعرّف تلقائياً على نوع السؤال وأجب بالشكل الأنسب:\n'
        '• برمجة: اكتب كوداً نظيفاً بأي لغة (Python, JS, Dart, Java, C++, SQL...) مع شرح مختصر.\n'
        '• صور: صف الصور المرفقة أو اقترح prompts لتوليد صور.\n'
        '• فيديو/مونتاج: سيناريوهات، خطط تحرير، وصف مشاهد.\n'
        '• مالية/فواتير: حلّل الأرقام والبنود بدقة.\n'
        '• ترجمة: ترجم لأي لغة مع الحفاظ على الأسلوب.\n'
        '• كتب/قصص/تقارير: نظّم المحتوى بعناوين وفقرات جاهزة للتصدير.\n'
        '• وسائل تواصل: منشورات مناسبة للمنصة.\n'
        'أجب بالعربية إلا إذا طُلب غير ذلك. كن واضحاً ومفيداً ومختصراً عند الإمكان.',
    List<ProviderConfig>? customProviders,
    Map<String, String>? gatewayKeys,
    List<String>? gatewayOrder,
  })  : customProviders = customProviders ?? [],
        gatewayKeys = gatewayKeys ?? {},
        gatewayOrder = gatewayOrder ??
            [
              'Groq',
              'Gemini',
              'NVIDIA',
              'Cerebras',
              'OpenRouter',
              'Pollinations',
            ];

  /// تعريفات مزودي البوابة (OpenAI-compatible / HTTPS / JSON / SSE)
  static Map<String, Map<String, String>> get builtInGateways => {
        'Groq': {
          'endpoint': 'https://api.groq.com/openai/v1',
          'model': 'llama-3.3-70b-versatile',
        },
        'Gemini': {
          'endpoint':
              'https://generativelanguage.googleapis.com/v1beta/openai',
          'model': 'gemini-2.0-flash',
        },
        'NVIDIA': {
          'endpoint': 'https://integrate.api.nvidia.com/v1',
          'model': 'meta/llama-3.1-8b-instruct',
        },
        'Cerebras': {
          'endpoint': 'https://api.cerebras.ai/v1',
          'model': 'llama-3.3-70b',
        },
        'OpenRouter': {
          'endpoint': 'https://openrouter.ai/api/v1',
          'model': 'openrouter/free',
        },
        'Pollinations': {
          'endpoint': 'https://text.pollinations.ai',
          'model': 'openai',
        },
      };

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'provider': provider,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'streamEnabled': streamEnabled,
        'systemPrompt': systemPrompt,
        'customProviders': customProviders.map((e) => e.toJson()).toList(),
        'gatewayKeys': gatewayKeys,
        'gatewayOrder': gatewayOrder,
      };

  factory WahaSettings.fromJson(Map<String, dynamic> json) {
    final customs = <ProviderConfig>[];
    final rawList = json['customProviders'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          customs.add(
            ProviderConfig.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final keys = <String, String>{};
    final rawKeys = json['gatewayKeys'];
    if (rawKeys is Map) {
      rawKeys.forEach((k, v) {
        keys[k.toString()] = v?.toString() ?? '';
      });
    }
    final order = <String>[];
    final rawOrder = json['gatewayOrder'];
    if (rawOrder is List) {
      for (final o in rawOrder) {
        order.add(o.toString());
      }
    }
    return WahaSettings(
      mode: json['mode']?.toString() ?? 'gateway',
      provider: json['provider']?.toString() ?? 'WHAH Gateway',
      endpoint: json['endpoint']?.toString() ??
          'https://api.groq.com/openai/v1',
      apiKey: json['apiKey']?.toString() ?? '',
      model: json['model']?.toString() ?? 'llama-3.3-70b-versatile',
      streamEnabled: json['streamEnabled'] as bool? ?? true,
      systemPrompt: json['systemPrompt']?.toString() ??
          'أنت مساعد ذكي اسمه WHAH AI. أجب بالعربية بشكل واضح ومفيد.',
      customProviders: customs,
      gatewayKeys: keys,
      gatewayOrder: order.isEmpty ? null : order,
    );
  }

  /// هل الوضع بوابة ذكية؟
  bool get isGateway =>
      mode == 'gateway' || provider == 'WHAH Gateway' || provider.contains('Gateway');
}

// ───────────────────────────── التخزين المحلي ─────────────────────────────

class LocalStorage {
  static const settingsKey = 'waha_settings_v3';
  static const historyKey = 'waha_history_v2';
  static const appsKey = 'waha_connected_apps';

  static Future<WahaSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(settingsKey);
    if (raw == null || raw.isEmpty) {
      // محاولة قراءة الإصدار القديم
      final old = prefs.getString('waha_settings_v2');
      if (old == null || old.isEmpty) return WahaSettings();
      try {
        return WahaSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(old)),
        );
      } catch (_) {
        return WahaSettings();
      }
    }
    try {
      return WahaSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return WahaSettings();
    }
  }

  static Future<void> saveSettings(WahaSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, jsonEncode(s.toJson()));
  }

  static Future<List<ChatHistory>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((i) => ChatHistory.fromJson(Map<String, dynamic>.from(i)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveHistory(List<ChatHistory> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      historyKey,
      jsonEncode(history.map((c) => c.toJson()).toList()),
    );
  }

  static Future<List<Map<String, String>>> loadApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(appsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, String>.from(
                m.map((k, v) => MapEntry(k.toString(), v.toString())),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveApps(List<Map<String, String>> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appsKey, jsonEncode(apps));
  }
}

// ───────────────────────────── شاشة المحادثة الرئيسية ─────────────────────────────

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  WahaSettings _settings = WahaSettings();
  List<ChatHistory> _history = [];
  late ChatHistory _currentChat;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<AttachedFile> _attachedFiles = [];
  bool _isLoading = false;
  bool _ready = false;

  // Skills — مهارات جاهزة حسب الفئة (موسّعة)
  final List<Map<String, String>> _skills = [
    // برمجة بكل اللغات
    {'title': 'كتابة كود', 'cat': 'برمجة', 'icon': 'code', 'prompt': 'اكتب كوداً نظيفاً وقابلاً للتشغيل مع تعليقات. حدد اللغة تلقائياً حسب الطلب:\n'},
    {'title': 'Python', 'cat': 'برمجة', 'icon': 'code', 'prompt': 'كمطور Python خبير، نفّذ المطلوب بكود حديث وواضح:\n'},
    {'title': 'JavaScript/TS', 'cat': 'برمجة', 'icon': 'code', 'prompt': 'كمطور JavaScript/TypeScript، اكتب كوداً حديثاً (ES2022+):\n'},
    {'title': 'Flutter / Dart', 'cat': 'برمجة', 'icon': 'phone', 'prompt': 'كمطور Flutter خبير، نفّذ المطلوب بكود Dart حديث:\n'},
    {'title': 'Java / Kotlin', 'cat': 'برمجة', 'icon': 'code', 'prompt': 'اكتب كود Java أو Kotlin نظيفاً حسب الطلب:\n'},
    {'title': 'C / C++ / Rust', 'cat': 'برمجة', 'icon': 'code', 'prompt': 'اكتب كوداً آمناً وعالي الأداء بلغة الأنظمة المطلوبة:\n'},
    {'title': 'SQL / قواعد بيانات', 'cat': 'برمجة', 'icon': 'storage', 'prompt': 'اكتب استعلام SQL أو تصميم قاعدة بيانات فعال:\n'},
    {'title': 'إصلاح أخطاء', 'cat': 'برمجة', 'icon': 'bug', 'prompt': 'حلل الخطأ، حدد السبب الجذري، وقدّم الكود المصحح مع شرح:\n'},
    {'title': 'مراجعة كود', 'cat': 'برمجة', 'icon': 'review', 'prompt': 'راجع الكود: أمان، أداء، وضوح، وأفضل الممارسات:\n'},
    // تحليل
    {'title': 'تحليل مشاكل', 'cat': 'تحليل', 'icon': 'analytics', 'prompt': 'حلّل المشكلة خطوة بخطوة: الأسباب، التأثير، الحلول المقترحة:\n'},
    {'title': 'تحليل بيانات', 'cat': 'تحليل', 'icon': 'analytics', 'prompt': 'حلل البيانات: ملخص، إحصائيات، أنماط، واستنتاجات:\n'},
    {'title': 'فواتير وحسابات', 'cat': 'مالية', 'icon': 'table', 'prompt': 'حلّل الفاتورة أو الحسابات: بنود، إجماليات، ملاحظات، وتنظيم:\n'},
    {'title': 'تقارير مالية', 'cat': 'مالية', 'icon': 'report', 'prompt': 'أنشئ تقريراً مالياً واضحاً (إيرادات، مصروفات، رصيد) من البيانات:\n'},
    // مستندات وكتب
    {'title': 'توليد كتاب', 'cat': 'مستندات', 'icon': 'description', 'prompt': 'اكتب كتاباً أو فصلاً منظماً (عناوين، فقرات، خلاصة) عن:\n'},
    {'title': 'قصة قصيرة', 'cat': 'مستندات', 'icon': 'edit', 'prompt': 'اكتب قصة قصيرة مشوّقة ببداية وعقدة ونهاية:\n'},
    {'title': 'تحويل إلى PDF/Markdown', 'cat': 'مستندات', 'icon': 'description', 'prompt': 'حوّل المحتوى إلى Markdown منظم جاهز للتصدير كـ PDF:\n'},
    {'title': 'تلخيص', 'cat': 'مستندات', 'icon': 'summarize', 'prompt': 'لخّص النص بنقاط واضحة مع أهم الأفكار:\n'},
    {'title': 'قالب جاهز', 'cat': 'مستندات', 'icon': 'report', 'prompt': 'أنشئ قالباً احترافياً (عقد، خطاب، تقرير، سيرة) لـ:\n'},
    // ترجمة
    {'title': 'ترجمة لأي لغة', 'cat': 'لغة', 'icon': 'translate', 'prompt': 'ترجم النص بدقة إلى اللغة المطلوبة مع الحفاظ على الأسلوب:\n'},
    {'title': 'ترجمة للعربية', 'cat': 'لغة', 'icon': 'translate', 'prompt': 'ترجم إلى العربية الفصحى بدقة ووضوح:\n'},
    {'title': 'ترجمة للإنجليزية', 'cat': 'لغة', 'icon': 'translate', 'prompt': 'Translate to clear professional English:\n'},
    {'title': 'تدقيق لغوي', 'cat': 'لغة', 'icon': 'spell', 'prompt': 'صحّح الأخطاء اللغوية والإملائية وقدّم النسخة المعدّلة:\n'},
    // إبداع ووسائط
    {'title': 'توليد وصف صورة', 'cat': 'إبداع', 'icon': 'image', 'prompt': 'Write a detailed English image-generation prompt (style, lighting, composition):\n'},
    {'title': 'تحليل صورة', 'cat': 'إبداع', 'icon': 'image', 'prompt': 'صف الصورة المرفقة بالتفصيل: محتوى، نص ظاهر، ألوان، سياق:\n'},
    {'title': 'سيناريو فيديو', 'cat': 'إبداع', 'icon': 'video', 'prompt': 'اكتب سيناريو فيديو (مشاهد، حوار، نص شاشة، مدة تقريبية):\n'},
    {'title': 'مونتاج / تحرير', 'cat': 'إبداع', 'icon': 'video', 'prompt': 'اقترح خطة مونتاج وتحرير (تسلسل، انتقالات، مؤثرات) لـ:\n'},
    {'title': 'وسائل تواصل', 'cat': 'إبداع', 'icon': 'lightbulb', 'prompt': 'اكتب منشورات مناسبة لوسائل التواصل (تويتر، إنستغرام، لينكدإن) عن:\n'},
    // تطوير
    {'title': 'README GitHub', 'cat': 'تطوير', 'icon': 'github', 'prompt': 'اكتب README.md احترافي (عربي/إنجليزي) للمشروع:\n'},
    {'title': 'API / JSON', 'cat': 'تطوير', 'icon': 'api', 'prompt': 'صمّم REST API بصيغة JSON مع أمثلة طلب واستجابة:\n'},
    {'title': 'خطة تطبيق', 'cat': 'تطوير', 'icon': 'app', 'prompt': 'ضع خطة تطبيق (شاشات، ميزات، تقنية، مراحل) للفكرة:\n'},
  ];


  @override
  void initState() {
    super.initState();
    _currentChat = ChatHistory(title: 'محادثة جديدة');
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final settings = await LocalStorage.loadSettings();
    final history = await LocalStorage.loadHistory();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _history = history;
      if (history.isNotEmpty) {
        _currentChat = history.first;
      }
      _ready = true;
    });
  }

  String _makeTitle(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return 'محادثة جديدة';
    if (clean.length <= 40) return clean;
    return '${clean.substring(0, 40)}...';
  }

  Future<void> _saveCurrentChat() async {
    _currentChat.updatedAt = DateTime.now();
    final index = _history.indexWhere((c) => c.id == _currentChat.id);
    if (index >= 0) {
      _history[index] = _currentChat;
    } else {
      _history.insert(0, _currentChat);
    }
    // رتب حسب آخر تحديث
    _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await LocalStorage.saveHistory(_history);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ─── اختيار ملفات (file_picker 13) ───
  Future<void> _pickFiles() async {
    try {
      // API الجديد في file_picker 13: يعيد List<PlatformFile> مباشرة
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) return;

      setState(() {
        for (final file in files) {
          final size = file.lengthSync() ?? 0;
          _attachedFiles.add(
            AttachedFile(
              name: file.name,
              path: file.path ?? '',
              size: size,
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار الملفات: $e')),
      );
    }
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم النسخ إلى الحافظة'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final current = _controller.text;
    final selection = _controller.selection;
    final start = selection.start >= 0 ? selection.start : current.length;
    final end = selection.end >= 0 ? selection.end : current.length;
    final newText = current.replaceRange(start, end, data.text!);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: start + data.text!.length,
    );
    setState(() {});
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<WahaSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(settings: _settings),
      ),
    );
    if (result == null) return;
    setState(() => _settings = result);
    await LocalStorage.saveSettings(_settings);
  }

  void _newChat() {
    setState(() {
      _currentChat = ChatHistory(title: 'محادثة جديدة');
      _attachedFiles.clear();
      _controller.clear();
    });
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  void _selectChat(ChatHistory chat) {
    setState(() {
      _currentChat = chat;
      _attachedFiles.clear();
      _controller.clear();
    });
    Navigator.pop(context);
  }

  Future<void> _deleteChat(ChatHistory chat) async {
    setState(() {
      _history.removeWhere((c) => c.id == chat.id);
      if (_currentChat.id == chat.id) {
        _currentChat = ChatHistory(title: 'محادثة جديدة');
      }
    });
    await LocalStorage.saveHistory(_history);
  }

  void _applySkill(Map<String, String> skill) {
    final prompt = skill['prompt'] ?? '';
    _controller.text = prompt;
    _controller.selection = TextSelection.collapsed(offset: prompt.length);
    _focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('مهارة: ${skill['title'] ?? ""} — أكمل الطلب ثم أرسل'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;
    if (_isLoading) return;

    // تحقق من الإعدادات
    if (!_settings.isGateway &&
        _settings.apiKey.trim().isEmpty &&
        !_settings.provider.contains('بدون مفتاح') &&
        !_settings.provider.contains('Pollinations') &&
        !_settings.provider.contains('يدوي') &&
        _settings.provider != 'Custom') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('أدخل مفتاح API من الإعدادات أولاً'),
          action: SnackBarAction(
            label: 'الإعدادات',
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }

    final userText = text.isEmpty ? 'حلل الملفات المرفقة.' : text;
    final attached = List<AttachedFile>.from(_attachedFiles);

    final displayText = attached.isEmpty
        ? userText
        : '$userText\n\nالملفات المرفقة:\n${attached.map((f) => '• ${f.name} (${f.sizeLabel})').join('\n')}';

    final userMessage = ChatMessage(
      role: 'user',
      content: displayText,
      files: attached,
    );

    setState(() {
      if (_currentChat.messages.isEmpty) {
        _currentChat.title = _makeTitle(userText);
      }
      _currentChat.messages.add(userMessage);
      _attachedFiles.clear();
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    final assistantMessage = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _currentChat.messages.add(assistantMessage);
    });

    try {
      // بناء الرسائل مع system prompt
      final messages = <Map<String, dynamic>>[];

      if (_settings.systemPrompt.trim().isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': _settings.systemPrompt.trim(),
        });
      }

      for (final m in _currentChat.messages) {
        if (m.role == 'assistant' && m.content.trim().isEmpty) continue;
        if (m.content.trim().isEmpty && m.files.isEmpty) continue;

        // دعم الصور (vision) — إرسال base64 للنماذج الداعمة
        final imageFiles = m.files.where((f) {
          final n = f.name.toLowerCase();
          return n.endsWith('.png') ||
              n.endsWith('.jpg') ||
              n.endsWith('.jpeg') ||
              n.endsWith('.webp') ||
              n.endsWith('.gif');
        }).toList();

        if (imageFiles.isNotEmpty && m.role == 'user') {
          final parts = <Map<String, dynamic>>[];
          parts.add({'type': 'text', 'text': m.content});
          for (final f in imageFiles) {
            try {
              if (f.path.isEmpty) continue;
              final bytes = await File(f.path).readAsBytes();
              // حدّ أقصى ~4MB للصورة لتجنب تجاوز حدود API
              if (bytes.length > 4 * 1024 * 1024) continue;
              final b64 = base64Encode(bytes);
              final mime = f.name.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : f.name.toLowerCase().endsWith('.webp')
                      ? 'image/webp'
                      : f.name.toLowerCase().endsWith('.gif')
                          ? 'image/gif'
                          : 'image/jpeg';
              parts.add({
                'type': 'image_url',
                'image_url': {'url': 'data:$mime;base64,$b64'},
              });
            } catch (_) {
              // تجاهل الصور غير القابلة للقراءة
            }
          }
          messages.add({'role': m.role, 'content': parts});
        } else {
          messages.add({'role': m.role, 'content': m.content});
        }
      }

      // محاولات: بوابة ذكية (تبديل تلقائي) أو مزود واحد
      final attempts = <AIService>[];

      if (_settings.isGateway) {
        for (final name in _settings.gatewayOrder) {
          final preset = WahaSettings.builtInGateways[name];
          if (preset == null) continue;
          final key = _settings.gatewayKeys[name] ?? '';
          if (key.isEmpty && name != 'Pollinations') continue;
          attempts.add(AIService(
            endpoint: preset['endpoint']!,
            apiKey: key,
            model: preset['model']!,
            provider: name,
          ));
        }
        if (attempts.isEmpty) {
          final p = WahaSettings.builtInGateways['Pollinations']!;
          attempts.add(AIService(
            endpoint: p['endpoint']!,
            apiKey: '',
            model: p['model']!,
            provider: 'Pollinations',
          ));
        }
      } else {
        attempts.add(AIService(
          endpoint: _settings.endpoint,
          apiKey: _settings.apiKey,
          model: _settings.model,
          provider: _settings.provider,
        ));
      }

      Object? lastError;
      var success = false;
      for (final service in attempts) {
        try {
          final result = await service.sendSmart(
            messages: messages,
            preferStream: _settings.streamEnabled,
            onChunk: (chunk) {
              if (!mounted || chunk.isEmpty) return;
              setState(() {
                assistantMessage.content += chunk;
              });
              _scrollToBottom();
            },
          );
          if (result.trim().isNotEmpty ||
              assistantMessage.content.trim().isNotEmpty) {
            success = true;
            break;
          }
        } catch (e) {
          lastError = e;
          if (mounted) {
            setState(() => assistantMessage.content = '');
          }
        }
      }

      if (!success) {
        throw lastError ?? Exception('فشلت جميع مزودي البوابة');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          assistantMessage.content =
              '⚠️ حدث خطأ أثناء الاتصال:\n\n$e\n\n'
              'تحقق من:\n'
              '• مفتاح API صحيح وغير منتهٍ\n'
              '• Endpoint: ${_settings.endpoint}\n'
              '• النموذج: ${_settings.model}\n'
              '• المزود: ${_settings.provider}\n'
              '• اتصال الإنترنت مفعّل للتطبيق\n\n'
              'نصيحة: جرّب OpenRouter مع نموذج openai/gpt-4o-mini '
              'واضغط «اختبار الاتصال» في الإعدادات.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      await _saveCurrentChat();
      _scrollToBottom();
    }
  }

  // ─── الواجهة ───

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome, size: 36, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    'WHAH AI',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'مساعد ذكاء اصطناعي متعدد',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('محادثة جديدة'),
              onTap: _newChat,
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('الإعدادات والمزودين'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Skills والربط'),
              onTap: () {
                Navigator.pop(context);
                _showSkillsSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('التطبيقات المرتبطة'),
              onTap: () {
                Navigator.pop(context);
                _showConnectedApps();
              },
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'المحادثات السابقة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _history.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد محادثات محفوظة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final chat = _history[index];
                        final selected = chat.id == _currentChat.id;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: AppColors.userBubble,
                          leading: const Icon(Icons.chat_bubble_outline, size: 20),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteChat(chat),
                          ),
                          onTap: () => _selectChat(chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSkillsSheet() {
    final cats = <String>[];
    for (final s in _skills) {
      final c = s['cat'] ?? 'عام';
      if (!cats.contains(c)) cats.add(c);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Text(
                  'Skills — المهارات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'اختر مهارة لملء صندوق الكتابة، ثم أكمل طلبك وأرسل.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...cats.map((cat) {
                  final items =
                      _skills.where((s) => (s['cat'] ?? 'عام') == cat).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text(
                          cat,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: items.map((s) {
                          return ActionChip(
                            avatar: Icon(_skillIcon(s['icon']), size: 18),
                            label: Text(s['title'] ?? ''),
                            backgroundColor: AppColors.bg,
                            side: const BorderSide(color: AppColors.border),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _applySkill(s);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  IconData _skillIcon(String? name) {
    switch (name) {
      case 'code':
        return Icons.code;
      case 'bug':
        return Icons.bug_report_outlined;
      case 'review':
        return Icons.rate_review_outlined;
      case 'phone':
        return Icons.phone_android;
      case 'analytics':
        return Icons.analytics_outlined;
      case 'table':
        return Icons.table_chart_outlined;
      case 'storage':
        return Icons.storage_outlined;
      case 'description':
        return Icons.description_outlined;
      case 'summarize':
        return Icons.short_text;
      case 'edit':
        return Icons.edit_note;
      case 'report':
        return Icons.article_outlined;
      case 'translate':
        return Icons.translate;
      case 'spell':
        return Icons.spellcheck;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'github':
        return Icons.merge_type;
      case 'api':
        return Icons.api_outlined;
      case 'app':
        return Icons.apps_outlined;
      default:
        return Icons.auto_awesome;
    }
  }

  void _showConnectedApps() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const ConnectedAppsSheet(),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: isUser ? AppColors.userBubble : AppColors.assistantBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(color: AppColors.border.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person_outline : Icons.auto_awesome,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isUser ? 'أنت' : 'WHAH AI',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (message.content.isNotEmpty)
              SelectableRegion(
                focusNode: FocusNode(),
                selectionControls: materialTextSelectionControls,
                child: MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: AppColors.textPrimary,
                    ),
                    code: TextStyle(
                      backgroundColor: const Color(0xFFEFF6FF),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    codeblockPadding: const EdgeInsets.all(12),
                  ),
                  onTapLink: (text, href, title) async {
                    if (href == null) return;
                    final uri = Uri.tryParse(href);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            if (message.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...message.files.map(
                (file) => Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${file.name}  (${file.sizeLabel})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!isUser && message.content.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'نسخ',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyText(message.content),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.userBubble,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'مرحباً بك في WHAH AI',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'مساعد ذكي للبرمجة، التحليل، التحويل، والإبداع',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _skills.map((s) {
                return ActionChip(
                  avatar: Icon(_skillIcon(s['icon']), size: 18),
                  label: Text(s['title']!),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => _applySkill(s),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            if (_settings.apiKey.isEmpty)
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.key),
                label: const Text('إعداد مزود الذكاء الاصطناعي'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachedFiles.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _attachedFiles[i];
                    return Chip(
                      avatar: const Icon(Icons.insert_drive_file, size: 16),
                      label: Text(
                        f.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _attachedFiles.removeAt(i));
                      },
                    );
                  },
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'إرفاق ملف',
                  onPressed: _isLoading ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  tooltip: 'لصق من الحافظة',
                  onPressed: _isLoading ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك هنا...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentChat.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              _settings.isGateway
                  ? 'بوابة ذكية · تبديل تلقائي'
                  : 'المزود: ${_settings.provider}',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Skills',
            onPressed: _showSkillsSheet,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'محادثة جديدة',
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _currentChat.messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _currentChat.messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessage(_currentChat.messages[index]);
                    },
                  ),
          ),
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
            ),
          _buildComposer(),
        ],
      ),
    );
  }
}

// ───────────────────────────── التطبيقات المرتبطة ─────────────────────────────

class ConnectedAppsSheet extends StatefulWidget {
  const ConnectedAppsSheet({super.key});

  @override
  State<ConnectedAppsSheet> createState() => _ConnectedAppsSheetState();
}

class _ConnectedAppsSheetState extends State<ConnectedAppsSheet> {
  List<Map<String, String>> _apps = [];
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await LocalStorage.loadApps();
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    setState(() {
      _apps.add({'name': name, 'url': url});
      _nameCtrl.clear();
      _urlCtrl.clear();
    });
    await LocalStorage.saveApps(_apps);
  }

  Future<void> _remove(int i) async {
    setState(() => _apps.removeAt(i));
    await LocalStorage.saveApps(_apps);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'التطبيقات المرتبطة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'أضف اسم التطبيق ورابطه (مثل GitHub أو أي خدمة)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم التطبيق',
              hintText: 'GitHub',
              prefixIcon: Icon(Icons.apps),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'الرابط',
              hintText: 'https://github.com/...',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('إضافة وربط'),
          ),
          const SizedBox(height: 16),
          if (_apps.isEmpty)
            const Text(
              'لا توجد تطبيقات مرتبطة بعد',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ...List.generate(_apps.length, (i) {
              final app = _apps[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link),
                title: Text(app['name'] ?? ''),
                subtitle: Text(
                  app['url'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => _open(app['url'] ?? ''),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _remove(i),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ───────────────────────────── شاشة الإعدادات ─────────────────────────────


class _GatewayKeyTile extends StatefulWidget {
  final String name;
  final bool enabled;
  final String initialKey;
  final ValueChanged<String> onChanged;

  const _GatewayKeyTile({
    required this.name,
    required this.enabled,
    required this.initialKey,
    required this.onChanged,
  });

  @override
  State<_GatewayKeyTile> createState() => _GatewayKeyTileState();
}

class _GatewayKeyTileState extends State<_GatewayKeyTile> {
  late TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialKey);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c,
        enabled: widget.enabled,
        obscureText: true,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.enabled
              ? '${widget.name} API Key'
              : '${widget.name} (بدون مفتاح)',
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: const Icon(Icons.key_outlined, size: 20),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final WahaSettings settings;

  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _endpointController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _systemController;
  late TextEditingController _customNameController;
  late TextEditingController _addEndpointController;
  late TextEditingController _addApiKeyController;
  late TextEditingController _addModelController;
  late String _provider;
  late String _mode;
  late bool _streamEnabled;
  late List<ProviderConfig> _customProviders;
  late Map<String, String> _gatewayKeys;
  late List<String> _gatewayOrder;
  bool _testing = false;
  String? _testResult;
  bool _showAddCustom = false;
  bool _obscureApiKey = true;
  bool _obscureAddApiKey = true;

  static const _singleProviders = {
    'مجاني بدون مفتاح (Pollinations)': {
      'endpoint': 'https://text.pollinations.ai',
      'model': 'openai',
    },
    'Groq (مجاني)': {
      'endpoint': 'https://api.groq.com/openai/v1',
      'model': 'llama-3.3-70b-versatile',
    },
    'OpenRouter (مجاني)': {
      'endpoint': 'https://openrouter.ai/api/v1',
      'model': 'openrouter/free',
    },
    'Google Gemini (مجاني)': {
      'endpoint':
          'https://generativelanguage.googleapis.com/v1beta/openai',
      'model': 'gemini-2.0-flash',
    },
    'DeepSeek': {
      'endpoint': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
    },
    'Mistral': {
      'endpoint': 'https://api.mistral.ai/v1',
      'model': 'mistral-small-latest',
    },
    'OpenAI': {
      'endpoint': 'https://api.openai.com/v1',
      'model': 'gpt-4o-mini',
    },
    'يدوي (Custom)': {
      'endpoint': '',
      'model': '',
    },
  };

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _provider = s.provider;
    _mode = s.isGateway ? 'gateway' : 'single';
    _streamEnabled = s.streamEnabled;
    _customProviders = List<ProviderConfig>.from(s.customProviders);
    _gatewayKeys = Map<String, String>.from(s.gatewayKeys);
    _gatewayOrder = List<String>.from(s.gatewayOrder);
    _endpointController = TextEditingController(text: s.endpoint);
    _apiKeyController = TextEditingController(text: s.apiKey);
    _modelController = TextEditingController(text: s.model);
    _systemController = TextEditingController(text: s.systemPrompt);
    _customNameController = TextEditingController();
    // حقول الإضافة دائماً فارغة
    _addEndpointController = TextEditingController();
    _addApiKeyController = TextEditingController();
    _addModelController = TextEditingController();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemController.dispose();
    _customNameController.dispose();
    _addEndpointController.dispose();
    _addApiKeyController.dispose();
    _addModelController.dispose();
    super.dispose();
  }

  List<String> get _allProviderNames {
    final names = <String>['WHAH Gateway'];
    names.addAll(_singleProviders.keys);
    for (final c in _customProviders) {
      if (c.name.isNotEmpty) names.add(c.name);
    }
    return names;
  }

  void _applyProvider(String provider) {
    setState(() {
      _provider = provider;
      if (provider == 'WHAH Gateway') {
        _mode = 'gateway';
        return;
      }
      _mode = 'single';
      final preset = _singleProviders[provider];
      if (preset != null) {
        if (preset['endpoint']!.isNotEmpty) {
          _endpointController.text = preset['endpoint']!;
        }
        if (preset['model']!.isNotEmpty) {
          _modelController.text = preset['model']!;
        }
        if (provider.contains('بدون مفتاح') ||
            provider.contains('Pollinations')) {
          _apiKeyController.clear();
        }
        return;
      }
      // مزود يدوي محفوظ
      for (final c in _customProviders) {
        if (c.name == provider) {
          _endpointController.text = c.endpoint;
          _apiKeyController.text = c.apiKey;
          _modelController.text = c.model;
          break;
        }
      }
    });
  }

  void _saveCustomProvider() {
    final name = _customNameController.text.trim();
    final endpoint = _addEndpointController.text.trim();
    final model = _addModelController.text.trim();
    final key = _addApiKeyController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المزود أولاً')),
      );
      return;
    }
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رابط API للمزود')),
      );
      return;
    }
    setState(() {
      final idx = _customProviders.indexWhere((e) => e.name == name);
      final cfg = ProviderConfig(
        name: name,
        endpoint: endpoint,
        apiKey: key,
        model: model.isEmpty ? 'gpt-4o-mini' : model,
      );
      if (idx >= 0) {
        _customProviders[idx] = cfg;
      } else {
        _customProviders.add(cfg);
      }
      // تطبيق المزود الجديد مباشرة
      _provider = name;
      _mode = 'single';
      _endpointController.text = cfg.endpoint;
      _apiKeyController.text = cfg.apiKey;
      _modelController.text = cfg.model;
      // إفراغ حقول الإضافة
      _showAddCustom = false;
      _customNameController.clear();
      _addEndpointController.clear();
      _addApiKeyController.clear();
      _addModelController.clear();
      _obscureAddApiKey = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ المزود «$name» مع المزودين')),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      if (_mode == 'gateway') {
        // اختبر أول مزود متاح في البوابة
        String? err;
        var any = false;
        for (final name in _gatewayOrder) {
          final preset = WahaSettings.builtInGateways[name];
          if (preset == null) continue;
          final key = _gatewayKeys[name] ?? '';
          if (key.isEmpty && name != 'Pollinations') continue;
          any = true;
          final service = AIService(
            endpoint: preset['endpoint']!,
            apiKey: key,
            model: preset['model']!,
            provider: name,
          );
          final e = await service.testConnectionDetailed();
          if (e == null) {
            setState(() => _testResult = '✅ البوابة تعمل — نجح: $name');
            return;
          }
          err = e;
        }
        if (!any) {
          setState(() =>
              _testResult = '❌ أضف مفتاحاً لمزود واحد على الأقل في البوابة');
        } else {
          setState(() => _testResult = '❌ فشل الاتصال: ${err ?? ""}');
        }
        return;
      }

      final endpoint = _endpointController.text.trim();
      final apiKey = _apiKeyController.text.trim();
      final model = _modelController.text.trim();
      final noKeyOk = _provider.contains('بدون مفتاح') ||
          _provider.contains('Pollinations') ||
          _provider.contains('يدوي');

      if (endpoint.isEmpty) {
        setState(() => _testResult = '❌ أدخل الرابط أولاً');
        return;
      }
      if (apiKey.isEmpty && !noKeyOk) {
        setState(() => _testResult = '❌ أدخل API Key');
        return;
      }
      if (model.isEmpty) {
        setState(() => _testResult = '❌ أدخل اسم النموذج');
        return;
      }

      final service = AIService(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        provider: _provider,
      );
      final err = await service.testConnectionDetailed();
      setState(() {
        _testResult = err == null ? '✅ الاتصال ناجح' : '❌ فشل الاتصال:\n$err';
      });
    } catch (e) {
      setState(() => _testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final settings = WahaSettings(
      mode: _mode,
      provider: _mode == 'gateway' ? 'WHAH Gateway' : _provider,
      endpoint: _endpointController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      streamEnabled: _streamEnabled,
      systemPrompt: _systemController.text.trim(),
      customProviders: _customProviders,
      gatewayKeys: _gatewayKeys,
      gatewayOrder: _gatewayOrder,
    );
    await LocalStorage.saveSettings(settings);
    if (!mounted) return;
    Navigator.pop(context, settings);
  }

  Widget _ltrField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintTextDirection: TextDirection.ltr,
        border: const OutlineInputBorder(),
        prefixIcon: icon != null ? Icon(icon) : null,
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الذكاء الاصطناعي'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // شريط حفظ ثابت أسفل الشاشة (بعيد عن أزرار النظام)
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'اختبار...' : 'اختبار'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // وضع التشغيل
          const Text('وضع التشغيل',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'gateway',
                label: Text('بوابة ذكية'),
                icon: Icon(Icons.hub_outlined, size: 18),
              ),
              ButtonSegment(
                value: 'single',
                label: Text('مزود واحد'),
                icon: Icon(Icons.smart_toy_outlined, size: 18),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() {
                _mode = s.first;
                if (_mode == 'gateway') {
                  _provider = 'WHAH Gateway';
                }
              });
            },
          ),
          const SizedBox(height: 16),

          if (_mode == 'gateway') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'المستخدم ← WHAH Gateway ← اختيار تلقائي\n'
                'Groq → Gemini → NVIDIA → Cerebras → OpenRouter → Pollinations\n'
                'البروتوكول: HTTPS + REST + JSON + OpenAI API + SSE',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
            const SizedBox(height: 12),
            const Text('مفاتيح مزودي البوابة',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...WahaSettings.builtInGateways.entries.map((e) {
              final name = e.key;
              final needsKey = name != 'Pollinations';
              return _GatewayKeyTile(
                name: name,
                enabled: needsKey,
                initialKey: _gatewayKeys[name] ?? '',
                onChanged: (v) => _gatewayKeys[name] = v,
              );
            }),
          ] else ...[
            // قائمة مزودين قريبة من الأعلى
            const Text('المزود',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _allProviderNames.contains(_provider)
                  ? _provider
                  : _allProviderNames.first,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cloud_outlined),
                isDense: true,
              ),
              items: _allProviderNames
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _applyProvider(v);
              },
            ),
            const SizedBox(height: 12),

            // إضافة مزود يدوي — حقول فارغة دائماً
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showAddCustom = !_showAddCustom;
                  if (_showAddCustom) {
                    // إفراغ الحقول عند الفتح
                    _customNameController.clear();
                    _addEndpointController.clear();
                    _addApiKeyController.clear();
                    _addModelController.clear();
                    _obscureAddApiKey = true;
                  }
                });
              },
              icon: Icon(_showAddCustom ? Icons.close : Icons.add),
              label: Text(
                _showAddCustom ? 'إلغاء الإضافة' : 'إضافة مزود جديد',
              ),
            ),
            if (_showAddCustom) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'مزود جديد (الحقول فارغة)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customNameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المزود',
                        hintText: 'مثال: شركتي / سيرفري / Claude API',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addEndpointController,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: 'API Endpoint (HTTPS)',
                        hintText: 'https://api.example.com/v1',
                        hintTextDirection: TextDirection.ltr,
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addApiKeyController,
                      obscureText: _obscureAddApiKey,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        hintTextDirection: TextDirection.ltr,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.key_outlined),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureAddApiKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureAddApiKey = !_obscureAddApiKey,
                          ),
                          tooltip: _obscureAddApiKey
                              ? 'إظهار المفتاح'
                              : 'إخفاء المفتاح',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addModelController,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: 'Model (اختياري)',
                        hintText: 'gpt-4o-mini',
                        hintTextDirection: TextDirection.ltr,
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.smart_toy_outlined),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saveCustomProvider,
                      icon: const Icon(Icons.playlist_add_check),
                      label: const Text('حفظ المزود في القائمة'),
                    ),
                  ],
                ),
              ),
            ],
            if (_customProviders.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('المزودون المحفوظون',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _customProviders.map((c) {
                  return InputChip(
                    label: Text(c.name),
                    selected: _provider == c.name,
                    onSelected: (_) => _applyProvider(c.name),
                    onDeleted: () {
                      setState(() {
                        _customProviders.removeWhere((e) => e.name == c.name);
                        if (_provider == c.name) {
                          _provider = 'Groq (مجاني)';
                          _applyProvider(_provider);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            _ltrField(
              controller: _endpointController,
              label: 'API Endpoint (HTTPS)',
              hint: 'https://api.groq.com/openai/v1',
              keyboardType: TextInputType.url,
              icon: Icons.link,
            ),
            const SizedBox(height: 10),
            // API Key مع إمكانية الإظهار
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                hintTextDirection: TextDirection.ltr,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key_outlined),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                  tooltip: _obscureApiKey ? 'إظهار المفتاح' : 'إخفاء المفتاح',
                ),
              ),
            ),
            const SizedBox(height: 10),
            _ltrField(
              controller: _modelController,
              label: 'Model',
              hint: 'llama-3.3-70b-versatile',
              icon: Icons.smart_toy_outlined,
            ),
          ],

          const SizedBox(height: 14),
          TextField(
            controller: _systemController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'System Prompt',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.psychology_outlined),
              isDense: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('البث المباشر (SSE Streaming)'),
            subtitle: const Text('OpenAI-compatible + Server-Sent Events'),
            value: _streamEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _streamEnabled = v),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('✅')
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'البروتوكول: HTTPS · REST API · JSON · OpenAI-compatible · SSE\n'
              'البوابة تجرب المزودين بالترتيب وتسقط تلقائياً عند الفشل.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
          // مساحة إضافية فوق شريط الحفظ
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
