import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFDDE3EA),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFDDE3EA),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF60A5FA),
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const ChatPage(),
    );
  }
}

// ============================================================
// MESSAGE
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

// ============================================================
// FILE
// ============================================================

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

// ============================================================
// CHAT HISTORY
// ============================================================

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
// PROVIDER
// ============================================================

class WahaProvider {
  final String name;
  final String endpoint;
  final String modelHint;
  final String description;

  const WahaProvider({
    required this.name,
    required this.endpoint,
    required this.modelHint,
    required this.description,
  });
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
      provider:
          json['provider']?.toString() ?? 'OpenRouter',
      endpoint:
          json['endpoint']?.toString() ??
              'https://openrouter.ai/api/v1/chat/completions',
      apiKey:
          json['apiKey']?.toString() ?? '',
      model:
          json['model']?.toString() ??
              'openai/gpt-4o-mini',
      rememberHistory:
          json['rememberHistory'] is bool
              ? json['rememberHistory'] as bool
              : true,
    );
  }
}

// ============================================================
// STORAGE
// ============================================================

class LocalStorage {
  static const String settingsKey = 'waha_settings';
  static const String historyKey = 'waha_history';

  static Future<WahaSettings> loadSettings() async {
    final prefs =
        await SharedPreferences.getInstance();

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
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  static Future<List<ChatHistory>> loadHistory() async {
    final prefs =
        await SharedPreferences.getInstance();

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
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      historyKey,
      jsonEncode(
        history.map((e) => e.toJson()).toList(),
      ),
    );
  }
}

// ============================================================
// AI SERVICE
// ============================================================

class AIService {
  static String normalizeEndpoint(
    String endpoint,
  ) {
    var value = endpoint.trim();

    if (value.isEmpty) {
      return value;
    }

    while (value.endsWith('/')) {
      value = value.substring(
        0,
        value.length - 1,
      );
    }

    final lower = value.toLowerCase();

    if (lower.endsWith('/chat/completions')) {
      return value;
    }

    if (lower.endsWith('/v1')) {
      return '$value/chat/completions';
    }

    if (lower.endsWith('/api')) {
      return '$value/v1/chat/completions';
    }

    if (lower.endsWith('/api/v1')) {
      return '$value/chat/completions';
    }

    return '$value/chat/completions';
  }

  static Map<String, String> _headers(
    WahaSettings settings,
  ) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    if (settings.apiKey.trim().isNotEmpty) {
      headers['Authorization'] =
          'Bearer ${settings.apiKey.trim()}';
    }

    if (settings.provider == 'OpenRouter') {
      headers['HTTP-Referer'] =
          'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'Waha AI';
    }

