import 'models.dart';

enum Intent {
  chat,
  imageGen,
  videoGen,
  vision,
  finance,
  social,
  problem,
  code,
  translate,
  summarize,
  data,
}

class IntentResult {
  final Intent intent;

  /// هل توجد صور/لقطات فيديو يجب إرسالها لنموذج الرؤية
  final bool needsVision;
  final String label;

  /// تعليمات تُضاف لموجّه النظام لهذا السؤال
  final String addon;

  const IntentResult(this.intent,
      {this.needsVision = false, this.label = '', this.addon = ''});

  bool get isGeneration =>
      intent == Intent.imageGen || intent == Intent.videoGen;
}

/// يتعرف تلقائياً على نوع السؤال (قواعد سريعة، بدون استدعاء نموذج) من النص
/// والمرفقات: توليد صورة/فيديو، تحليل صورة، مالية، تواصل اجتماعي، مشكلة، كود...
class IntentDetector {
  static String normalize(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp('[ً-ٰٟـ]'), '');
    t = t.replaceAll(RegExp('[أإآ]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ة', 'ه');
    return t;
  }

  static RegExp _compile(List<String> words) {
    final parts = words.map((w) {
      final n = RegExp.escape(normalize(w));
      final latin = RegExp(r'^[a-z0-9]').hasMatch(normalize(w));
      return latin ? '\\b$n' : n;
    }).join('|');
    return RegExp(parts);
  }

  static int _count(RegExp r, String t) => r.allMatches(t).length;

  // ─── توليد الوسائط ───
  static final RegExp _genVerb = _compile([
    'ولد', 'انشئ', 'انشي', 'اصنع', 'صمم', 'ارسم', 'اعمل', 'اريد صوره',
    'اريد فيديو', 'generate', 'create', 'make', 'draw', 'design', 'render',
    'imagine', 'produce', 'animate', 'حرك', 'اعطني صوره', 'اعطني فيديو',
  ]);
  static final RegExp _strongVerb = _compile([
    'ولد', 'انشئ', 'انشي', 'ارسم', 'generate', 'create', 'draw', 'imagine',
    'render', 'animate', 'صمم',
  ]);
  static final RegExp _imgNoun = _compile([
    'صوره', 'صور ', 'لوحه', 'رسمه', 'شعار', 'لوغو', 'بوستر', 'ملصق', 'غلاف',
    'image', 'picture', 'photo', 'illustration', 'logo', 'poster', 'wallpaper',
    'artwork', 'portrait', 'drawing', 'icon',
  ]);
  static final RegExp _drawVerb = _compile(['ارسم', 'draw']);
  static final RegExp _vidNoun = _compile([
    'فيديو', 'فديو', 'مقطع متحرك', 'انيميشن', 'رسوم متحركه', 'video', 'clip',
    'animation', 'reel',
  ]);
  static final RegExp _textOnly = _compile([
    'برومبت', 'prompt', 'سيناريو', 'script', 'اشرح', 'explain', 'حلل',
    'analy', 'describe', 'صف لي', 'كود', 'code', 'لخص',
  ]);
  static final RegExp _describeMedia =
      RegExp('وصف\\s+(هذه|هذا|ال)');

