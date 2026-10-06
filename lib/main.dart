import 'dart:convert';

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

class WahaSettings {
  String provider;
  String endpoint;
  String apiKey;
  String model;
  bool streamEnabled;
  String systemPrompt;

  WahaSettings({
    this.provider = 'مجاني بدون مفتاح (Pollinations)',
    this.endpoint = 'https://text.pollinations.ai',
    this.apiKey = '',
    this.model = 'openai',
    this.streamEnabled = true,
    this.systemPrompt =
        'أنت مساعد ذكي اسمه WHAH AI. أجب بالعربية بشكل واضح ومفيد. يمكنك كتابة كود، تحليل بيانات، وتحويل مستندات.',
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'streamEnabled': streamEnabled,
        'systemPrompt': systemPrompt,
      };

  factory WahaSettings.fromJson(Map<String, dynamic> json) {
    return WahaSettings(
      provider: json['provider']?.toString() ?? 'OpenRouter (مجاني)',
      endpoint: json['endpoint']?.toString() ??
          'https://openrouter.ai/api/v1',
      apiKey: json['apiKey']?.toString() ?? '',
      model: json['model']?.toString() ?? 'openrouter/free',
      streamEnabled: json['streamEnabled'] as bool? ?? true,
      systemPrompt: json['systemPrompt']?.toString() ??
          'أنت مساعد ذكي اسمه WHAH AI. أجب بالعربية بشكل واضح ومفيد.',
    );
  }
}

// ───────────────────────────── التخزين المحلي ─────────────────────────────

class LocalStorage {
  static const settingsKey = 'waha_settings_v2';
  static const historyKey = 'waha_history_v2';
  static const appsKey = 'waha_connected_apps';

  static Future<WahaSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(settingsKey);
    if (raw == null || raw.isEmpty) return WahaSettings();
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      // ترحيل الأسماء القديمة
      final p = map['provider']?.toString() ?? '';
      if (p == 'Gateway' || p == 'Custom') {
        map['provider'] = 'يدوي (Custom)';
      }
      if (p == 'OpenRouter') {
        map['provider'] = 'OpenRouter (مجاني)';
      }
      if (p == 'Groq') {
        map['provider'] = 'Groq (مجاني)';
      }
      return WahaSettings.fromJson(map);
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

