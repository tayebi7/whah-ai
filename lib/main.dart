import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF60A5FA),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF60A5FA)),
          ),
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
  final DateTime time;
  final List<AttachedFile> files;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.time,
    this.files = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'time': time.toIso8601String(),
      'files': files.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? const Uuid().v4(),
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      time: DateTime.tryParse(json['time'] ?? '') ?? DateTime.now(),
      files: ((json['files'] ?? []) as List)
          .map((e) => AttachedFile.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
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
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      extension: json['extension'] ?? '',
    );
  }
}

class ChatHistory {
  final String id;
  String title;
  final DateTime created;
  List<ChatMessage> messages;

  ChatHistory({
    required this.id,
    required this.title,
    required this.created,
    required this.messages,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created': created.toIso8601String(),
      'messages': messages.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    return ChatHistory(
      id: json['id'] ?? const Uuid().v4(),
      title: json['title'] ?? 'محادثة جديدة',
      created:
          DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
      messages: ((json['messages'] ?? []) as List)
          .map(
            (e) => ChatMessage.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
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
    this.endpoint = 'https://openrouter.ai/api/v1/chat/completions',
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
      provider: json['provider'] ?? 'OpenRouter',
      endpoint: json['endpoint'] ??
          'https://openrouter.ai/api/v1/chat/completions',
      apiKey: json['apiKey'] ?? '',
      model: json['model'] ?? 'openai/gpt-4o-mini',
      rememberHistory: json['rememberHistory'] ?? true,
    );
  }
}

// ============================================================
// LOCAL STORAGE
// ============================================================

class LocalStorage {
  static const String settingsKey = 'waha_settings';
  static const String historyKey = 'waha_history';

  static Future<WahaSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString(settingsKey);

    if (data == null || data.isEmpty) {
      return WahaSettings();
    }

    try {
      return WahaSettings.fromJson(
        jsonDecode(data),
      );
    } catch (_) {
      return WahaSettings();
    }
  }

  static Future<void> saveSettings(WahaSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  static Future<List<ChatHistory>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString(historyKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final list = jsonDecode(data) as List;

      return list
          .map(
            (e) => ChatHistory.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveHistory(
    List<ChatHistory> histories,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      historyKey,
      jsonEncode(
        histories.map((e) => e.toJson()).toList(),
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
    if (settings.apiKey.trim().isEmpty) {
      throw Exception(
        'لم تتم إضافة API Key. افتح الإعدادات وأضف المفتاح.',
      );
    }

    if (settings.endpoint.trim().isEmpty) {
      throw Exception(
        'عنوان السيرفر غير موجود.',
      );
    }

    final List<Map<String, dynamic>> apiMessages = [];

    for (final message in messages) {
      if (message.role != 'user' && message.role != 'assistant') {
        continue;
      }

      apiMessages.add({
        'role': message.role,
        'content': message.content,
      });
    }

    final body = {
      'model': settings.model,
      'messages': apiMessages,
      'stream': false,
    };

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${settings.apiKey.trim()}',
      'Accept': 'application/json',
    };

    if (settings.provider.toLowerCase().contains('openrouter')) {
      headers['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'Waha AI';
    }

    final response = await http
        .post(
          Uri.parse(settings.endpoint.trim()),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(
          const Duration(seconds: 90),
        );

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message = response.body;

      try {
        final error = jsonDecode(response.body);

        message =
            error['error']?['message']?.toString() ??
            error['message']?.toString() ??
            response.body;
      } catch (_) {}

      throw Exception(
        'خطأ ${response.statusCode}: $message',
      );
    }

    final data = jsonDecode(response.body);

    final choices = data['choices'];

    if (choices is List && choices.isNotEmpty) {
      final content =
          choices.first['message']?['content'];

      if (content != null) {
        if (content is String) {
          return content;
        }

        return content.toString();
      }
    }

    throw Exception(
      'السيرفر أعاد استجابة غير مفهومة.',
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
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final Uuid _uuid = const Uuid();

  WahaSettings _settings = WahaSettings();

  List<ChatHistory> _histories = [];

  ChatHistory? _currentChat;

  List<AttachedFile> _pendingFiles = [];

  bool _loading = false;

  bool _showSidebar = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final settings = await LocalStorage.loadSettings();
    final histories = await LocalStorage.loadHistory();

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _histories = histories;

      if (histories.isNotEmpty) {
        _currentChat = histories.first;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================================
  // NEW CHAT
  // ==========================================================

  void _newChat() {
    setState(() {
      _currentChat = ChatHistory(
        id: _uuid.v4(),
        title: 'محادثة جديدة',
        created: DateTime.now(),
        messages: [],
      );

      _pendingFiles = [];
      _showSidebar = false;
    });
  }

  // ==========================================================
  // SEND
  // ==========================================================

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty && _pendingFiles.isEmpty) {
      return;
    }

    if (_currentChat == null) {
      _newChat();
    }

    final chat = _currentChat!;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: text.isEmpty
          ? 'حلل الملفات المرفقة.'
          : text,
      time: DateTime.now(),
      files: List.from(_pendingFiles),
    );

    setState(() {
      chat.messages.add(userMessage);

      if (chat.messages.length == 1) {
        final title =
            text.isEmpty ? 'ملفات جديدة' : text;

        chat.title = title.length > 45
            ? '${title.substring(0, 45)}...'
            : title;
      }

      _controller.clear();
      _pendingFiles = [];
      _loading = true;
    });

    _scrollToBottom();

    try {
      final answer = await AIService.sendMessage(
        settings: _settings,
        messages: chat.messages,
      );

      if (!mounted) return;

      setState(() {
        chat.messages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: 'assistant',
            content: answer,
            time: DateTime.now(),
          ),
        );

        _loading = false;
      });

      await _saveCurrentHistory();

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        chat.messages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: 'assistant',
            content:
                '⚠️ حدث خطأ أثناء الاتصال:\n\n${e.toString()}',
            time: DateTime.now(),
          ),
        );

        _loading = false;
      });

      await _saveCurrentHistory();

      _scrollToBottom();
    }
  }

  // ==========================================================
  // HISTORY
  // ==========================================================

  Future<void> _saveCurrentHistory() async {
    if (_currentChat == null) return;

    final index = _histories.indexWhere(
      (e) => e.id == _currentChat!.id,
    );

    if (index == -1) {
      _histories.insert(0, _currentChat!);
    } else {
      _histories[index] = _currentChat!;
    }

    if (_settings.rememberHistory) {
      await LocalStorage.saveHistory(_histories);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _openHistory(ChatHistory chat) {
    setState(() {
      _currentChat = chat;
      _showSidebar = false;
    });

    _scrollToBottom();
  }

  Future<void> _deleteHistory(ChatHistory chat) async {
    _histories.removeWhere(
      (e) => e.id == chat.id,
    );

    if (_currentChat?.id == chat.id) {
      _currentChat = null;
    }

    await LocalStorage.saveHistory(_histories);

    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // FILES
  // ==========================================================

  Future<void> _pickFiles() async {
    try {
      final result =
          await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );

      if (result == null) return;

      final files = result.files
          .where((file) => file.path != null)
          .map(
            (file) => AttachedFile(
              name: file.name,
              path: file.path!,
              size: file.size,
              extension: file.extension ?? '',
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _pendingFiles.addAll(files);
      });
    } catch (e) {
      _showMessage(
        'تعذر اختيار الملفات: $e',
      );
    }
  }

  void _removePendingFile(AttachedFile file) {
    setState(() {
      _pendingFiles.remove(file);
    });
  }

  // ==========================================================
  // COPY
  // ==========================================================

  Future<void> _copyText(String text) async {
    await Clipboard.setData(
      ClipboardData(text: text),
    );

    _showMessage('تم النسخ');
  }

  // ==========================================================
  // DOWNLOAD
  // ==========================================================

  Future<void> _saveTextAsFile(String text) async {
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

      _showMessage(
        'تم حفظ الملف:\n${file.path}',
      );
    } catch (e) {
      _showMessage(
        'فشل حفظ الملف: $e',
      );
    }
  }

  // ==========================================================
  // SCROLL
  // ==========================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  Future<void> _openSettings() async {
    final result =
        await Navigator.of(context).push<WahaSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
        ),
      ),
    );

    if (result == null) return;

    await LocalStorage.saveSettings(result);

    if (!mounted) return;

    setState(() {
      _settings = result;
    });

    _showMessage('تم حفظ الإعدادات');
  }

  // ==========================================================
  // SIDEBAR
  // ==========================================================

  Widget _buildSidebar() {
    return Material(
      elevation: 8,
      child: Container(
        width: 290,
        color: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Waha AI',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showSidebar = false;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _newChat,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'محادثة جديدة',
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              const Divider(),

              const Padding(
                padding: EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'History',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: _histories.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد محادثات محفوظة',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _histories.length,
                        itemBuilder: (_, index) {
                          final chat = _histories[index];

                          return ListTile(
                            selected:
                                _currentChat?.id == chat.id,
                            selectedTileColor:
                                const Color(0xFFEFF6FF),
                            leading: const Icon(
                              Icons.chat_bubble_outline,
                            ),
                            title: Text(
                              chat.title,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                _openHistory(chat),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                              ),
                              onPressed: () =>
                                  _deleteHistory(chat),
                            ),
                          );
                        },
                      ),
              ),

              const Divider(),

              ListTile(
                leading:
                    const Icon(Icons.settings_outlined),
                title: const Text('الإعدادات'),
                onTap: _openSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: Align(
        alignment: isUser
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 760,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser
                ? const Color(0xFFDBEAFE)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUser
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (message.files.isNotEmpty)
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
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                ),

              if (message.files.isNotEmpty)
                const SizedBox(height: 8),

              Directionality(
                textDirection: TextDirection.rtl,
                child: MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 16,
                      height: 1.55,
                      color: Color(0xFF1E293B),
                    ),
                    code: const TextStyle(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 5),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'نسخ',
                    visualDensity:
                        VisualDensity.compact,
                    icon: const Icon(
                      Icons.copy_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        _copyText(message.content),
                  ),
                  IconButton(
                    tooltip: 'حفظ',
                    visualDensity:
                        VisualDensity.compact,
                    icon: const Icon(
                      Icons.download_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        _saveTextAsFile(
                      message.content,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // INPUT
  // ==========================================================

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          12,
          6,
          12,
          12,
        ),
        child: Column(
          children: [
            if (_pendingFiles.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(
                  bottom: 8,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _pendingFiles
                      .map(
                        (file) => InputChip(
                          label: Text(
                            file.name,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                          ),
                          onDeleted: () =>
                              _removePendingFile(file),
                        ),
                      )
                      .toList(),
                ),
              ),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFFCBD5E1),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 12,
                    color: Color(0x14000000),
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'إرفاق ملف',
                    onPressed:
                        _loading ? null : _pickFiles,
                    icon: const Icon(
                      Icons.add_circle_outline,
                    ),
                  ),

                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 7,
                      textDirection:
                          TextDirection.rtl,
                      decoration:
                          const InputDecoration(
                        hintText:
                            'اكتب رسالتك إلى Waha AI...',
                        border: InputBorder.none,
                        filled: false,
                        contentPadding:
                            EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) =>
                          _sendMessage(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(
                      right: 6,
                      bottom: 6,
                    ),
                    child: IconButton.filled(
                      tooltip: 'إرسال',
                      onPressed:
                          _loading
                              ? null
                              : _sendMessage,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            Text(
              '${_settings.provider} • ${_settings.model}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // MAIN UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final messages =
        _currentChat?.messages ?? [];

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  8,
                  8,
                  8,
                  8,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'History',
                        onPressed: () {
                          setState(() {
                            _showSidebar =
                                !_showSidebar;
                          });
                        },
                        icon: const Icon(
                          Icons.menu_rounded,
                        ),
                      ),

                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFDBEAFE),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color:
                              Color(0xFF2563EB),
                        ),
                      ),

                      const SizedBox(width: 10),

                      const Expanded(
                        child: Text(
                          'Waha AI',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                      ),

                      IconButton(
                        tooltip: 'محادثة جديدة',
                        onPressed: _newChat,
                        icon: const Icon(
                          Icons.edit_square,
                        ),
                      ),

                      IconButton(
                        tooltip: 'الإعدادات',
                        onPressed: _openSettings,
                        icon: const Icon(
                          Icons.settings_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: messages.isEmpty
                    ? _buildWelcome()
                    : ListView.builder(
                        controller:
                            _scrollController,
                        padding:
                            const EdgeInsets.only(
                          top: 14,
                          bottom: 14,
                        ),
                        itemCount:
                            messages.length,
                        itemBuilder: (_, index) {
                          return _buildMessage(
                            messages[index],
                          );
                        },
                      ),
              ),

              _buildInput(),
            ],
          ),

          if (_showSidebar)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showSidebar = false;
                  });
                },
                child: Container(
                  color:
                      const Color(0x33000000),
                ),
              ),
            ),

          if (_showSidebar)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _buildSidebar(),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color:
                    const Color(0xFFDBEAFE),
                borderRadius:
                    BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 40,
                color: Color(0xFF2563EB),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'مرحباً بك في Waha AI',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'مساعد ذكاء اصطناعي متعدد الاستخدامات',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF64748B),
              ),
            ),

            const SizedBox(height: 28),

            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                _suggestion(
                  '💻 البرمجة',
                  'اكتب لي تطبيق Flutter',
                ),
                _suggestion(
                  '📄 تحليل مستند',
                  'حلل هذا المستند',
                ),
                _suggestion(
                  '📊 تحليل بيانات',
                  'حلل بياناتي',
                ),
                _suggestion(
                  '💡 أفكار',
                  'اقترح لي فكرة تطبيق',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(
    String title,
    String text,
  ) {
    return ActionChip(
      avatar: const Icon(
        Icons.auto_awesome,
        size: 17,
      ),
      label: Text(title),
      onPressed: () {
        _controller.text = text;
        _controller.selection =
            TextSelection.collapsed(
          offset: _controller.text.length,
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================
// SETTINGS PAGE
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

  late TextEditingController endpointController;
  late TextEditingController apiKeyController;
  late TextEditingController modelController;

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

    endpointController =
        TextEditingController(
      text: settings.endpoint,
    );

    apiKeyController =
        TextEditingController(
      text: settings.apiKey,
    );

    modelController =
        TextEditingController(
      text: settings.model,
    );
  }

  @override
  void dispose() {
    endpointController.dispose();
    apiKeyController.dispose();
    modelController.dispose();
    super.dispose();
  }

  void _providerChanged(String? value) {
    if (value == null) return;

    setState(() {
      settings.provider = value;

      if (value == 'OpenRouter') {
        endpointController.text =
            'https://openrouter.ai/api/v1/chat/completions';

        if (modelController.text.isEmpty ||
            modelController.text ==
                'gemini-1.5-flash') {
          modelController.text =
              'openai/gpt-4o-mini';
        }
      }

      if (value == 'OpenAI') {
        endpointController.text =
            'https://api.openai.com/v1/chat/completions';

        modelController.text =
            'gpt-4o-mini';
      }

      if (value == 'Gateway') {
        endpointController.text = '';
      }

      if (value == 'Custom') {
        endpointController.text = '';
      }
    });
  }

  Future<void> _save() async {
    settings.endpoint =
        endpointController.text.trim();

    settings.apiKey =
        apiKeyController.text.trim();

    settings.model =
        modelController.text.trim();

    await LocalStorage.saveSettings(settings);

    if (!mounted) return;

    Navigator.pop(
      context,
      settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'مزود الذكاء الاصطناعي',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          DropdownButtonFormField<String>(
            value: settings.provider,
            decoration:
                const InputDecoration(
              labelText: 'Provider',
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
            controller: endpointController,
            decoration:
                const InputDecoration(
              labelText: 'Server / API Endpoint',
              hintText:
                  'https://example.com/v1/chat/completions',
            ),
            keyboardType:
                TextInputType.url,
          ),

          const SizedBox(height: 16),

          TextField(
            controller: apiKeyController,
            obscureText: true,
            decoration:
                const InputDecoration(
              labelText: 'API Key',
              prefixIcon:
                  Icon(Icons.key_outlined),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: modelController,
            decoration:
                const InputDecoration(
              labelText: 'Model',
              hintText:
                  'openai/gpt-4o-mini',
            ),
          ),

          const SizedBox(height: 20),

          SwitchListTile(
            value:
                settings.rememberHistory,
            title: const Text(
              'حفظ History',
            ),
            subtitle: const Text(
              'حفظ المحادثات على الجهاز',
            ),
            onChanged: (value) {
              setState(() {
                settings.rememberHistory =
                    value;
              });
            },
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(
              Icons.save_outlined,
            ),
            label: const Padding(
              padding:
                  EdgeInsets.symmetric(
                vertical: 13,
              ),
              child: Text(
                'حفظ الإعدادات',
              ),
            ),
          ),

          const SizedBox(height: 25),

          const Divider(),

          const SizedBox(height: 10),

          const Text(
            'ملاحظات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Waha AI يستخدم API متوافقاً مع OpenAI في هذه المرحلة. '
            'سنضيف لاحقاً مزودات Gemini وواجهات أخرى وGateway '
            'مع Streaming وتحويل الملفات.',
            style: TextStyle(
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(
                'https://github.com/tayebi7/whah-ai',
              );

              await launchUrl(
                uri,
                mode:
                    LaunchMode.externalApplication,
              );
            },
            icon: const Icon(
              Icons.code,
            ),
            label: const Text(
              'فتح GitHub',
            ),
          ),
        ],
      ),
    );
  }
}
