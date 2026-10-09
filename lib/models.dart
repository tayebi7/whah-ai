import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();
String newId() => _uuid.v4();

// ───────────────────────────── المزودون ─────────────────────────────

/// إعداد مزود واحد. يُحفظ فوراً في التخزين المحلي عند الإضافة أو التعديل.
class ProviderConfig {
  String id;
  String name;
  String endpoint;
  String apiKey;
  String model;
  String visionModel;
  String imageModel;
  String videoModel;

  /// auto | openai | anthropic
  String format;
  bool enabled;
  bool needsKey;

  ProviderConfig({
    String? id,
    required this.name,
    required this.endpoint,
    this.apiKey = '',
    this.model = '',
    this.visionModel = '',
    this.imageModel = '',
    this.videoModel = '',
    this.format = 'auto',
    this.enabled = true,
    this.needsKey = true,
  }) : id = id ?? newId();

  /// جاهز للاستخدام: مفعّل + له عنوان + (مفتاح إن كان مطلوباً)
  bool get usable =>
      enabled &&
      endpoint.trim().isNotEmpty &&
      (!needsKey || apiKey.trim().isNotEmpty);

  ProviderConfig copy() => ProviderConfig(
        id: id,
        name: name,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        visionModel: visionModel,
        imageModel: imageModel,
        videoModel: videoModel,
        format: format,
        enabled: enabled,
        needsKey: needsKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'visionModel': visionModel,
        'imageModel': imageModel,
        'videoModel': videoModel,
        'format': format,
        'enabled': enabled,
        'needsKey': needsKey,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> j) => ProviderConfig(
        id: j['id']?.toString(),
        name: j['name']?.toString() ?? '',
        endpoint: j['endpoint']?.toString() ?? '',
        apiKey: j['apiKey']?.toString() ?? '',
        model: j['model']?.toString() ?? '',
        visionModel: j['visionModel']?.toString() ?? '',
        imageModel: j['imageModel']?.toString() ?? '',
        videoModel: j['videoModel']?.toString() ?? '',
        format: j['format']?.toString() ?? 'auto',
        enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
        needsKey: j['needsKey'] is bool ? j['needsKey'] as bool : true,
      );
}

/// قالب جاهز يملأ النموذج (المفتاح يبقى فارغاً دائماً).
class ProviderPreset {
  final String name;
  final String endpoint;
  final String model;
  final String visionModel;
  final String imageModel;
  final String videoModel;
  final String format;
  final bool needsKey;

  const ProviderPreset({
    required this.name,
    required this.endpoint,
    required this.model,
    this.visionModel = '',
    this.imageModel = '',
    this.videoModel = '',
    this.format = 'auto',
    this.needsKey = true,
  });

  ProviderConfig toConfig() => ProviderConfig(
        name: name,
        endpoint: endpoint,
        model: model,
        visionModel: visionModel,
        imageModel: imageModel,
        videoModel: videoModel,
        format: format,
        needsKey: needsKey,
      );
}

const List<ProviderPreset> kProviderPresets = [
  ProviderPreset(
    name: 'Pollinations (مجاني)',
    endpoint: 'https://text.pollinations.ai/openai',
    model: 'openai',
    visionModel: 'openai',
    imageModel: 'flux',
    needsKey: false,
  ),
  ProviderPreset(
    name: 'Groq',
    endpoint: 'https://api.groq.com/openai/v1',
    model: 'llama-3.3-70b-versatile',
    visionModel: 'meta-llama/llama-4-scout-17b-16e-instruct',
  ),
  ProviderPreset(
    name: 'Gemini',
    endpoint: 'https://generativelanguage.googleapis.com/v1beta/openai',
    model: 'gemini-2.5-flash',
    visionModel: 'gemini-2.5-flash',
  ),
  ProviderPreset(
    name: 'OpenRouter',
    endpoint: 'https://openrouter.ai/api/v1',
    model: 'openrouter/free',
    visionModel: 'openrouter/free',
  ),
  ProviderPreset(
    name: 'NVIDIA',
    endpoint: 'https://integrate.api.nvidia.com/v1',
    model: 'meta/llama-3.1-8b-instruct',
    visionModel: 'meta/llama-3.2-11b-vision-instruct',
  ),
  ProviderPreset(
    name: 'Cerebras',
    endpoint: 'https://api.cerebras.ai/v1',
    model: 'llama-3.3-70b',
  ),
  ProviderPreset(
    name: 'Together',
    endpoint: 'https://api.together.xyz/v1',
    model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    visionModel: 'meta-llama/Llama-Vision-Free',
    imageModel: 'black-forest-labs/FLUX.1-schnell',
  ),
  ProviderPreset(
    name: 'OpenAI',
    endpoint: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    visionModel: 'gpt-4o-mini',
    imageModel: 'gpt-image-1',
    videoModel: 'sora-2',
  ),
  ProviderPreset(
    name: 'Anthropic',
    endpoint: 'https://api.anthropic.com/v1',
    model: 'claude-haiku-4-5',
    visionModel: 'claude-haiku-4-5',
    format: 'anthropic',
  ),
  ProviderPreset(
    name: 'DeepSeek',
    endpoint: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  ),
  ProviderPreset(
    name: 'Mistral',
    endpoint: 'https://api.mistral.ai/v1',
    model: 'mistral-small-latest',
    visionModel: 'pixtral-12b-2409',
  ),
];