  // Skills سريعة
  final List<Map<String, String>> _skills = [
    {
      'title': 'برمجة',
      'prompt': 'اكتب كوداً نظيفاً مع شرح مختصر:',
      'icon': 'code',
    },
    {
      'title': 'تحليل بيانات',
      'prompt': 'حلل البيانات التالية وأعطني ملخصاً وإحصائيات:',
      'icon': 'analytics',
    },
    {
      'title': 'تحويل مستند',
      'prompt': 'حوّل المحتوى التالي إلى صيغة منظمة (Markdown):',
      'icon': 'description',
    },
    {
      'title': 'تلخيص',
      'prompt': 'لخّص النص التالي بشكل واضح ومختصر:',
      'icon': 'summarize',
    },
    {
      'title': 'ترجمة',
      'prompt': 'ترجم النص التالي إلى العربية بدقة:',
      'icon': 'translate',
    },
    {
      'title': 'أفكار',
      'prompt': 'اقترح أفكاراً إبداعية حول:',
      'icon': 'lightbulb',
    },
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
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;
    if (_isLoading) return;

    // تحقق من الإعدادات
    final noKeyOk = _settings.provider.contains('بدون مفتاح') ||
        _settings.provider.contains('Pollinations') ||
        _settings.provider.contains('يدوي') ||
        _settings.provider == 'Custom';
    if (_settings.apiKey.trim().isEmpty && !noKeyOk) {
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
      final service = AIService(
        endpoint: _settings.endpoint,
        apiKey: _settings.apiKey,
        model: _settings.model,
        provider: _settings.provider,
      );

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
        if (m.content.trim().isEmpty) continue;
        messages.add({
          'role': m.role,
          'content': m.content,
        });
      }

      // مسار سريع: بث فوري مع سقوط تلقائي للطلب العادي
      await service.sendSmart(
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Skills — مهارات سريعة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _skills.map((s) {
                  return ActionChip(
                    avatar: Icon(_skillIcon(s['icon']), size: 18),
                    label: Text(s['title']!),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _applySkill(s);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'اضغط على مهارة لإدخال الأمر في صندوق الكتابة.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _skillIcon(String? name) {
    switch (name) {
      case 'code':
        return Icons.code;
      case 'analytics':
        return Icons.analytics_outlined;
      case 'description':
        return Icons.description_outlined;
      case 'summarize':
        return Icons.short_text;
      case 'translate':
        return Icons.translate;
      case 'lightbulb':
        return Icons.lightbulb_outline;
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
        title: Text(
          _currentChat.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
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
  late String _provider;
  late bool _streamEnabled;
  bool _testing = false;
  String? _testResult;

  static const _providers = {
    // —— بدون مفتاح API ——
    'مجاني بدون مفتاح (Pollinations)': {
      'endpoint': 'https://text.pollinations.ai',
      'model': 'openai',
    },
    // —— مجاني بمفتاح مجاني ——
    'Groq (مجاني)': {
      'endpoint': 'https://api.groq.com/openai/v1',
      'model': 'llama-3.3-70b-versatile',
    },
    'OpenRouter (مجاني)': {
      'endpoint': 'https://openrouter.ai/api/v1',
      'model': 'openrouter/free',
    },
    'Google Gemini (مجاني)': {
      'endpoint': 'https://generativelanguage.googleapis.com/v1beta/openai',
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
    'OpenRouter': {
      'endpoint': 'https://openrouter.ai/api/v1',
      'model': 'openai/gpt-4o-mini',
    },
    'يدوي (Custom)': {
      'endpoint': '',
      'model': '',
    },
  };

  @override
  void initState() {
    super.initState();
    _provider = widget.settings.provider;
    _streamEnabled = widget.settings.streamEnabled;
    _endpointController =
        TextEditingController(text: widget.settings.endpoint);
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
    _modelController = TextEditingController(text: widget.settings.model);
    _systemController =
        TextEditingController(text: widget.settings.systemPrompt);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemController.dispose();
    super.dispose();
  }

  void _applyProvider(String provider) {
    setState(() {
      _provider = provider;
      final preset = _providers[provider];
      if (preset != null) {
        if (preset['endpoint']!.isNotEmpty) {
          _endpointController.value = TextEditingValue(
            text: preset['endpoint']!,
            selection: TextSelection.collapsed(offset: preset['endpoint']!.length),
          );
        }
        if (preset['model']!.isNotEmpty) {
          _modelController.value = TextEditingValue(
            text: preset['model']!,
            selection: TextSelection.collapsed(offset: preset['model']!.length),
          );
        }
        // مزود بدون مفتاح: امسح المفتاح
        if (provider.contains('بدون مفتاح') || provider.contains('Pollinations')) {
          _apiKeyController.clear();
        }
      }
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final endpoint = _endpointController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (endpoint.isEmpty) {
      setState(() {
        _testResult = '❌ أدخل عنوان API أولاً';
        _testing = false;
      });
      return;
    }
    if (model.isEmpty) {
      setState(() {
        _testResult = '❌ أدخل اسم النموذج أولاً';
        _testing = false;
      });
      return;
    }
    final noKeyOk = _provider.contains('بدون مفتاح') ||
        _provider.contains('Pollinations') ||
        _provider.contains('يدوي') ||
        _provider == 'Custom';
    if (apiKey.isEmpty && !noKeyOk) {
      setState(() {
        _testResult = '❌ أدخل مفتاح API أولاً';
        _testing = false;
      });
      return;
    }

    final service = AIService(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      provider: _provider,
    );

    try {
      final err = await service.testConnectionDetailed();
      setState(() {
        _testResult = err == null
            ? '✅ الاتصال ناجح — يمكنك الحفظ والبدء'
            : '❌ فشل الاتصال:\n$err';
      });
    } catch (e) {
      setState(() {
        _testResult = '❌ $e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  void _save() {
    Navigator.pop(
      context,
      WahaSettings(
        provider: _provider,
        endpoint: _endpointController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
        streamEnabled: _streamEnabled,
        systemPrompt: _systemController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الذكاء الاصطناعي'),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'مزود الذكاء الاصطناعي',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provider,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud_outlined),
            ),
            items: _providers.keys
                .map(
                  (p) => DropdownMenuItem(value: p, child: Text(p)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _applyProvider(v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointController,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            keyboardType: TextInputType.url,
            style: const TextStyle(
              fontFamily: 'monospace',
              letterSpacing: 0,
            ),
            decoration: const InputDecoration(
              labelText: 'API Endpoint (رابط المزود)',
              hintText: 'https://openrouter.ai/api/v1',
              hintTextDirection: TextDirection.ltr,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
              helperText:
                  'اكتب الرابط من اليسار لليمين. مثال: https://openrouter.ai/api/v1',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-or-v1-...',
              hintTextDirection: TextDirection.ltr,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _modelController,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'openrouter/free',
              hintTextDirection: TextDirection.ltr,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.smart_toy_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _systemController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'System Prompt (تعليمات النظام)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.psychology_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('البث المباشر (Streaming)'),
            subtitle: const Text('استجابة فورية مثل ChatGPT و Claude'),
            value: _streamEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _streamEnabled = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_testing ? 'جاري الاختبار...' : 'اختبار الاتصال'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 10),
            Text(
              _testResult!,
              style: TextStyle(
                color: _testResult!.startsWith('✅')
                    ? Colors.green.shade700
                    : Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'مجاني بدون مفتاح: اختر «مجاني بدون مفتاح (Pollinations)».\n'
                    'مجاني بمفتاح: Groq أو Gemini أو OpenRouter.\n'
                    'اكتب الرابط والنموذج من اليسار لليمين.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
          ),
        ],
      ),
    );
  }
}
