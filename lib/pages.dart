import 'package:flutter/material.dart';

import 'ai_service.dart';
import 'connectors.dart';
import 'models.dart';
import 'net_utils.dart';
import 'theme.dart';
import 'widgets.dart';

// ═════════════════════════════ المزودون ═════════════════════════════

class ProvidersPage extends StatefulWidget {
  final List<ProviderConfig> providers;
  final Future<void> Function(List<ProviderConfig>) onChanged;

  const ProvidersPage({super.key, required this.providers, required this.onChanged});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  late List<ProviderConfig> _list;

  @override
  void initState() {
    super.initState();
    _list = List<ProviderConfig>.from(widget.providers);
  }

  /// كل تغيير يُحفظ فوراً في التخزين (لا حاجة لزر حفظ رئيسي)
  Future<void> _commit() async {
    if (mounted) setState(() {});
    await widget.onChanged(List<ProviderConfig>.from(_list));
  }

  Future<void> _add() async {
    final r = await Navigator.push<ProviderConfig>(
      context,
      MaterialPageRoute(builder: (_) => const ProviderEditPage()),
    );
    if (r == null) return;
    _list.add(r);
    await _commit();
  }

  Future<void> _edit(ProviderConfig p) async {
    final r = await Navigator.push<ProviderConfig>(
      context,
      MaterialPageRoute(builder: (_) => ProviderEditPage(initial: p)),
    );
    if (r == null) return;
    final i = _list.indexWhere((e) => e.id == p.id);
    if (i >= 0) _list[i] = r;
    await _commit();
  }