  // ─── المجالات ───
  static final RegExp _financeStrong = _compile([
    'فاتور', 'فواتير', 'ميزاني', 'محاسب', 'ضريب', 'ضرائب', 'مصاريف', 'مصروف',
    'ايرادات', 'ارباح', 'خسائر', 'رواتب', 'مدين', 'دائن', 'كشف حساب',
    'دفتر اليوميه', 'قيد محاسبي', 'ايصال', 'invoice', 'receipt', 'vat', 'tva',
    'balance sheet', 'ledger', 'accounting', 'payroll', 'cash flow', 'p&l',
    'facture', 'bilan', 'comptab', 'devis', 'reçu', 'recu',
  ]);
  static final RegExp _financeWeak = _compile([
    'حسابات', 'تكلف', 'مبلغ', 'سعر', 'اجمالي', 'المجموع', 'دينار', 'دج',
    'dzd', 'ريال', 'درهم', 'جنيه', 'دولار', 'يورو', 'ربح', 'خساره', 'ديون',
    'قرض', 'ضمان', 'bill', 'tax', 'expense', 'revenue', 'profit', 'loss',
    'budget', 'amount', 'total', 'debit', 'credit', 'montant', 'prix',
    'usd', 'eur', r'$', '€',
  ]);
  static final RegExp _socialStrong = _compile([
    'facebook', 'فيسبوك', 'فيس بوك', 'instagram', 'انستغرام', 'انستجرام',
    'انستا', 'tiktok', 'تيك توك', 'تيكتوك', 'youtube', 'يوتيوب', 'twitter',
    'تويتر', 'x.com', 'linkedin', 'لينكد', 'snapchat', 'سناب', 'telegram',
    'تيليجرام', 'تيليغرام', 'whatsapp', 'واتساب', 'threads', 'pinterest',
    'reels', 'ريلز', 'هاشتاق', 'hashtag', 'وسائل التواصل', 'سوشيال',
    'social media', 'ستوري', 'influencer', 'مؤثر', 'unfollow', 'instagr',
  ]);
  static final RegExp _socialWeak = _compile([
    'منشور', 'بوست', 'caption', 'محتوى', 'تفاعل', 'متابع', 'followers',
    'engagement', 'تعليقات', 'comments', 'حسابي', 'صفحتي', 'قناتي', 'ترند',
    'trend', 'viral', 'فيرال',
  ]);
  static final RegExp _problemStrong = _compile([
    'مشكل', 'لا يعمل', 'لا تعمل', 'ما يشتغل', 'لا يشتغل', 'تعطل', 'عطل ', 'خطا ', 'خطا:', 'اخطاء',
    'استثناء', 'error', 'exception', 'traceback', 'stack trace', 'crash',
    'bug', 'failed', 'fails', 'not working', "doesn't work", 'troubleshoot',
    'problem', 'issue', 'تحليل المشكل', 'حل المشكل', 'يتوقف', 'يعلق', 'يهنج',
    'لماذا لا', 'fatal', 'cannot', "can't", 'unable to', 'null check',
  ]);
  static final RegExp _problemWeak = _compile([
    'fix', 'اصلح', 'صلح', 'حل ', 'سبب', 'لماذا', 'why', 'غير صحيح', 'wrong',
    'تحذير', 'warning', 'timeout', 'مهله',
  ]);
  static final RegExp _codeStrong = _compile([
    '```', 'function ', 'def ', 'class ', 'import ', 'كود', 'برمج', 'سكريبت',
    'script', 'flutter', 'dart', 'python', 'javascript', 'typescript', 'java ',
    'kotlin', 'html', 'css', 'sql', 'regex', 'api', 'github', 'git ',
    'compile', 'build', 'دالة', 'متغير', 'خوارزمي', 'algorithm',
  ]);
  static final RegExp _translate = _compile(['ترجم', 'ترجمه', 'translate', 'traduire', 'traduis']);
  static final RegExp _summarize = _compile(['لخص', 'تلخيص', 'summar', 'resume ', 'ملخص']);
  static final RegExp _dataWords = _compile([
    'تحليل بيانات', 'احصاء', 'جدول', 'csv', 'xlsx', 'excel', 'اكسل', 'statistic',
    'dataset', 'pivot', 'متوسط', 'المجموع', 'average', 'median', 'sum of',
  ]);

