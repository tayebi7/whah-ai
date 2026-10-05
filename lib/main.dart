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
  runApp(const WahaAI());
}

class WahaAI extends StatelessWidget {
  const WahaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Waha AI',
      // واجهة عربية: لتظهر عناصر Material واتجاه النص من اليمين إلى اليسار.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF60A5FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
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
  final String content;
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
      'files': files.map((file) => file.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];

    final parsedFiles = <AttachedFile>[];

    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map) {
          parsedFiles.add(
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
      files: parsedFiles,
    );
  }
}

// ============================================================
// ATTACHED FILE
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
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];

    final parsedMessages = <ChatMessage>[];

    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          parsedMessages.add(
            ChatMessage.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    return ChatHistory(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? 'New Chat',
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            json['updatedAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      messages: parsedMessages,
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

  factory WahaSettings.fromJson(Map<String, dynamic> json) {
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
        history.map((chat) => chat.toJson()).toList(),
      ),
    );
  }
}

// ============================================================
// AI SERVICE
// ============================================================

class AIService {
  static Future<String> sendMessage({
    required WahaSettings settings,
    required List<ChatMessage> messages,
  }) async {
    final apiKey = settings.apiKey.trim();
    final endpoint = settings.endpoint.trim();
    final model = settings.model.trim();

    if (apiKey.isEmpty) {
      throw Exception(
        'API Key غير موجود. افتح الإعدادات وأضف المفتاح.',
      );
    }

    if (endpoint.isEmpty) {
      throw Exception(
        'API Endpoint غير موجود.',
      );
    }

    if (model.isEmpty) {
      throw Exception(
        'Model غير موجود.',
      );
    }

    final apiMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      apiMessages.add({
        'role': message.role,
        'content': message.content,
      });
    }

