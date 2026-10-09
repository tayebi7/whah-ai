import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'ai_service.dart';
import 'connectors.dart';
import 'file_processor.dart';
import 'intent.dart';
import 'media_service.dart';
import 'models.dart';
import 'pages.dart';
import 'storage.dart';
import 'theme.dart';
import 'widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.onThemeChanged});

  final ValueChanged<String>? onThemeChanged;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  AppSettings _settings = AppSettings();
  List<ProviderConfig> _providers = [];
  List<Skill> _customSkills = [];
  List<ConnectorConfig> _connectors = [];
  List<ChatHistory> _history = [];
  ChatHistory _chat = ChatHistory(title: 'محادثة جديدة');

  Skill? _activeSkill;
  final List<AttachedFile> _attached = [];
  bool _busy = false;
  bool _cancel = false;
  bool _ready = false;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await LocalStorage.loadSettings();
    final p = await LocalStorage.loadProviders();
    final sk = await LocalStorage.loadCustomSkills();
    final c = await LocalStorage.loadConnectors();
    final h = await LocalStorage.loadHistory();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _providers = p;
      _customSkills = sk;
      _connectors = c;
      _history = h;
      _ready = true;
    });
    widget.onThemeChanged?.call(s.themeMode);
  }

  // ───────────── أدوات ─────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  String _title(String t) {
    final c = t.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (c.isEmpty) return 'محادثة جديدة';
    return c.length <= 40 ? c : '${c.substring(0, 40)}…';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _saveChat() async {
    _chat.updatedAt = DateTime.now();
    final i = _history.indexWhere((c) => c.id == _chat.id);
    if (i >= 0) {
      _history[i] = _chat;
    } else {
      _history.insert(0, _chat);
    }
    _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await LocalStorage.saveHistory(_history);
  }

  List<Skill> get _allSkills => [...kBuiltInSkills, ..._customSkills];

  // ───────────── الملفات ─────────────

  Future<void> _pickFiles(FileType type) async {
    try {
      final files = await FilePicker.pickFiles(type: type);
      if (files.isEmpty) return;
      setState(() {
        for (final f in files) {
          final path = f.path ?? '';
          var size = 0;
          try {
            if (path.isNotEmpty) size = File(path).lengthSync();
          } catch (_) {}
          _attached.add(AttachedFile(name: f.name, path: path, size: size));
        }
      });
    } catch (e) {
      _snack('تعذر اختيار الملفات: $e');
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final cur = _controller.text;
    final sel = _controller.selection;
    final start = sel.start >= 0 ? sel.start : cur.length;
    final end = sel.end >= 0 ? sel.end : cur.length;
    _controller.text = cur.replaceRange(start, end, t);
    _controller.selection = TextSelection.collapsed(offset: start + t.length);
  }

  void _showAttachMenu() {
    final p = context.pal;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
              leading: Icon(icon, color: p.text),
              title: Text(label),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              item(Icons.insert_drive_file_outlined, 'ملف (أي صيغة)', () => _pickFiles(FileType.any)),
              item(Icons.image_outlined, 'صورة', () => _pickFiles(FileType.image)),
              item(Icons.videocam_outlined, 'فيديو', () => _pickFiles(FileType.video)),
              item(Icons.content_paste, 'لصق من الحافظة', _paste),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ───────────── Skills / Connectors / المزودون ─────────────

  Future<void> _openSkills() async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (c, sc) => SkillsSheet(
          controller: sc,
          customSkills: _customSkills,
          activeId: _activeSkill?.id,
          onCustomChanged: (list) async {
            _customSkills = list;
            await LocalStorage.saveCustomSkills(list);
            if (_activeSkill != null && !_allSkills.any((s) => s.id == _activeSkill!.id)) {
              _activeSkill = null;
            }
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    if (!mounted) return;
    if (picked is Skill) {
      setState(() => _activeSkill = picked);
      _focus.requestFocus();
    } else if (picked == 'none') {
      setState(() => _activeSkill = null);
    }
  }

  Future<void> _openConnectors() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (c, sc) => ConnectorsSheet(
          controller: sc,
          connectors: _connectors,
          onChanged: (list) async {
            _connectors = list;
            await LocalStorage.saveConnectors(list);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openProviders() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProvidersPage(
          providers: _providers,
          onChanged: (list) async {
            _providers = list;
            await LocalStorage.saveProviders(list);
            if (_settings.activeProviderId != 'auto' &&
                !list.any((p) => p.id == _settings.activeProviderId)) {
              _settings.activeProviderId = 'auto';
              await LocalStorage.saveSettings(_settings);
            }
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
          onChanged: (s) async {
            _settings = s;
            await LocalStorage.saveSettings(s);
            widget.onThemeChanged?.call(s.themeMode);
            if (mounted) setState(() {});
          },
          onClearHistory: () async {
            _history.clear();
            _chat = ChatHistory(title: 'محادثة جديدة');
            await LocalStorage.saveHistory(_history);
            if (mounted) setState(() {});
          },
          onOpenProviders: _openProviders,
        ),
      ),
    );
  }

  void _showProviderPicker() {
    final p = context.pal;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        Future<void> choose(String id) async {
          _settings.activeProviderId = id;
          await LocalStorage.saveSettings(_settings);
          if (mounted) setState(() {});
          if (ctx.mounted) Navigator.pop(ctx);
        }

        final usable = _providers.where((e) => e.usable).toList();
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            children: [
              ListTile(
                leading: Icon(Icons.autorenew, color: p.accent),
                title: const Text('تلقائي'),
                subtitle: const Text('يجرب المزودين بالترتيب وينتقل عند الفشل'),
                trailing: _settings.activeProviderId == 'auto'
                    ? Icon(Icons.check, color: p.accent)
                    : null,
                onTap: () => choose('auto'),
              ),
              const Divider(height: 1),
              if (usable.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا يوجد مزود جاهز. أضف مفتاح API من «إدارة المزودين».'),
                ),
              for (final pr in usable)
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(pr.name),
                  subtitle: Text(pr.model.isEmpty ? '—' : pr.model,
                      textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                  trailing: _settings.activeProviderId == pr.id
                      ? Icon(Icons.check, color: p.accent)
                      : null,
                  onTap: () => choose(pr.id),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('إدارة المزودين'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openProviders();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String get _providerLabel {
    if (_settings.activeProviderId == 'auto') return 'تلقائي';
    for (final p in _providers) {
      if (p.id == _settings.activeProviderId) return p.name;
    }
    return 'تلقائي';
  }

  // ───────────── المحادثات ─────────────

  void _newChat() {
    if (_busy) return;
    setState(() {
      _chat = ChatHistory(title: 'محادثة جديدة');
      _attached.clear();
      _controller.clear();
      _activeSkill = null;
    });
  }

  void _selectChat(ChatHistory c) {
    if (_busy) return;
    setState(() {
      _chat = c;
      _attached.clear();
      _controller.clear();
    });
    _scrollToBottom();
  }

  Future<void> _deleteChat(ChatHistory c) async {
    setState(() {
      _history.removeWhere((e) => e.id == c.id);
      if (_chat.id == c.id) _chat = ChatHistory(title: 'محادثة جديدة');
    });
    await LocalStorage.saveHistory(_history);
  }

  // ───────────── الإرسال ─────────────

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_busy || (text.isEmpty && _attached.isEmpty)) return;
    final files = List<AttachedFile>.from(_attached);
    final user = ChatMessage(role: 'user', content: text, files: files);
    final asst = ChatMessage(role: 'assistant');
    setState(() {
      if (_chat.messages.isEmpty) {
        _chat.title = _title(text.isEmpty ? files.first.name : text);
      }
      _chat.messages.add(user);
      _chat.messages.add(asst);
      _attached.clear();
      _controller.clear();
    });
    _scrollToBottom();
    await _respond(user, asst);
  }

  Future<void> _regenerate(ChatMessage asst) async {
    if (_busy) return;
    final i = _chat.messages.indexOf(asst);
    if (i <= 0) return;
    final user = _chat.messages[i - 1];
    if (user.role != 'user') return;
    setState(() {
      asst.content = '';
      asst.media.clear();
      asst.isError = false;
    });
    await _respond(user, asst);
  }

  void _stop() {
    _cancel = true;
  }

  List<LlmMessage> _buildMessages(
      ChatMessage current, IntentResult intent, List<ImagePart> images, String effective) {
    final sys = StringBuffer(_settings.systemPrompt.trim());
    if (_settings.userName.trim().isNotEmpty) {
      sys.write('\nاسم المستخدم: ${_settings.userName.trim()}.');
    }
    sys.write('\nالتاريخ اليوم: ${DateTime.now().toIso8601String().substring(0, 10)}.');
    if (intent.addon.isNotEmpty) sys.write('\n\n${intent.addon}');

    String textOf(ChatMessage m) {
      final base = m.content;
      return m.context.isEmpty ? base : '$base\n\n${m.context}';
    }

    final idx = _chat.messages.indexOf(current);
    final hist = _chat.messages
        .sublist(0, idx < 0 ? 0 : idx)
        .where((m) => !m.isError && textOf(m).trim().isNotEmpty)
        .toList();
    var budget = 60000;
    final picked = <LlmMessage>[];
    for (var i = hist.length - 1; i >= 0 && budget > 0; i--) {
      final t = textOf(hist[i]);
      budget -= t.length;
      picked.insert(0, LlmMessage(hist[i].role, t));
    }
    return [
      LlmMessage('system', sys.toString()),
      ...picked,
      LlmMessage('user', effective, images: images),
    ];
  }

  Future<void> _respond(ChatMessage user, ChatMessage asst) async {
    setState(() {
      _busy = true;
      _cancel = false;
      asst.status = 'جارٍ التحضير…';
      asst.isError = false;
    });
    bool cancelled() => _cancel;

    try {
      // 1) قراءة الملفات
      final processed = <ProcessedFile>[];
      for (final f in user.files) {
        if (mounted) setState(() => asst.status = 'قراءة ${f.name}…');
        processed.add(await FileProcessor.process(f, maxChars: _settings.maxFileChars));
      }
      final images = <ImagePart>[
        for (final pf in processed) ...pf.images,
      ];
      if (images.length > 10) images.removeRange(10, images.length);
      final hasVideo = processed.any((p) => p.kind == FileKind.video);
      final hasImages = processed.any((p) => p.kind == FileKind.image) ||
          (images.isNotEmpty && !hasVideo);
      final exts = user.files.map((f) => FileProcessor.extOf(f.name)).toList();

      // 2) التعرف على نوع السؤال
      IntentResult intent;
      if (_settings.autoIntent || _activeSkill != null) {
        final detected = IntentDetector.detect(user.content,
            hasImages: hasImages, hasVideo: hasVideo, fileExts: exts);
        if (detected.isGeneration) {
          intent = detected;
        } else if (_activeSkill != null) {
          intent = IntentResult(Intent.chat,
              needsVision: images.isNotEmpty,
              label: _activeSkill!.title,
              addon: _activeSkill!.instruction);
        } else {
          intent = detected;
        }
      } else {
        intent = IntentResult(Intent.chat, needsVision: images.isNotEmpty);
      }
      if (mounted) setState(() => asst.intentLabel = intent.label);

      // 3) السياق: ملفات + روابط
      var ctx = FileProcessor.buildContext(processed,
          maxChars: _settings.maxFileChars,
          normalizeNumbers: intent.intent == Intent.finance);
      final urls = UrlContext.extract(user.content);
      if (urls.isNotEmpty) {
        if (mounted) setState(() => asst.status = 'قراءة الروابط…');
        final u = await UrlContext.build(urls, _connectors);
        ctx = ctx.isEmpty ? u : '$ctx\n\n$u';
      }
      user.context = ctx;

      if (intent.intent == Intent.imageGen) {
        await _generateImage(user, asst, cancelled);
        return;
      }
      if (intent.intent == Intent.videoGen) {
        await _generateVideo(user, asst, cancelled);
        return;
      }

      // 4) المحادثة
      final base = user.content.isEmpty
          ? 'حلل المرفقات وأخبرني بأهم ما فيها.'
          : user.content;
      final effective = ctx.isEmpty ? base : '$base\n\n$ctx';
      final msgs = _buildMessages(user, intent, images, effective);

      if (mounted) setState(() => asst.status = 'جارٍ الاتصال…');
      final res = await ChatRouter.run(
        providers: _providers,
        messages: msgs,
        activeId: _settings.activeProviderId,
        autoSwitch: _settings.autoSwitch,
        vision: images.isNotEmpty,
        stream: _settings.streamEnabled,
        isCancelled: cancelled,
        onProvider: (name) {
          if (!mounted) return;
          setState(() {
            asst.provider = name;
            asst.status = 'الاتصال بـ $name…';
            asst.content = '';
          });
        },
        onChunk: (c) {
          if (!mounted) return;
          setState(() {
            asst.status = '';
            asst.content += c;
          });
          _scrollToBottom();
        },
      );
      if (mounted) {
        setState(() {
          if (asst.content.trim().isEmpty) asst.content = res.text;
          asst.provider = res.provider;
        });
      }
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == 'cancel') {
          if (asst.content.isEmpty) asst.content = '(تم الإيقاف)';
        } else {
          asst.isError = true;
          asst.content = _errorText(e);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        asst.isError = true;
        asst.content = '⚠️ حدث خطأ غير متوقع:\n\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          asst.status = '';
          if (_cancel && asst.content.trim().isEmpty && asst.media.isEmpty) {
            asst.content = '(تم الإيقاف)';
          }
        });
      }
      await _saveChat();
      _scrollToBottom();
    }
  }

  String _errorText(LlmException e) {
    final b = StringBuffer('⚠️ تعذر الحصول على إجابة\n\n${e.message}\n\n');
    if (e.kind == 'config') {
      b.write('افتح «إدارة المزودين» وتأكد من العنوان والمفتاح واسم النموذج.');
    } else {
      b.write('جرّب: زر «إدارة المزودين» ← اختبار الاتصال، أو أضف مزوداً آخر ليتم الانتقال إليه تلقائياً.');
    }
    return b.toString();
  }

  // ───────────── توليد الوسائط ─────────────

  Future<String> _englishPrompt(String text, String kind) async {
    try {
      final r = await ChatRouter.quick(
        providers: _providers,
        system: 'Convert the user request into ONE detailed English prompt for a $kind generation model '
            '(subject, style, lighting, composition, colors, mood). Output ONLY the prompt, no quotes or explanations.',
        user: text,
        activeId: _settings.activeProviderId,
        autoSwitch: _settings.autoSwitch,
      );
      return r.isEmpty ? text : r;
    } catch (_) {
      return text;
    }
  }

  Future<void> _generateImage(ChatMessage user, ChatMessage asst, bool Function() cancelled) async {
    final text = user.content;
    if (mounted) setState(() => asst.status = 'تحسين وصف الصورة…');
    final prompt = await _englishPrompt(text, 'image');
    try {
      final r = await MediaService.generateImage(
        prompt: prompt,
        providers: _providers,
        isCancelled: cancelled,
        onStatus: (s) {
          if (mounted) setState(() => asst.status = s);
        },
      );
      final item = await MediaService.save(r);
      if (!mounted) return;
      setState(() {
        asst.media.add(item);
        asst.provider = r.provider;
        asst.content = 'تم توليد الصورة.\n\n> الوصف المستخدم: $prompt';
      });
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == 'cancel') {
          asst.content = '(تم الإيقاف)';
        } else {
          asst.isError = true;
          asst.content = '⚠️ تعذر توليد الصورة\n\n${e.message}\n\n'
              'يمكنك إضافة مزود يدعم الصور (OpenAI / Together ...) وكتابة «نموذج الصور» في إعداداته.\n\n'
              'الوصف المحسّن:\n```\n$prompt\n```';
        }
      });
    }
  }

  Future<void> _generateVideo(ChatMessage user, ChatMessage asst, bool Function() cancelled) async {
    final text = user.content;
    if (mounted) setState(() => asst.status = 'تحسين وصف الفيديو…');
    final prompt = await _englishPrompt(text, 'video');
    try {
      final r = await MediaService.generateVideo(
        prompt: prompt,
        providers: _providers,
        isCancelled: cancelled,
        onStatus: (s) {
          if (mounted) setState(() => asst.status = s);
        },
      );
      final item = await MediaService.save(r);
      if (!mounted) return;
      setState(() {
        asst.media.add(item);
        asst.provider = r.provider;
        asst.content = 'تم توليد الفيديو.\n\n> الوصف المستخدم: $prompt';
      });
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == 'cancel') {
          asst.content = '(تم الإيقاف)';
        } else {
          asst.isError = true;
          asst.content = '⚠️ تعذر توليد الفيديو\n\n${e.message}\n\n'
              'توليد الفيديو يحتاج مزوداً يدعمه (مثل OpenAI Sora) مع كتابة «نموذج الفيديو» في إعداداته.\n\n'
              'يمكنك استخدام هذا الوصف في أي مولّد فيديو:\n```\n$prompt\n```';
        }
      });
    }
  }

  // ───────────── الموصلات ─────────────

  Future<void> _sendToConnector(String text) async {
    final list = _connectors.where(ConnectorActions.canSend).toList();
    if (list.isEmpty) {
      _snack('أضف موصل Telegram أو Webhook أولاً من زر الموصلات');
      return;
    }
    ConnectorConfig? target;
    if (list.length == 1) {
      target = list.first;
    } else {
      target = await showModalBottomSheet<ConnectorConfig>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('إرسال إلى…', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final c in list)
                ListTile(
                  leading: const Icon(Icons.send_outlined),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      );
    }
    if (target == null) return;
    try {
      final msg = await ConnectorActions.send(target, text);
      _snack(msg);
    } catch (e) {
      _snack('فشل الإرسال: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  // ───────────── الواجهة ─────────────

  Widget _drawer() {
    final p = context.pal;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const SparkIcon(size: 26),
                  const SizedBox(width: 10),
                  const Text('WHAH AI',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, fontFamily: 'serif')),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('المحادثات', style: TextStyle(color: p.text2, fontSize: 13)),
              ),
            ),
            Expanded(
              child: _history.isEmpty
                  ? Center(child: Text('لا توجد محادثات', style: TextStyle(color: p.text2)))
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, i) {
                        final c = _history[i];
                        final sel = c.id == _chat.id;
                        return ListTile(
                          selected: sel,
                          selectedTileColor: p.userBubble,
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 19),
                            onPressed: () => _deleteChat(c),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _selectChat(c);
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('المزودون'),
              onTap: () {
                Navigator.pop(context);
                _openProviders();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('الإعدادات'),
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

  Widget _welcome() {
    final p = context.pal;
    final name = _settings.userName.trim();
    final hasProvider = _providers.any((e) => e.usable);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SparkIcon(size: 46),
            const SizedBox(height: 22),
            Text(
              name.isEmpty ? 'كيف أساعدك اليوم؟' : 'مرحباً، $name',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 31,
                fontWeight: FontWeight.w500,
                color: p.text,
              ),
            ),
            if (!hasProvider) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _openProviders,
                icon: const Icon(Icons.key),
                label: const Text('أضف مزود ذكاء اصطناعي'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _userBubble(ChatMessage m) {
    final p = context.pal;
    final images = m.files.where((f) => FileProcessor.kindOf(f.name) == FileKind.image).toList();
    final others = m.files.where((f) => FileProcessor.kindOf(f.name) != FileKind.image).toList();
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: p.userBubble,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in images)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LocalImage(path: f.path, width: 110, height: 110),
                      ),
                  ],
                ),
              ),
            for (final f in others)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FileProcessor.kindOf(f.name) == FileKind.video
                          ? Icons.videocam_outlined
                          : Icons.description_outlined,
                      size: 18,
                      color: p.text2,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${f.name} · ${f.sizeLabel}',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            if (m.content.isNotEmpty)
              SelectableText(m.content, style: TextStyle(fontSize: 16, height: 1.5, color: p.text)),
          ],
        ),
      ),
    );
  }

  Widget _assistantBlock(ChatMessage m, {required bool isLast}) {
    final p = context.pal;
    final working = _busy && isLast;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SparkIcon(size: 18),
              const SizedBox(width: 8),
              if (m.provider.isNotEmpty)
                Text(m.provider, style: TextStyle(fontSize: 12, color: p.text2)),
              if (m.intentLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.userBubble,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(m.intentLabel, style: TextStyle(fontSize: 11.5, color: p.text2)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (working && m.status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Flexible(child: Text(m.status, style: TextStyle(color: p.text2))),
                ],
              ),
            ),
          for (final it in m.media)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: it.kind == 'video'
                  ? VideoCard(path: it.path)
                  : GestureDetector(
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => ImageViewerPage(path: it.path)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: LocalImage(path: it.path, fit: BoxFit.cover),
                      ),
                    ),
            ),
          if (m.content.isNotEmpty)
            MarkdownBody(
              data: m.content,
              selectable: true,
              styleSheet: markdownStyle(context),
              onTapLink: (text, href, title) => openLink(href),
            ),
          if (!working && (m.content.isNotEmpty || m.media.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _action(Icons.copy_outlined, 'نسخ', () async {
                    await Clipboard.setData(ClipboardData(text: m.content));
                    _snack('تم النسخ');
                  }),
                  if (m.media.isNotEmpty)
                    _action(Icons.ios_share, 'مشاركة / حفظ', () => shareFile(m.media.first.path))
                  else
                    _action(Icons.ios_share, 'مشاركة', () => shareText(m.content)),
                  if (_connectors.any(ConnectorActions.canSend) && m.content.isNotEmpty)
                    _action(Icons.send_outlined, 'إرسال إلى موصل', () => _sendToConnector(m.content)),
                  if (isLast)
                    _action(Icons.refresh, 'إعادة التوليد', () => _regenerate(m)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: context.pal.text2),
    );
  }

  Widget _composer() {
    final p = context.pal;
    final hasText = _controller.text.trim().isNotEmpty || _attached.isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_attached.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attached.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final f = _attached[i];
                      return InputChip(
                        avatar: Icon(
                          switch (FileProcessor.kindOf(f.name)) {
                            FileKind.image => Icons.image_outlined,
                            FileKind.video => Icons.videocam_outlined,
                            _ => Icons.description_outlined,
                          },
                          size: 16,
                        ),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(f.name, overflow: TextOverflow.ellipsis),
                        ),
                        onDeleted: () => setState(() => _attached.removeAt(i)),
                      );
                    },
                  ),
                ),
              if (_activeSkill != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InputChip(
                      avatar: Icon(Icons.bolt, size: 16, color: p.accent),
                      label: Text(_activeSkill!.title),
                      onDeleted: () => setState(() => _activeSkill = null),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 16.5),
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالتك…',
                    hintStyle: TextStyle(color: p.text2),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              Row(
                children: [
                  _roundButton(Icons.add, 'إرفاق', _busy ? null : _showAttachMenu),
                  _roundButton(Icons.bolt_outlined, 'Skills', _busy ? null : _openSkills,
                      active: _activeSkill != null),
                  _roundButton(Icons.hub_outlined, 'الموصلات', _busy ? null : _openConnectors,
                      active: _connectors.any((c) => c.enabled)),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _busy ? null : _showProviderPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(_providerLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, color: p.text2)),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 18, color: p.text2),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _busy
                      ? IconButton.filled(
                          onPressed: _stop,
                          style: IconButton.styleFrom(backgroundColor: p.text, foregroundColor: p.bg),
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          onPressed: hasText ? _send : null,
                          style: IconButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: p.border,
                            disabledForegroundColor: p.text2,
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) {
    final p = context.pal;
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: active ? p.accent : p.text2),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final empty = _chat.messages.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          empty ? '' : _chat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'محادثة جديدة',
            onPressed: _newChat,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      drawer: _drawer(),
      body: Column(
        children: [
          Expanded(
            child: empty
                ? _welcome()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    itemCount: _chat.messages.length,
                    itemBuilder: (context, i) {
                      final m = _chat.messages[i];
                      return m.role == 'user'
                          ? _userBubble(m)
                          : _assistantBlock(m, isLast: i == _chat.messages.length - 1);
                    },
                  ),
          ),
          _composer(),
        ],
      ),
    );
  }
}