  static IntentResult detect(
    String text, {
    bool hasImages = false,
    bool hasVideo = false,
    List<String> fileExts = const [],
  }) {
    final t = '${normalize(text)} ';
    final hasMedia = hasImages || hasVideo;

    // 1) توليد صورة/فيديو
    final wantsGen = _genVerb.hasMatch(t) &&
        !_textOnly.hasMatch(t) &&
        !_describeMedia.hasMatch(t) &&
        !(hasMedia && !_strongVerb.hasMatch(t));
    if (wantsGen) {
      if (_vidNoun.hasMatch(t)) {
        return const IntentResult(Intent.videoGen,
            label: 'توليد فيديو');
      }
      if (_imgNoun.hasMatch(t) || _drawVerb.hasMatch(t)) {
        return const IntentResult(Intent.imageGen,
            label: 'توليد صورة');
      }
    }

    // 2) تقييم المجالات
    final scores = <Intent, int>{
      Intent.finance: _count(_financeStrong, t) * 3 + _count(_financeWeak, t),
      Intent.social: _count(_socialStrong, t) * 3 + _count(_socialWeak, t),
      Intent.problem: _count(_problemStrong, t) * 3 + _count(_problemWeak, t),
      Intent.code: _count(_codeStrong, t) * 2,
      Intent.translate: _count(_translate, t) * 4,
      Intent.summarize: _count(_summarize, t) * 3,
      Intent.data: _count(_dataWords, t) * 2,
    };
    // مرفقات جداول → بيانات
    if (fileExts.any((e) => e == 'xlsx' || e == 'xls' || e == 'csv' || e == 'ods')) {
      scores[Intent.data] = (scores[Intent.data] ?? 0) + 3;
    }
    // الأخطاء + كود → مشكلة (تغطي إصلاح الكود)
    if ((scores[Intent.problem] ?? 0) >= 3 && (scores[Intent.code] ?? 0) > 0) {
      scores[Intent.problem] = (scores[Intent.problem] ?? 0) + 2;
    }
    // الفواتير مع جداول → مالية
    if ((scores[Intent.finance] ?? 0) >= 3 && (scores[Intent.data] ?? 0) > 0) {
      scores[Intent.finance] = (scores[Intent.finance] ?? 0) + 2;
    }

    const order = [
      Intent.finance,
      Intent.social,
      Intent.problem,
      Intent.translate,
      Intent.summarize,
      Intent.code,
      Intent.data,
    ];
    var best = Intent.chat;
    var bestScore = 0;
    for (final i in order) {
      final s = scores[i] ?? 0;
      if (s > bestScore) {
        best = i;
        bestScore = s;
      }
    }
    final threshold = best == Intent.code || best == Intent.data ? 2 : 3;
    if (bestScore < threshold) best = Intent.chat;

    if (best == Intent.chat && hasMedia) {
      return IntentResult(Intent.vision,
          needsVision: true,
          label: hasVideo ? 'تحليل فيديو' : 'تحليل صورة',
          addon: _visionAddon(hasVideo));
    }
    return IntentResult(
      best,
      needsVision: hasMedia,
      label: _label(best),
      addon: _addon(best, hasVideo: hasVideo, hasImages: hasImages),
    );
  }

  static String _label(Intent i) {
    switch (i) {
      case Intent.finance:
        return 'تحليل مالي';
      case Intent.social:
        return 'وسائل التواصل';
      case Intent.problem:
        return 'تحليل مشكلة';
      case Intent.code:
        return 'برمجة';
      case Intent.translate:
        return 'ترجمة';
      case Intent.summarize:
        return 'تلخيص';
      case Intent.data:
        return 'تحليل بيانات';
      case Intent.vision:
        return 'تحليل صورة';
      case Intent.imageGen:
        return 'توليد صورة';
      case Intent.videoGen:
        return 'توليد فيديو';
      case Intent.chat:
        return '';
    }
  }

  static String _visionAddon(bool video) => video
      ? 'المرفقات لقطات مأخوذة بالترتيب الزمني من فيديو. صف ما يحدث عبر الزمن، '
          'واقرأ أي نص ظاهر، وحدد الأشخاص/الأشياء/الأحداث المهمة. الصوت غير متاح لك.'
      : 'حلل الصور المرفقة بدقة: صف المحتوى، واقرأ أي نص ظاهر فيها (OCR) بلغته الأصلية، '
          'واستخرج الأرقام والجداول كما هي، ثم أجب عن سؤال المستخدم تحديداً.';

  static String _addon(Intent i, {bool hasVideo = false, bool hasImages = false}) {
    final media = (hasImages || hasVideo) ? '\n${_visionAddon(hasVideo)}' : '';
    switch (i) {
      case Intent.finance:
        return kFinanceInstruction + media;
      case Intent.social:
        return kSocialInstruction + media;
      case Intent.problem:
        return kProblemInstruction + media;
      case Intent.code:
        return 'أنت مهندس برمجيات خبير. قدّم كوداً كاملاً وصحيحاً وجاهزاً للتشغيل في كتل Markdown مع اسم اللغة، '
            'واشرح باختصار ما يلزم فقط.$media';
      case Intent.translate:
        return 'ترجم بدقة مع الحفاظ على المعنى والنبرة والتنسيق، وأعد الترجمة فقط دون مقدمات '
            'إلا إذا كان هناك غموض.$media';
      case Intent.summarize:
        return 'لخّص بنقاط واضحة مرتبة حسب الأهمية ثم خلاصة قصيرة، دون إضافة معلومات من خارج النص.$media';
      case Intent.data:
        return 'حلل البيانات بدقة: احسب الإحصاءات فعلياً وبيّن خطوات الحساب، اعرض الجداول بصيغة Markdown، '
            'وأشر إلى القيم الشاذة أو الناقصة، ثم قدّم استنتاجات قابلة للتنفيذ.$media';
      case Intent.vision:
        return _visionAddon(hasVideo);
      case Intent.imageGen:
      case Intent.videoGen:
      case Intent.chat:
        return media.trim();
    }
  }
}
