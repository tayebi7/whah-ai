import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const WhahApp());

// ======================= الألوان =======================
const kBg = Color(0xFF0B0F1E);
const kCard = Color(0xFF151B31);
const kPrimary = Color(0xFF7C5CFF);
const kAccent = Color(0xFF22D3EE);

// ======================= الأوضاع =======================
class Mode {
  final String id, label, emoji;
  const Mode(this.id, this.label, this.emoji);
}

const modes = [
  Mode('auto', 'تلقائي', '✨'),
  Mode('chat', 'شات', '💬'),
  Mode('code', 'برمجة', '👨‍💻'),
  Mode('android', 'أندرويد', '🤖'),
  Mode('linux', 'لينكس', '🐧'),
  Mode('enigma2', 'Enigma2', '🛰'),
];

Mode modeById(String id) =>
    modes.firstWhere((m) => m.id == id, orElse: () => modes.first);

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
        colorScheme: const ColorScheme.dark(primary: kPrimary, secondary: kAccent),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          colors: [kPrimary, kAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: kPrimary.withOpacity(0.45), blurRadius: size * 0.4),
        ],
      ),
      child: Center(
        child: Text('W',
            style: TextStyle(
                fontSize: size * 0.6,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      ),
    );
  }
}

// ======================= الرسالة =======================
class Msg {
  final String role; // user | assistant
  final String text;
  final String? mode;
  Msg(this.role, this.text, [this.mode]);
}

// ======================= شاشة الشات =======================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Msg> _msgs = [];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String _mode = 'auto';
  bool _loading = false;
  String _serverUrl = 'http://10.0.2.2:3000';
  String _token = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _serverUrl = p.getString('server') ?? _serverUrl;
      _token = p.getString('token') ?? '';
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(Msg('user', text));
      _loading = true;
    });
    _toBottom();

    try {
      final history = _msgs
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      final res = await http
          .post(
            Uri.parse('$_serverUrl/chat'),
            headers: {
              'Content-Type': 'application/json',
              if (_token.isNotEmpty) 'x-app-token': _token,
            },
            body: jsonEncode({'mode': _mode, 'messages': history}),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) {
        throw Exception(data['error'] ?? 'خطأ ${res.statusCode}');
      }
      setState(() => _msgs.add(Msg('assistant', data['reply'], data['mode'])));
    } catch (e) {
      setState(() => _msgs.add(Msg('assistant', '⚠️ تعذر الاتصال بالسيرفر:\n$e')));
    } finally {
      setState(() => _loading = false);
      _toBottom();
    }
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _openSettings() async {
    final s = TextEditingController(text: _serverUrl);
    final t = TextEditingController(text: _token);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('الإعدادات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
              controller: s,
              decoration: const InputDecoration(
                  labelText: 'رابط السيرفر', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: t,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'رمز التطبيق (اختياري)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.setString('server', s.text.trim());
              await p.setString('token', t.text.trim());
              setState(() {
                _serverUrl = s.text.trim();
                _token = t.text.trim();
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        titleSpacing: 16,
        title: Row(children: [
          const WhahLogo(size: 34),
          const SizedBox(width: 10),
          const Text('whah ai',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(_msgs.clear)),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(children: [
        _modeBar(),
        Expanded(
          child: _msgs.isEmpty
              ? _welcome()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _msgs.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) =>
                      i == _msgs.length ? _typing() : _bubble(_msgs[i]),
                ),
        ),
        _inputBar(),
      ]),
    );
  }

  Widget _modeBar() => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final m in modes)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${m.emoji} ${m.label}'),
                  selected: _mode == m.id,
                  selectedColor: kPrimary,
                  backgroundColor: kCard,
                  side: BorderSide.none,
                  onSelected: (_) => setState(() => _mode = m.id),
                ),
              ),
          ],
        ),
      );

  Widget _welcome() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const WhahLogo(size: 84),
            const SizedBox(height: 20),
            const Text('مرحباً بك في whah ai',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
                'اكتب طلبك وسأختار الوضع المناسب تلقائياً:\nبرمجة، أندرويد، لينكس، أو Enigma2.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, height: 1.5)),
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final q in [
                'اكتب إضافة Enigma2 تعرض الطقس',
                'اشرح لي كود Python',
                'سكربت bash لنسخ احتياطي',
              ])
                ActionChip(
                  label: Text(q),
                  backgroundColor: kCard,
                  onPressed: () {
                    _ctrl.text = q;
                    _send();
                  },
                ),
            ]),
          ]),
        ),
      );

  Widget _bubble(Msg m) {
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          gradient: user
              ? const LinearGradient(colors: [kPrimary, Color(0xFF5B8CFF)])
              : null,
          color: user ? null : kCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!user && m.mode != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${modeById(m.mode!).emoji} ${modeById(m.mode!).label}',
                  style: const TextStyle(color: kAccent, fontSize: 12)),
            ),
          user
              ? SelectableText(m.text, style: const TextStyle(height: 1.4))
              : MarkdownBody(
                  data: m.text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    code: const TextStyle(
                        fontFamily: 'monospace',
                        backgroundColor: Color(0xFF0B0F1E)),
                    codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF0B0F1E),
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
          if (!user)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم النسخ')));
                },
                child: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.copy, size: 16, color: Colors.white38),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _typing() => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: kAccent)),
        ),
      );

  Widget _inputBar() => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'اكتب رسالتك...',
                  filled: true,
                  fillColor: kCard,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [kPrimary, kAccent]),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ]),
        ),
      );
}
