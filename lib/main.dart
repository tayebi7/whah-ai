import 'dart:async';
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

// ============================================================
// APP
// ============================================================

class WahaAI extends StatelessWidget {
  const WahaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Waha AI',
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF60A5FA),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const ChatPage(),
    );
  }
}

// ============================================================
// MODELS
// ============================================================

class ChatMessage {
  final String id;
  final String role;
  String content;
  final DateTime createdAt;
  final List<AttachedFile> files;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.files = const [],
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'files': files.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final files = <AttachedFile>[];

    final rawFiles = json['files'];

    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map) {
          files.add(
            AttachedFile.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    return ChatMessage(
      id: json['id']?.toString(),
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      files: files,
    );
  }
}

class AttachedFile {
  final String name;
  final String path;
  final int size;
  final String extension;

  AttachedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.extension,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'extension': extension,
    };
  }

  factory AttachedFile.fromJson(Map<String, dynamic> json) {
    return AttachedFile(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: int.tryParse(
            json['size']?.toString() ?? '0',
          ) ??
          0,
      extension: json['extension']?.toString() ?? '',
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    final messages = <ChatMessage>[];

    final rawMessages = json['messages'];

    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          messages.add(
            ChatMessage.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    return ChatHistory(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? 'محادثة جديدة',
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            json['updatedAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      messages: messages,
    );
  }
}

// ============================================================
// SETTINGS
// ============================================================

class WahaSettings {
  String provider;
  String endpoint;
  String apiKey;
  String model;
  bool rememberHistory;

  WahaSettings({
    this.provider = 'OpenRouter',
    this.endpoint =
        'https://openrouter.ai/api/v1/chat/completions',
    this.apiKey = '',
    this.model = 'openai/gpt-4o-mini',
    this.rememberHistory = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'endpoint': endpoint,
      'apiKey': apiKey,
      'model': model,
      'rememberHistory': rememberHistory,
    };
  }

  factory WahaSettings.fromJson(
    Map<String, dynamic> json,
  ) {
    return WahaSettings(
      provider: json['provider']?.toString() ?? 'OpenRouter',
      endpoint: json['endpoint']?.toString() ??
          'https://openrouter.ai/api/v1/chat/completions',
      apiKey: json['apiKey']?.toString() ?? '',
      model: json['model']?.toString() ?? 'openai/gpt-4o-mini',
      rememberHistory: json['rememberHistory'] is bool
          ? json['rememberHistory'] as bool
          : true,
    );
  }
}

// ============================================================
// LOCAL STORAGE
// ============================================================

class LocalStorage {
  static const settingsKey = 'waha_settings';
  static const historyKey = 'waha_history';

  static Future<WahaSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(settingsKey);

    if (raw == null || raw.isEmpty) {
      return WahaSettings();
    }

    try {
      return WahaSettings.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(raw) as Map,
        ),
      );
    } catch (_) {
      return WahaSettings();
    }
  }

  static Future<void> saveSettings(
    WahaSettings settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  static Future<List<ChatHistory>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(historyKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => ChatHistory.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveHistory(
    List<ChatHistory> history,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      historyKey,
      jsonEncode(
        history.map((e) => e.toJson()).toList(),
      ),
    );
  }
}

// ============================================================
// CHAT PAGE
// ============================================================

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _inputController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  WahaSettings _settings = WahaSettings();

  List<ChatHistory> _history = [];

  ChatHistory _currentChat =
      ChatHistory(title: 'محادثة جديدة');

  final List<AttachedFile> _pendingFiles = [];

  bool _loading = false;
  bool _sidebar = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
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
    });
  }

  // ==========================================================
  // CHAT
  // ==========================================================

  Future<void> _sendMessage() async {
    if (_loading) return;

    final text = _inputController.text.trim();

    if (text.isEmpty && _pendingFiles.isEmpty) {
      return;
    }

    String content = text;

    if (_pendingFiles.isNotEmpty) {
      final names = _pendingFiles
          .map((e) => e.name)
          .join(', ');

      if (content.isEmpty) {
        content = 'الملفات المرفقة: $names';
      } else {
        content =
            '$content\n\nالملفات المرفقة: $names';
      }
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: content,
      files: List<AttachedFile>.from(
        _pendingFiles,
      ),
    );

    setState(() {
      _currentChat.messages.add(userMessage);

      if (_currentChat.title == 'محادثة جديدة') {
        _currentChat.title = _makeTitle(content);
      }

      _inputController.clear();
      _pendingFiles.clear();
      _loading = true;
    });

    await _saveCurrentChat();
    _scrollToBottom();

    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
    );

    setState(() {
      _currentChat.messages.add(assistantMessage);
    });

    try {
      await AIService.streamMessage(
        settings: _settings,
        messages: _currentChat.messages
            .