// ───────────────────────────── الإعدادات ─────────────────────────────

class AppSettings {
  String userName;

  /// 'auto' أو معرّف مزود محدد
  String activeProviderId;

  /// الانتقال تلقائياً للمزود التالي عند الفشل
  bool autoSwitch;

  /// التعرف التلقائي على نوع السؤال
  bool autoIntent;
  bool streamEnabled;
  String systemPrompt;

  /// system | light | dark
  String themeMode;

  /// أقصى عدد أحرف يُقرأ من كل ملف
  int maxFileChars;

  static const String defaultSystemPrompt =
      'أنت مساعد ذكي اسمه WHAH AI. أجب بلغة المستخدم بوضوح ودقة وإيجاز. '
      'إذا أُرفقت صور أو ملفات فهي مرفقة فعلاً في هذه الرسالة فاعتمد عليها '
      'ولا تقل إنك لا تستطيع رؤيتها.';

  AppSettings({
    this.userName = '',
    this.activeProviderId = 'auto',
    this.autoSwitch = true,
    this.autoIntent = true,
    this.streamEnabled = true,
    this.systemPrompt = defaultSystemPrompt,
    this.themeMode = 'system',
    this.maxFileChars = 30000,
  });

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'activeProviderId': activeProviderId,
        'autoSwitch': autoSwitch,
        'autoIntent': autoIntent,
        'streamEnabled': streamEnabled,
        'systemPrompt': systemPrompt,
        'themeMode': themeMode,
        'maxFileChars': maxFileChars,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final mfc = j['maxFileChars'];
    return AppSettings(
      userName: j['userName']?.toString() ?? '',
      activeProviderId: j['activeProviderId']?.toString() ?? 'auto',
      autoSwitch: j['autoSwitch'] is bool ? j['autoSwitch'] as bool : true,
      autoIntent: j['autoIntent'] is bool ? j['autoIntent'] as bool : true,
      streamEnabled:
          j['streamEnabled'] is bool ? j['streamEnabled'] as bool : true,
      systemPrompt: (j['systemPrompt']?.toString() ?? '').trim().isEmpty
          ? defaultSystemPrompt
          : j['systemPrompt'].toString(),
      themeMode: j['themeMode']?.toString() ?? 'system',
      maxFileChars: mfc is int && mfc >= 2000 ? mfc : 30000,
    );
  }
}

// ───────────────────────────── المحادثة ─────────────────────────────

class AttachedFile {
  final String name;
  final String path;
  final int size;

  const AttachedFile({
    required this.name,
    required this.path,
    required this.size,
  });

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'size': size};

  factory AttachedFile.fromJson(Map<String, dynamic> j) => AttachedFile(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        size: j['size'] is int
            ? j['size'] as int
            : int.tryParse(j['size']?.toString() ?? '') ?? 0,
      );

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// ملف وسائط (صورة/فيديو) مولّد أو مُحوَّل ومحفوظ محلياً
class MediaItem {
  final String path;

  /// image | video
  final String kind;
  final String mime;

  const MediaItem({required this.path, required this.kind, required this.mime});

  Map<String, dynamic> toJson() => {'path': path, 'kind': kind, 'mime': mime};

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        path: j['path']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'image',
        mime: j['mime']?.toString() ?? '',
      );
}

class ChatMessage {
  final String id;
  final String role; // user | assistant
  String content;

  /// نص مستخرج من الملفات والروابط (يُرسل للنموذج ولا يُعرض)
  String context;
  final DateTime createdAt;
  final List<AttachedFile> files;
  final List<MediaItem> media;
  String provider;
  String intentLabel;
  bool isError;

  /// حالة مؤقتة تظهر أثناء المعالجة (لا تُحفظ)
  String status;