    return headers;
  }

  static Future<String> sendMessage({
    required WahaSettings settings,
    required List<ChatMessage> messages,
  }) async {
    final result = StringBuffer();

    await streamMessage(
      settings: settings,
      messages: messages,
      onDelta: (delta) {
        result.write(delta);
      },
    );

    final text = result.toString().trim();

    if (text.isEmpty) {
      throw Exception(
        'لم يرجع مزود الذكاء الاصطناعي أي نص.',
      );
    }

    return text;
  }

  static Future<void> streamMessage({
    required WahaSettings settings,
    required List<ChatMessage> messages,
    required void Function(String delta) onDelta,
  }) async {
    final endpoint =
        normalizeEndpoint(settings.endpoint);

    final apiKey = settings.apiKey.trim();
    final model = settings.model.trim();

    if (endpoint.isEmpty) {
      throw Exception(
        'API Endpoint غير موجود.',
      );
    }

    if (apiKey.isEmpty) {
      throw Exception(
        'API Key غير موجود. افتح الإعدادات وأضف المفتاح.',
      );
    }

    if (model.isEmpty) {
      throw Exception(
        'Model غير موجود.',
      );
    }

    final apiMessages =
        <Map<String, dynamic>>[];

    for (final message in messages) {
      if (message.role != 'user' &&
          message.role != 'assistant' &&
          message.role != 'system') {
        continue;
      }

      apiMessages.add({
        'role': message.role,
        'content': message.content,
      });
    }

    final body = {
      'model': model,
      'messages': apiMessages,
      'stream': true,
    };

    final request = http.Request(
      'POST',
      Uri.parse(endpoint),
    );

    request.headers.addAll(
      _headers(settings),
    );

    request.body = jsonEncode(body);

    final client = http.Client();

    try {
      final response =
          await client.send(request).timeout(
                const Duration(seconds: 60),
              );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final errorBody =
            await response.stream.bytesToString();

        throw Exception(
          _parseError(
            response.statusCode,
            errorBody,
          ),
        );
      }

      final contentType =
          response.headers['content-type']
                  ?.toLowerCase() ??
              '';

      if (!contentType.contains('text/event-stream')) {
        final bodyText =
            await response.stream.bytesToString();

        _parseNormalResponse(
          bodyText,
          onDelta,
        );

        return;
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      bool received = false;

      await for (final line in stream) {
        final value = line.trim();

        if (value.isEmpty) {
          continue;
        }

        if (!value.startsWith('data:')) {
          continue;
        }

        final data = value
            .substring(5)
            .trim();

        if (data == '[DONE]') {
          break;
        }

        try {
          final decoded =
              jsonDecode(data);

          final delta =
              _extractDelta(decoded);

          if (delta.isNotEmpty) {
            received = true;
            onDelta(delta);
          }
        } catch (_) {
          // بعض البوابات ترسل أجزاء غير JSON.
        }
      }

      if (!received) {
        throw Exception(
          'الخادم اتصل بنجاح لكنه لم يرسل محتوى. '
          'تأكد أن الـ Gateway يدعم OpenAI-compatible '
          'Chat Completions و Streaming.',
        );
      }
    } on TimeoutException {
      throw Exception(
        'انتهت مهلة الاتصال بالخادم.',
      );
    } on SocketException {
      throw Exception(
        'لا يوجد اتصال بالإنترنت أو الخادم غير متاح.',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'خطأ في الاتصال: ${e.message}',
      );
    } finally {
      client.close();
    }
  }

  static String _extractDelta(
    dynamic decoded,
  ) {
    if (decoded is! Map) {
      return '';
    }

    final choices = decoded['choices'];

    if (choices is! List ||
        choices.isEmpty) {
      return '';
    }

    final first = choices.first;

    if (first is! Map) {
      return '';
    }

    final delta = first['delta'];

    if (delta is Map) {
      final content = delta['content'];

      if (content is String) {
        return content;
      }

      if (content is List) {
        return content.map((item) {
          if (item is Map) {
            return item['text']?.toString() ?? '';
          }

          return '';
        }).join();
      }
    }

    final message = first['message'];

    if (message is Map) {
      final content = message['content'];

      if (content is String) {
        return content;
      }
    }

    final text = first['text'];

    if (text is String) {
      return text;
    }

    return '';
  }

  static void _parseNormalResponse(
    String body,
    void Function(String) onDelta,
  ) {
    try {
      final decoded = jsonDecode(body);

      final text = _extractNormalText(decoded);

      if (text.isNotEmpty) {
        onDelta(text);
        return;
      }

      throw Exception(
        'استجابة الخادم لا تحتوي على نص.',
      );
    } catch (_) {
      throw Exception(
        'الخادم أرسل استجابة غير مفهومة.',
      );
    }
  }

  static String _extractNormalText(
    dynamic decoded,
  ) {
    if (decoded is! Map) {
      return '';
    }

    final choices = decoded['choices'];

    if (choices is List &&
        choices.isNotEmpty) {
      final first = choices.first;

      if (first is Map) {
        final message = first['message'];

        if (message is Map) {
          final content =
              message['content'];

          if (content is String) {
            return content;
          }

          if (content is List) {
            return content.map((item) {
              if (item is Map) {
                return item['text']
                        ?.toString() ??
                    '';
              }

              return '';
            }).join();
          }
        }

        final text = first['text'];

        if (text != null) {
          return text.toString();
        }
      }
    }

    final output = decoded['output'];

    if (output != null) {
      return output.toString();
    }

    final response = decoded['response'];

    if (response != null) {
      return response.toString();
    }

    return '';
  }

  static String _parseError(
    int status,
    String body,
  ) {
    String message =
        'HTTP $status';

    if (body.trim().isEmpty) {
      return message;
    }

    try {
      final decoded =
          jsonDecode(body);

      if (decoded is Map) {
        final error = decoded['error'];

        if (error is Map) {
          message =
              error['message']
                      ?.toString() ??
                  message;
        } else if (error != null) {
          message = error.toString();
        }

        if (decoded['message'] != null) {
          message =
              decoded['message'].toString();
        }
      }
    } catch (_) {
      if (body.length < 500) {
        message =
            '$message: $body';
      }
    }

    return message;
  }
}

// ============================================================
// CHAT PAGE
// ============================================================

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() =>
      _ChatPageState();
}

class _ChatPageState
    extends State<ChatPage> {
  final TextEditingController
      _inputController =
      TextEditingController();

  final ScrollController
      _scrollController =
      ScrollController();

  WahaSettings _settings =
      WahaSettings();

  List<ChatHistory> _history = [];

  ChatHistory _currentChat =
      ChatHistory(title: 'محادثة جديدة');

  final List<AttachedFile> _pendingFiles =
      [];

  bool _loading = false;
  bool _sidebar = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings =
        await LocalStorage.loadSettings();

    final history =
        await LocalStorage.loadHistory();

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _history = history;

      if (history.isNotEmpty) {
        _currentChat = history.first;
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================================
  // SEND
  // ==========================================================

  Future<void> _sendMessage() async {
    if (_loading) return;

    final text =
        _inputController.text.trim();

    if (text.isEmpty &&
        _pendingFiles.isEmpty) {
      return;
    }

    String content = text;

    if (_pendingFiles.isNotEmpty) {
      final names = _pendingFiles
          .map((e) => e.name)
          .join(', ');

      if (content.isEmpty) {
        content =
            'الملفات المرفقة: $names';
      } else {
        content =
            '$content\n\nالملفات المرفقة: $names';
      }
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: content,
      files:
          List<AttachedFile>.from(
        _pendingFiles,
      ),
    );

    final