    final body = {
      'model': model,
      'messages': apiMessages,
      'stream': false,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    if (settings.provider == 'OpenRouter') {
      headers['HTTP-Referer'] =
          'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'Waha AI';
    }

    final client = http.Client();

    try {
      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 90),
          );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        var errorMessage =
            'HTTP ${response.statusCode}';

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map) {
            final error = decoded['error'];

            if (error is Map) {
              errorMessage =
                  error['message']?.toString() ??
                      errorMessage;
            } else if (error != null) {
              errorMessage = error.toString();
            }

            if (decoded['message'] != null) {
              errorMessage =
                  decoded['message'].toString();
            }
          }
        } catch (_) {}

        throw Exception(errorMessage);
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception(
          'استجابة غير صحيحة من الخادم.',
        );
      }

      final choices = decoded['choices'];

      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;

        if (first is Map) {
          final message = first['message'];

          if (message is Map) {
            final content = message['content'];

            if (content is String &&
                content.trim().isNotEmpty) {
              return content.trim();
            }

            if (content is List) {
              final text = content
                  .map((item) {
                    if (item is Map) {
                      return item['text']?.toString() ?? '';
                    }

                    return item.toString();
                  })
                  .join();

              if (text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }

          final text = first['text'];

          if (text != null &&
              text.toString().trim().isNotEmpty) {
            return text.toString().trim();
          }
        }
      }

      final output = decoded['output'];

      if (output != null &&
          output.toString().trim().isNotEmpty) {
        return output.toString().trim();
      }

      final responseText = decoded['response'];

      if (responseText != null &&
          responseText.toString().trim().isNotEmpty) {
        return responseText.toString().trim();
      }

      throw Exception(
        'لم يرجع المزود أي نص.',
      );
    } on TimeoutException {
      throw Exception(
        'انتهت مهلة الاتصال بالخادم. تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.',
      );
    } on SocketException {
      throw Exception(
        'لا يوجد اتصال بالإنترنت.',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'خطأ في الاتصال: ${e.message}',
      );
    } finally {
      client.close();
    }
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
      ChatHistory(title: 'New Chat');

  final List<AttachedFile> _pendingFiles = [];

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

  Future<void> _sendMessage() async {
    if (_loading) return;

    final text = _inputController.text.trim();

    if (text.isEmpty && _pendingFiles.isEmpty) {
      return;
    }

    var content = text;

    if (_pendingFiles.isNotEmpty) {
      final names = _pendingFiles
          .map((file) => file.name)
          .join(', ');

      if (content.isEmpty) {
        content = 'الملفات المرفقة: $names';
      } else {
        content =
            '$content\n\nالملفات المرفقة: $names';
      }
    }

    final message = ChatMessage(
      role: 'user',
      content: content,
      files: List<AttachedFile>.from(
        _pendingFiles,
      ),
    );

    setState(() {
      _currentChat.messages.add(message);

      if (_currentChat.title == 'New Chat') {
        _currentChat.title =
            _createTitle(text);
      }

      _pendingFiles.clear();
      _inputController.clear();
      _loading = true;
    });

    _scrollBottom();

    try {
      final answer =
          await AIService.sendMessage(
        settings: _settings,
        messages: _currentChat.messages,
      );

      if (!mounted) return;

      setState(() {
        _currentChat.messages.add(
          ChatMessage(
            role: 'assistant',
            content: answer,
          ),
        );

        _loading = false;
      });

      await _saveChat();

      _scrollBottom();
    } catch (e) {
      if (!mounted) return;

      final error = e.toString().replaceFirst(
            'Exception: ',
            '',
          );

      setState(() {
        _currentChat.messages.add(
          ChatMessage(
            role: 'assistant',
            content:
                '⚠️ **خطأ**\n\n$error',
          ),
        );

        _loading = false;
      });

      await _saveChat();

      _scrollBottom();
    }
  }

  String _createTitle(String text) {
    final value =
        text.replaceAll('\n', ' ').trim();

    if (value.isEmpty) {
      return 'New Chat';
    }

    if (value.length <= 35) {
      return value;
    }

    return '${value.substring(0, 35)}...';
  }

  Future<void> _saveChat() async {
    if (!_settings.rememberHistory) {
      return;
    }

    if (_currentChat.messages.isEmpty) {
      return;
    }

    _currentChat.updatedAt = DateTime.now();

    final index = _history.indexWhere(
      (chat) => chat.id == _currentChat.id,
    );

    if (index == -1) {
      _history.insert(0, _currentChat);
    } else {
      _history[index] = _currentChat;
    }

    await LocalStorage.saveHistory(_history);
  }

  void _newChat() {
    setState(() {
      _currentChat =
          ChatHistory(title: 'New Chat');

      _pendingFiles.clear();
      _inputController.clear();
      _sidebar = false;
    });
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration:
            const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickFiles() async {
    try {
      // file_picker 13.x: FilePicker is a static class; the old
      // `allowMultiple` / `withData` parameters were removed in 13.0.0.
      final picked = await FilePicker.pickFiles();

      if (picked.isEmpty) return;

      final files = <AttachedFile>[];

      for (final file in picked) {
        files.add(
          AttachedFile(
            name: file.name,
            path: file.path ?? '',
            size: file.lengthSync() ?? 0,
            extension: file.extension ?? '',
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _pendingFiles.addAll(files);
      });
    } catch (e) {
      _snack(
        'تعذر اختيار الملف: $e',
      );
    }
  }

  void _removeFile(int index) {
    setState(() {
      _pendingFiles.removeAt(index);
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(
      ClipboardData(text: text),
    );

    _snack('تم النسخ');
  }

  Future<void> _saveText(String text) async {
    try {
      final directory =
          await getApplicationDocumentsDirectory();

      final file = File(
        '${directory.path}/waha_${DateTime.now().millisecondsSinceEpoch}.txt',
      );

      await file.writeAsString(
        text,
        encoding: utf8,
      );

      _snack('تم حفظ الملف');
    } catch (e) {
      _snack('فشل حفظ الملف: $e');
    }
  }

  void _snack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openSettings() async {
    final result =
        await Navigator.push<WahaSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _settings = result;
    });

    await LocalStorage.saveSettings(
      _settings,
    );
  }

  Future<void> _deleteChat(
    ChatHistory chat,
  ) async {
    _history.removeWhere(
      (item) => item.id == chat.id,
    );

    await LocalStorage.saveHistory(_history);

    if (!mounted) return;

    if (_currentChat.id == chat.id) {
      _newChat();
    } else {
      setState(() {});
    }
  }

  void _openChat(ChatHistory chat) {
    setState(() {
      _currentChat = chat;
      _sidebar = false;
    });

    _scrollBottom();
  }

  void _suggestion(String value) {
    _inputController.text = value;

    _inputController.selection =
        TextSelection.collapsed(
      offset: value.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (_sidebar)
              SizedBox(
                width: 290,
                child: _buildSidebar(),
              ),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _buildMessages(),
                  ),
                  _buildInput(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 62,
      padding:
          const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _sidebar = !_sidebar;
              });
            },
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 6),
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: const Color(0xFF60A5FA),
              borderRadius:
                  BorderRadius.circular(11),
            ),
            child: const Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Waha AI',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: _newChat,
            icon: const Icon(
              Icons.add_comment_outlined,
            ),
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(
              Icons.settings_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add),
                label:
                    const Text('محادثة جديدة'),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _history.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد محادثات',
                    ),
                  )
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder:
                        (context, index) {
                      final chat =
                          _history[index];

                      return ListTile(
                        selected:
                            chat.id ==
                                _currentChat.id,
                        leading: const Icon(
                          Icons.chat_outlined,
                        ),
                        title: Text(
                          chat.title,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${chat.messages.length} رسالة',
                        ),
                        onTap: () =>
                            _openChat(chat),
                        trailing:
                            PopupMenuButton<String>(
                          onSelected:
                              (value) {
                            if (value ==
                                'delete') {
                              _deleteChat(chat);
                            }
                          },
                          itemBuilder: (_) =>
                              const [
                            PopupMenuItem(
                              value: 'delete',
                              child:
                                  Text('حذف'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_currentChat.messages.isEmpty) {
      return _buildWelcome();
    }

    final count =
        _currentChat.messages.length +
            (_loading ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding:
          const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (context, index) {
        if (_loading &&
            index ==
                _currentChat.messages.length) {
          return _loadingBubble();
        }

        return _messageBubble(
          _currentChat.messages[index],
        );
      },
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA),
                borderRadius:
                    BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text(
                  'W',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'مرحبًا بك في Waha AI',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'مساعد ذكاء اصطناعي متعدد المزودين',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label:
                      const Text('اكتب لي برنامجًا'),
                  onPressed: () => _suggestion(
                    'اكتب لي برنامجًا',
                  ),
                ),
                ActionChip(
                  label:
                      const Text('حلل هذا المستند'),
                  onPressed: () => _suggestion(
                    'حلل هذا المستند',
                  ),
                ),
                ActionChip(
                  label:
                      const Text('اشرح لي هذا الكود'),
                  onPressed: () => _suggestion(
                    'اشرح لي هذا الكود',
                  ),
                ),
                ActionChip(
                  label:
                      const Text('ساعدني في فكرة تطبيق'),
                  onPressed: () => _suggestion(
                    'ساعدني في فكرة تطبيق',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(
    ChatMessage message,
  ) {
    final isUser =
        message.role == 'user';

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints:
            const BoxConstraints(
          maxWidth: 850,
        ),
        margin:
            const EdgeInsets.only(bottom: 16),
        padding:
            const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFFE8F2FF)
              : Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: isUser
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF111827),
                  child: Icon(
                    isUser
                        ? Icons.person_outline
                        : Icons.auto_awesome,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isUser
                      ? 'أنت'
                      : 'Waha AI',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'copy') {
                      _copy(message.content);
                    }

                    if (value == 'save') {
                      _saveText(message.content);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('نسخ'),
                    ),
                    if (!isUser)
                      const PopupMenuItem(
                        value: 'save',
                        child:
                            Text('حفظ كملف'),
                      ),
                  ],
                ),
              ],
            ),
            if (message.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.files
                    .map(
                      (file) => Chip(
                        avatar: const Icon(
                          Icons.attach_file,
                          size: 16,
                        ),
                        label: Text(
                          file.name,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            if (isUser)
              SelectableText(
                message.content,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.55,
                ),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet:
                    MarkdownStyleSheet(
                  p: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin:
            const EdgeInsets.only(bottom: 16),
        padding:
            const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 10),
            Text('Waha AI يفكر...'),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        10,
        8,
        10,
        10,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Column(
        children: [
          if (_pendingFiles.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection:
                    Axis.horizontal,
                children: _pendingFiles
                    .asMap()
                    .entries
                    .map(
                      (entry) => Padding(
                        padding:
                            const EdgeInsets.only(
                          right: 6,
                        ),
                        child: InputChip(
                          label: Text(
                            entry.value.name,
                          ),
                          onDeleted: () =>
                              _removeFile(
                            entry.key,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Container(
            constraints:
                const BoxConstraints(
              maxWidth: 900,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFD1D5DB),
              ),
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed:
                      _loading
                          ? null
                          : _pickFiles,
                  icon: const Icon(
                    Icons.attach_file,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller:
                        _inputController,
                    minLines: 1,
                    maxLines: 7,
                    decoration:
                        const InputDecoration(
                      hintText:
                          'اكتب رسالتك إلى Waha AI...',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 4,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.all(6),
                  child: IconButton.filled(
                    onPressed:
                        _loading
                            ? null
                            : _sendMessage,
                    icon: const Icon(
                      Icons.arrow_upward_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_settings.provider} • ${_settings.model}',
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS
// ============================================================

class SettingsPage extends StatefulWidget {
  final WahaSettings settings;

  const SettingsPage({
    super.key,
    required this.settings,
  });

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  late WahaSettings settings;

  late TextEditingController
      _endpointController;

  late TextEditingController
      _apiKeyController;

  late TextEditingController
      _modelController;

  bool _hideKey = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();

    settings = WahaSettings(
      provider: widget.settings.provider,
      endpoint: widget.settings.endpoint,
      apiKey: widget.settings.apiKey,
      model: widget.settings.model,
      rememberHistory:
          widget.settings.rememberHistory,
    );

    _endpointController =
        TextEditingController(
      text: settings.endpoint,
    );

    _apiKeyController =
        TextEditingController(
      text: settings.apiKey,
    );

    _modelController =
        TextEditingController(
      text: settings.model,
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _providerChanged(
    String? provider,
  ) {
    if (provider == null) return;

    setState(() {
      settings.provider = provider;

      if (provider == 'OpenRouter') {
        settings.endpoint =
            'https://openrouter.ai/api/v1/chat/completions';
      }

      if (provider == 'OpenAI') {
        settings.endpoint =
            'https://api.openai.com/v1/chat/completions';
      }

      _endpointController.text =
          settings.endpoint;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
    });

    final testSettings = WahaSettings(
      provider: settings.provider,
      endpoint:
          _endpointController.text.trim(),
      apiKey:
          _apiKeyController.text.trim(),
      model:
          _modelController.text.trim(),
      rememberHistory:
          settings.rememberHistory,
    );

    try {
      final result =
          await AIService.sendMessage(
        settings: testSettings,
        messages: [
          ChatMessage(
            role: 'user',
            content:
                'Reply with only: Waha AI OK',
          ),
        ],
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title:
              const Text('الاتصال ناجح ✅'),
          content: Text(result),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child:
                  const Text('موافق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title:
              const Text('فشل الاتصال ❌'),
          content: Text(
            e.toString().replaceFirst(
                  'Exception: ',
                  '',
                ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child:
                  const Text('إغلاق'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  void _save() {
    settings.endpoint =
        _endpointController.text.trim();

    settings.apiKey =
        _apiKeyController.text.trim();

    settings.model =
        _modelController.text.trim();

    Navigator.pop(
      context,
      settings,
    );
  }

  Future<void> _github() async {
    final uri = Uri.parse(
      'https://github.com/tayebi7/whah-ai',
    );

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إعدادات Waha AI'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(18),
        children: [
          const Text(
            'مزود الذكاء الاصطناعي',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // مهم:
          // استخدام initialValue وليس value
          // مع Flutter الحديث.
          DropdownButtonFormField<String>(
            initialValue: settings.provider,
            decoration:
                const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'OpenRouter',
                child: Text('OpenRouter'),
              ),
              DropdownMenuItem(
                value: 'OpenAI',
                child: Text('OpenAI'),
              ),
              DropdownMenuItem(
                value: 'Gateway',
                child: Text('Gateway'),
              ),
              DropdownMenuItem(
                value: 'Custom',
                child: Text('Custom API'),
              ),
            ],
            onChanged: _providerChanged,
          ),

          const SizedBox(height: 16),

          TextField(
            controller:
                _endpointController,
            keyboardType:
                TextInputType.url,
            decoration:
                const InputDecoration(
              labelText: 'API Endpoint',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller:
                _apiKeyController,
            obscureText: _hideKey,
            decoration:
                InputDecoration(
              labelText: 'API Key',
              border:
                  const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _hideKey = !_hideKey;
                  });
                },
                icon: Icon(
                  _hideKey
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller:
                _modelController,
            decoration:
                const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
              hintText:
                  'openai/gpt-4o-mini',
            ),
          ),

          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            title: const Text(
              'حفظ سجل المحادثات',
            ),
            subtitle: const Text(
              'حفظ المحادثات محليًا',
            ),
            value:
                settings.rememberHistory,
            onChanged: (value) {
              setState(() {
                settings.rememberHistory =
                    value;
              });
            },
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  _testing
                      ? null
                      : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.wifi_tethering,
                    ),
              label: Text(
                _testing
                    ? 'جاري الاختبار...'
                    : 'اختبار الاتصال',
              ),
            ),
          ),

          const SizedBox(height: 18),

          OutlinedButton.icon(
            onPressed: _github,
            icon: const Icon(Icons.code),
            label:
                const Text('GitHub'),
          ),
        ],
      ),
    );
  }
}