  ChatMessage({
    String? id,
    required this.role,
    this.content = '',
    this.context = '',
    DateTime? createdAt,
    List<AttachedFile>? files,
    List<MediaItem>? media,
    this.provider = '',
    this.intentLabel = '',
    this.isError = false,
    this.status = '',
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        files = files ?? [],
        media = media ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'context': context,
        'createdAt': createdAt.toIso8601String(),
        'files': files.map((f) => f.toJson()).toList(),
        'media': media.map((m) => m.toJson()).toList(),
        'provider': provider,
        'intentLabel': intentLabel,
        'isError': isError,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final rf = j['files'];
    final rm = j['media'];
    return ChatMessage(
      id: j['id']?.toString(),
      role: j['role']?.toString() ?? 'user',
      content: j['content']?.toString() ?? '',
      context: j['context']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      files: rf is List
          ? rf
              .whereType<Map>()
              .map((e) => AttachedFile.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      media: rm is List
          ? rm
              .whereType<Map>()
              .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      provider: j['provider']?.toString() ?? '',
      intentLabel: j['intentLabel']?.toString() ?? '',
      isError: j['isError'] is bool ? j['isError'] as bool : false,
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
  })  : id = id ?? newId(),
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

  factory ChatHistory.fromJson(Map<String, dynamic> j) {
    final rm = j['messages'];
    return ChatHistory(
      id: j['id']?.toString(),
      title: j['title']?.toString() ?? 'محادثة جديدة',
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      messages: rm is List
          ? rm
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
    );
  }
}

// ───────────────────────────── Skills ─────────────────────────────

class Skill {
  final String id;
  String title;
  String category;

  /// تعليمات تُضاف لموجّه النظام عند تفعيل المهارة
  String instruction;
  final bool builtIn;

  Skill({
    String? id,
    required this.title,
    required this.instruction,
    this.category = 'مخصص',
    this.builtIn = false,
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'instruction': instruction,
      };

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        id: j['id']?.toString(),
        title: j['title']?.toString() ?? '',
        category: j['category']?.toString() ?? 'مخصص',
        instruction: j['instruction']?.toString() ?? '',
      );
}

final List<Skill> kBuiltInSkills = [
  Skill(
    id: 'b-code',
    title: 'كتابة كود',
    category: 'برمجة',
    builtIn: true,
    instruction:
        'اكتب كوداً نظيفاً وقابلاً للتشغيل مع تعليقات مختصرة، واذكر طريقة التشغيل والمتطلبات.',
  ),
  Skill(
    id: 'b-debug',
    title: 'إصلاح أخطاء',
    category: 'برمجة',
    builtIn: true,
    instruction:
        'حلل الخطأ: السبب الجذري، ثم الكود المصحح كاملاً، ثم كيف أتأكد أن المشكلة حُلّت.',
  ),
  Skill(
    id: 'b-review',
    title: 'مراجعة كود',
    category: 'برمجة',
    builtIn: true,
    instruction:
        'راجع الكود من ناحية الأخطاء والأمان والأداء والوضوح، وقدّم تحسينات محددة بالأسطر.',
  ),
  Skill(
    id: 'b-data',
    title: 'تحليل بيانات',
    category: 'بيانات',
    builtIn: true,
    instruction:
        'حلل البيانات: ملخص، إحصاءات رئيسية (احسبها بدقة وبيّن خطوات الحساب)، أنماط، شذوذ، واستنتاجات قابلة للتنفيذ. اعرض الجداول بصيغة Markdown.',
  ),
  Skill(
    id: 'b-finance',
    title: 'محاسب مالي',
    category: 'مالية',
    builtIn: true,
    instruction: kFinanceInstruction,
  ),
  Skill(
    id: 'b-social',
    title: 'خبير سوشيال ميديا',
    category: 'تسويق',
    builtIn: true,
    instruction: kSocialInstruction,
  ),
  Skill(
    id: 'b-problem',
    title: 'محلل مشاكل',
    category: 'تحليل',
    builtIn: true,
    instruction: kProblemInstruction,
  ),
  Skill(
    id: 'b-summary',
    title: 'تلخيص',
    category: 'مستندات',
    builtIn: true,
    instruction:
        'لخّص المحتوى في نقاط واضحة مرتبة حسب الأهمية، ثم خلاصة من سطرين، دون إضافة معلومات من خارج النص.',
  ),
  Skill(
    id: 'b-translate',
    title: 'ترجمة',
    category: 'لغة',
    builtIn: true,
    instruction:
        'ترجم النص بدقة مع الحفاظ على المعنى والنبرة والتنسيق. إن لم تُحدَّد اللغة فترجم العربية للإنجليزية والعكس.',
  ),
  Skill(
    id: 'b-write',
    title: 'تحرير وتدقيق',
    category: 'لغة',
    builtIn: true,
    instruction:
        'صحّح الأخطاء اللغوية والإملائية وحسّن الصياغة بأسلوب احترافي مع الحفاظ على المعنى، ثم اذكر أهم التعديلات.',
  ),
];

// تعليمات الاختصاصات (تُستخدم في Skills وفي التعرف التلقائي)
const String kFinanceInstruction =
    'أنت محاسب ومحلل مالي خبير. عند تحليل فاتورة أو كشف حساب أو جدول مالي:\n'
    '1) استخرج الحقول في جدول Markdown: المورد/العميل، رقم الفاتورة، التاريخ، العملة، البنود (الوصف، الكمية، سعر الوحدة، المجموع)، المجموع الفرعي، الخصم، الضريبة (TVA/VAT) ونسبتها، الإجمالي، طريقة/حالة الدفع.\n'
    '2) أعد حساب كل سطر والمجاميع والضريبة بنفسك وقارنها بالمكتوب، وأشر صراحةً لأي تناقض مع الفرق.\n'
    '3) الأرقام الهندية (٠-٩) تساوي 0-9، والفاصلة قد تكون فاصلاً عشرياً (12,50) أو للآلاف (1,250.00) فاستنتج من السياق وبيّن افتراضك.\n'
    '4) إن كانت معلومة غير واضحة أو مقطوعة فاذكر ذلك ولا تخمّن.\n'
    '5) في الحسابات (ميزانية، أرباح وخسائر، تدفقات، قيود مدين/دائن) أظهر خطوات الحساب بالتفصيل.\n'
    '6) اختم بملاحظات: أخطاء محتملة، مخاطر، وما يجب مراجعته مع محاسب مرخّص عند الحاجة.';

const String kSocialInstruction =
    'أنت خبير وسائل التواصل الاجتماعي (فيسبوك، إنستغرام، تيك توك، يوتيوب، X، لينكدإن، سناب، تيليغرام).\n'
    '- حدّد المنصة والجمهور والغرض من المحتوى.\n'
    '- عند تحليل منشور/حساب/فيديو: الفكرة والخطاف (Hook)، النبرة، جودة النص والصورة، الهاشتاقات، نقاط القوة والضعف، توصيات لرفع التفاعل.\n'
    '- عند الكتابة: أنتج نسخاً مناسبة لحدود وأسلوب كل منصة، مع هاشتاقات ودعوة لاتخاذ إجراء، ويمكنك اقتراح جدول نشر.\n'
    '- اعتمد فقط على ما هو ظاهر في النص/الصور/بيانات الرابط المرفقة. إذا لم تتوفر بيانات (مثل الإحصاءات أو محتوى خلف تسجيل دخول) فقل ذلك بوضوح ولا تختلق أرقاماً.';

const String kProblemInstruction =
    'أنت محلل مشاكل ومستكشف أعطال محترف. قدّم الجواب بهذا الترتيب:\n'
    '1) **ملخص المشكلة** في سطرين.\n'
    '2) **الأعراض والأدلة** من النص/الملف/الصورة المرفقة (اقتبس السطر أو الرسالة المهمة).\n'
    '3) **الأسباب المحتملة** مرتبة من الأرجح للأقل ترجيحاً مع سبب كل ترتيب.\n'
    '4) **خطوات التشخيص** للتأكد من السبب الحقيقي.\n'
    '5) **الحل** خطوة بخطوة (والكود/الأوامر المصححة كاملة إن لزم).\n'
    '6) **كيف أمنع تكرارها**.\n'
    'إن كانت المعلومات ناقصة فاسأل أقل عدد من الأسئلة اللازمة بعد أن تقدّم أفضل تحليل ممكن.';

// ───────────────────────────── Connectors ─────────────────────────────

/// نوع الموصل: github | telegram | webhook | rest
class ConnectorConfig {
  final String id;
  String type;
  String name;

  /// github: (اختياري) | webhook: رابط الـ Webhook | rest: الرابط الأساسي
  String url;

  /// github: Personal Access Token | telegram: Bot Token | rest: Bearer token
  String token;

  /// telegram: Chat ID
  String extra;
  bool enabled;

  ConnectorConfig({
    String? id,
    required this.type,
    required this.name,
    this.url = '',
    this.token = '',
    this.extra = '',
    this.enabled = true,
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'url': url,
        'token': token,
        'extra': extra,
        'enabled': enabled,
      };

  factory ConnectorConfig.fromJson(Map<String, dynamic> j) => ConnectorConfig(
        id: j['id']?.toString(),
        type: j['type']?.toString() ?? 'rest',
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        token: j['token']?.toString() ?? '',
        extra: j['extra']?.toString() ?? '',
        enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
      );
}