  Future<void> _delete(ProviderConfig p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المزود'),
        content: Text('حذف «${p.name}» ومفتاحه من الجهاز؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    _list.removeWhere((e) => e.id == p.id);
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('المزودون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: p.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مزود'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'الترتيب هو أولوية التبديل التلقائي: عند فشل مزود ينتقل التطبيق إلى التالي. '
              'اسحب ≡ لإعادة الترتيب. كل تغيير يُحفظ فوراً.',
              style: TextStyle(color: p.text2, fontSize: 13, height: 1.45),
            ),
          ),
          Expanded(
            child: _list.isEmpty
                ? Center(child: Text('لا يوجد مزودون بعد', style: TextStyle(color: p.text2)))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    buildDefaultDragHandles: false,
                    itemCount: _list.length,
                    onReorder: (o, n) async {
                      if (n > o) n -= 1;
                      final it = _list.removeAt(o);
                      _list.insert(n, it);
                      await _commit();
                    },
                    itemBuilder: (context, i) {
                      final pr = _list[i];
                      final status = providerStatus(pr);
                      final ready = status == 'جاهز';
                      return Card(
                        key: ValueKey(pr.id),
                        elevation: 0,
                        color: p.surface,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: p.border),
                        ),
                        child: ListTile(
                          onTap: () => _edit(pr),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_handle, color: p.text2),
                          ),
                          title: Text(pr.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${pr.model.isEmpty ? '—' : pr.model} · $status'
                            '${pr.imageModel.isNotEmpty ? ' · صور' : ''}'
                            '${pr.videoModel.isNotEmpty ? ' · فيديو' : ''}',
                            style: TextStyle(color: ready ? p.text2 : p.danger, fontSize: 12.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: pr.enabled,
                                onChanged: (v) {
                                  pr.enabled = v;
                                  _commit();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _delete(pr),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ProviderEditPage extends StatefulWidget {
  final ProviderConfig? initial;
  const ProviderEditPage({super.key, this.initial});

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  // كل الحقول فارغة عند الإضافة الجديدة
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _vision = TextEditingController();
  final _image = TextEditingController();
  final _video = TextEditingController();
  String _format = 'auto';
  bool _needsKey = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _name.text = i.name;
      _endpoint.text = i.endpoint;
      _key.text = i.apiKey;
      _model.text = i.model;
      _vision.text = i.visionModel;
      _image.text = i.imageModel;
      _video.text = i.videoModel;
      _format = i.format;
      _needsKey = i.needsKey;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _endpoint, _key, _model, _vision, _image, _video]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(ProviderPreset p) {
    setState(() {
      _name.text = p.name;
      _endpoint.text = p.endpoint;
      _model.text = p.model;
      _vision.text = p.visionModel;
      _image.text = p.imageModel;
      _video.text = p.videoModel;
      _format = p.format;
      _needsKey = p.needsKey;
      _key.clear(); // المفتاح يبقى فارغاً دائماً
      _testResult = null;
    });
  }

  /// لصق JSON كامل في خانة العنوان يملأ الحقول تلقائياً
  void _onEndpointChanged(String v) {
    final j = Sanitize.parseProviderJson(v);
    if (j != null) {
      setState(() {
        if (j['endpoint']!.isNotEmpty) _endpoint.text = j['endpoint']!;
        if (j['apiKey']!.isNotEmpty) _key.text = j['apiKey']!;
        if (j['model']!.isNotEmpty) _model.text = j['model']!;
        if (j['name']!.isNotEmpty && _name.text.isEmpty) _name.text = j['name']!;
      });
      return;
    }
    setState(() {});
  }

  ProviderConfig _build() {
    final i = widget.initial;
    return ProviderConfig(
      id: i?.id,
      name: Sanitize.text(_name.text),
      endpoint: Sanitize.url(_endpoint.text),
      apiKey: Sanitize.key(_key.text),
      model: Sanitize.model(_model.text),
      visionModel: Sanitize.model(_vision.text),
      imageModel: Sanitize.model(_image.text),
      videoModel: Sanitize.model(_video.text),
      format: _format,
      enabled: i?.enabled ?? true,
      needsKey: _needsKey,
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _save() {
    final cfg = _build();
    final ep = ApiEndpoints.parse(cfg.endpoint, format: cfg.format);
    if (ep.error != null) {
      _snack(ep.error!);
      return;
    }
    if (cfg.model.isEmpty && cfg.imageModel.isEmpty && cfg.videoModel.isEmpty && !ep.isPollinations) {
      _snack('اكتب اسم النموذج (Model)');
      return;
    }
    if (cfg.name.isEmpty) cfg.name = ep.host;
    Navigator.pop(context, cfg);
  }

  Future<void> _test() async {
    final cfg = _build();
    final ep = ApiEndpoints.parse(cfg.endpoint, format: cfg.format);
    if (ep.error != null) {
      setState(() => _testResult = '❌ ${ep.error}');
      return;
    }
    if (cfg.needsKey && cfg.apiKey.isEmpty) {
      setState(() => _testResult = '❌ أدخل مفتاح API');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final err = await AIService(cfg).test();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = err == null ? '✅ الاتصال ناجح' : '❌ $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final adding = widget.initial == null;
    final ep = ApiEndpoints.parse(_endpoint.text, format: _format);
    final preview = _endpoint.text.trim().isEmpty
        ? null
        : (ep.error ?? 'سيُستخدم: ${ep.chatUrl}');
    return Scaffold(
      appBar: AppBar(
        title: Text(adding ? 'إضافة مزود' : 'تعديل المزود'),
        actions: [
          TextButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (adding) ...[
            Text('قوالب جاهزة (اختياري)', style: TextStyle(color: p.text2, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in kProviderPresets)
                  ActionChip(
                    label: Text(t.name),
                    backgroundColor: p.surface,
                    side: BorderSide(color: p.border),
                    onPressed: () => _applyPreset(t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'اسم المزود',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          LtrField(
            controller: _endpoint,
            label: 'العنوان (API URL)',
            hint: 'api.example.com/v1',
            icon: Icons.link,
            keyboardType: TextInputType.url,
            onChanged: _onEndpointChanged,
            helper: preview ??
                'يقبل بدون https، أو مع /chat/completions، أو رابط ينتهي بـ .json، أو JSON كامل.',
          ),
          const SizedBox(height: 12),
          LtrField(
            controller: _key,
            label: 'مفتاح API',
            icon: Icons.key_outlined,
            secret: true,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('يحتاج مفتاح API'),
            value: _needsKey,
            onChanged: (v) => setState(() => _needsKey = v),
          ),
          LtrField(
            controller: _model,
            label: 'النموذج (Model)',
            icon: Icons.smart_toy_outlined,
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('متقدم: الرؤية والصور والفيديو'),
              children: [
                const SizedBox(height: 8),
                LtrField(
                  controller: _vision,
                  label: 'نموذج الرؤية (لتحليل الصور) — اختياري',
                  icon: Icons.visibility_outlined,
                ),
                const SizedBox(height: 12),
                LtrField(
                  controller: _image,
                  label: 'نموذج توليد الصور — اختياري',
                  icon: Icons.image_outlined,
                ),
                const SizedBox(height: 12),
                LtrField(
                  controller: _video,
                  label: 'نموذج توليد الفيديو — اختياري',
                  icon: Icons.movie_outlined,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('صيغة الواجهة', style: TextStyle(color: p.text2, fontSize: 13)),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('تلقائي')),
                    ButtonSegment(value: 'openai', label: Text('OpenAI')),
                    ButtonSegment(value: 'anthropic', label: Text('Anthropic')),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) => setState(() => _format = s.first),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: Text(_testing ? 'جارٍ الاختبار…' : 'اختبار الاتصال'),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('✅') ? Colors.green.shade700 : p.danger,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(adding ? 'إضافة وحفظ' : 'حفظ التعديلات'),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════ Skills ═════════════════════════════

class SkillsSheet extends StatefulWidget {
  final ScrollController controller;
  final List<Skill> customSkills;
  final String? activeId;
  final Future<void> Function(List<Skill>) onCustomChanged;

  const SkillsSheet({
    super.key,
    required this.controller,
    required this.customSkills,
    required this.activeId,
    required this.onCustomChanged,
  });

  @override
  State<SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends State<SkillsSheet> {
  late List<Skill> _custom;

  @override
  void initState() {
    super.initState();
    _custom = List<Skill>.from(widget.customSkills);
  }

  Future<void> _addSkill() async {
    final title = TextEditingController();
    final instr = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مهارة جديدة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم المهارة')),
              const SizedBox(height: 12),
              TextField(
                controller: instr,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'التعليمات',
                  hintText: 'مثال: أجب كخبير قانوني جزائري واذكر المواد…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final t = Sanitize.text(title.text);
    final i = instr.text.trim();
    title.dispose();
    instr.dispose();
    if (ok != true || t.isEmpty || i.isEmpty) return;
    _custom.add(Skill(title: t, instruction: i));
    await widget.onCustomChanged(List<Skill>.from(_custom));
    if (mounted) setState(() {});
  }

  Future<void> _delete(Skill s) async {
    _custom.removeWhere((e) => e.id == s.id);
    await widget.onCustomChanged(List<Skill>.from(_custom));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = [...kBuiltInSkills, ..._custom];
    final cats = <String>[];
    for (final s in all) {
      if (!cats.contains(s.category)) cats.add(s.category);
    }
    return SheetScaffold(
      controller: widget.controller,
      title: 'Skills',
      subtitle: 'المهارة المختارة تُطبَّق على رسائلك حتى تلغيها. بدونها يتعرف التطبيق على نوع السؤال تلقائياً.',
      children: [
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('تلقائي (بدون مهارة)'),
              backgroundColor: widget.activeId == null ? p.userBubble : p.surface,
              side: BorderSide(color: p.border),
              onPressed: () => Navigator.pop(context, 'none'),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('مهارة جديدة'),
              backgroundColor: p.surface,
              side: BorderSide(color: p.border),
              onPressed: _addSkill,
            ),
          ],
        ),
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(cat, style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in all.where((e) => e.category == cat))
                GestureDetector(
                  onLongPress: s.builtIn ? null : () => _delete(s),
                  child: ActionChip(
                    label: Text(s.title),
                    backgroundColor: widget.activeId == s.id ? p.userBubble : p.surface,
                    side: BorderSide(
                      color: widget.activeId == s.id ? p.accent : p.border,
                    ),
                    onPressed: () => Navigator.pop(context, s),
                  ),
                ),
            ],
          ),
        ],
        if (_custom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text('اضغط مطولاً على مهارتك المخصصة لحذفها.',
                style: TextStyle(color: p.text2, fontSize: 12.5)),
          ),
      ],
    );
  }
}

// ═════════════════════════════ Connectors ═════════════════════════════

class ConnectorsSheet extends StatefulWidget {
  final ScrollController controller;
  final List<ConnectorConfig> connectors;
  final Future<void> Function(List<ConnectorConfig>) onChanged;

  const ConnectorsSheet({
    super.key,
    required this.controller,
    required this.connectors,
    required this.onChanged,
  });

  @override
  State<ConnectorsSheet> createState() => _ConnectorsSheetState();
}

class _ConnectorsSheetState extends State<ConnectorsSheet> {
  late List<ConnectorConfig> _list;

  @override
  void initState() {
    super.initState();
    _list = List<ConnectorConfig>.from(widget.connectors);
  }

  Future<void> _commit() async {
    if (mounted) setState(() {});
    await widget.onChanged(List<ConnectorConfig>.from(_list));
  }

  Future<void> _add() async {
    final type = await showDialog<ConnectorType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر نوع الموصل'),
        children: [
          for (final t in kConnectorTypes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(t.description,
                        style: TextStyle(fontSize: 12.5, color: context.pal.text2)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (type == null || !mounted) return;
    final r = await Navigator.push<ConnectorConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectorEditPage(initial: ConnectorConfig(type: type.id, name: type.title)),
      ),
    );
    if (r == null) return;
    _list.add(r);
    await _commit();
  }

  Future<void> _edit(ConnectorConfig c) async {
    final r = await Navigator.push<ConnectorConfig>(
      context,
      MaterialPageRoute(builder: (_) => ConnectorEditPage(initial: c)),
    );
    if (r == null) return;
    final i = _list.indexWhere((e) => e.id == c.id);
    if (i >= 0) _list[i] = r;
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SheetScaffold(
      controller: widget.controller,
      title: 'الموصلات (Connectors)',
      subtitle: 'اربط التطبيق بخدماتك: اقرأ روابط GitHub، وأرسل الإجابات إلى Telegram أو أي Webhook (Zapier / Make / n8n / Slack / Discord).',
      children: [
        for (final c in _list)
          Card(
            elevation: 0,
            color: p.bg,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.border),
            ),
            child: ListTile(
              onTap: () => _edit(c),
              leading: Icon(_iconFor(c.type), color: p.accent),
              title: Text(c.name),
              subtitle: Text(connectorTypeOf(c.type).title,
                  style: TextStyle(color: p.text2, fontSize: 12.5)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: c.enabled,
                    onChanged: (v) {
                      c.enabled = v;
                      _commit();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () {
                      _list.removeWhere((e) => e.id == c.id);
                      _commit();
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('إضافة موصل'),
        ),
      ],
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'github':
        return Icons.code;
      case 'telegram':
        return Icons.send_outlined;
      case 'webhook':
        return Icons.webhook_outlined;
      default:
        return Icons.api_outlined;
    }
  }
}

class ConnectorEditPage extends StatefulWidget {
  final ConnectorConfig initial;
  const ConnectorEditPage({super.key, required this.initial});

  @override
  State<ConnectorEditPage> createState() => _ConnectorEditPageState();
}

class _ConnectorEditPageState extends State<ConnectorEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _extra;
  bool _testing = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c.name);
    _url = TextEditingController(text: c.url);
    _token = TextEditingController(text: c.token);
    _extra = TextEditingController(text: c.extra);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _extra.dispose();
    super.dispose();
  }

  ConnectorConfig _build() => ConnectorConfig(
        id: widget.initial.id,
        type: widget.initial.type,
        name: Sanitize.text(_name.text).isEmpty
            ? connectorTypeOf(widget.initial.type).title
            : Sanitize.text(_name.text),
        url: Sanitize.url(_url.text),
        token: Sanitize.key(_token.text),
        extra: Sanitize.text(_extra.text),
        enabled: widget.initial.enabled,
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final err = await ConnectorActions.test(_build());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = err == null ? '✅ يعمل' : '❌ $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = connectorTypeOf(widget.initial.type);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.title, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(t.description, style: TextStyle(color: p.text2, height: 1.45)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.badge_outlined)),
          ),
          if (t.urlLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            LtrField(
              controller: _url,
              label: t.urlLabel,
              icon: Icons.link,
              keyboardType: TextInputType.url,
            ),
          ],
          if (t.tokenLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            LtrField(controller: _token, label: t.tokenLabel, icon: Icons.key_outlined, secret: true),
          ],
          if (t.extraLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            LtrField(controller: _extra, label: t.extraLabel, icon: Icons.tag),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('اختبار'),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_result!,
                  style: TextStyle(color: _result!.startsWith('✅') ? Colors.green.shade700 : p.danger)),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════ الإعدادات ═════════════════════════════

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onChanged;
  final Future<void> Function() onClearHistory;
  final Future<void> Function() onOpenProviders;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClearHistory,
    required this.onOpenProviders,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _s;
  late final TextEditingController _name;
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _name = TextEditingController(text: _s.userName);
    _prompt = TextEditingController(text: _s.systemPrompt);
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _apply() {
    setState(() {});
    widget.onChanged(_s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'اسمك (يظهر في الترحيب)',
              prefixIcon: Icon(Icons.person_outline),
            ),
            onChanged: (v) {
              _s.userName = v.trim();
              widget.onChanged(_s);
            },
          ),
          const SizedBox(height: 18),
          Text('المظهر', style: TextStyle(color: p.text2, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('النظام')),
              ButtonSegment(value: 'light', label: Text('فاتح')),
              ButtonSegment(value: 'dark', label: Text('داكن')),
            ],
            selected: {_s.themeMode},
            onSelectionChanged: (v) {
              _s.themeMode = v.first;
              _apply();
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: const Text('المزودون والمفاتيح'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => widget.onOpenProviders(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الانتقال التلقائي بين المزودين'),
            subtitle: const Text('عند فشل مزود أو تجاوز حدّه ينتقل للتالي'),
            value: _s.autoSwitch,
            onChanged: (v) {
              _s.autoSwitch = v;
              _apply();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('التعرف التلقائي على السؤال'),
            subtitle: const Text('صورة، فيديو، مالية، تواصل اجتماعي، مشكلة، كود…'),
            value: _s.autoIntent,
            onChanged: (v) {
              _s.autoIntent = v;
              _apply();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('عرض الإجابة أثناء كتابتها (Streaming)'),
            value: _s.streamEnabled,
            onChanged: (v) {
              _s.streamEnabled = v;
              _apply();
            },
          ),
          const SizedBox(height: 8),
          Text('أقصى نص يُقرأ من كل ملف: ${_s.maxFileChars} حرف',
              style: TextStyle(color: p.text2, fontSize: 13)),
          Slider(
            min: 5000,
            max: 100000,
            divisions: 19,
            value: _s.maxFileChars.clamp(5000, 100000).toDouble(),
            onChanged: (v) {
              _s.maxFileChars = v.round();
              _apply();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'موجّه النظام (System Prompt)',
              suffixIcon: IconButton(
                tooltip: 'استعادة الافتراضي',
                icon: const Icon(Icons.restore),
                onPressed: () {
                  _prompt.text = AppSettings.defaultSystemPrompt;
                  _s.systemPrompt = AppSettings.defaultSystemPrompt;
                  _apply();
                },
              ),
            ),
            onChanged: (v) {
              _s.systemPrompt = v.trim().isEmpty ? AppSettings.defaultSystemPrompt : v;
              widget.onChanged(_s);
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: p.danger),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('مسح كل المحادثات'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('مسح المحادثات'),
                  content: const Text('سيتم حذف كل المحادثات المحفوظة نهائياً.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
                  ],
                ),
              );
              if (ok == true) await widget.onClearHistory();
            },
          ),
        ],
      ),
    );
  }
}
