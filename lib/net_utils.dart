import 'dart:convert';
import 'dart:typed_data';

// ───────────────────────────── تنظيف المدخلات ─────────────────────────────

/// ينظّف ما يلصقه المستخدم: مسافات خفية، علامات اقتباس، "Bearer"، أسطر جديدة...
class Sanitize {
  static final RegExp _invisible =
      RegExp('[​-‏‪-‮⁠﻿ ]');
  static const String _quotes = '"\'`“”‘’«»';

  /// نص عادي (اسم، نموذج...): يزيل الأحرف الخفية والمسافات الزائدة
  static String text(String s) =>
      s.replaceAll(_invisible, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// اسم نموذج: بلا مسافات إطلاقاً
  static String model(String s) {
    var v = s.replaceAll(_invisible, '').replaceAll(RegExp(r'\s+'), '');
    v = _stripQuotes(v);
    return v;
  }

  static String _stripQuotes(String s) {
    var v = s;
    while (v.isNotEmpty && _quotes.contains(v[0])) {
      v = v.substring(1);
    }
    while (v.isNotEmpty && (_quotes.contains(v[v.length - 1]) || v.endsWith(','))) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// مفتاح API: يزيل "Bearer " و"Authorization:" والمسافات والأسطر والرموز غير ASCII
  /// (وجودها كان يُسقط الطلب بخطأ في رؤوس HTTP).
  static String key(String raw) {
    var s = raw.replaceAll(_invisible, '').trim();
    s = _stripQuotes(s);
    s = s.replaceFirst(
        RegExp(r'^authorization\s*[:=]\s*', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^bearer\s+', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+'), '');
    s = _stripQuotes(s);
    s = s.replaceAll(RegExp(r'[^\x21-\x7E]'), '');
    return s;
  }

  /// رابط: يزيل الفراغات والاقتباس والتكرار ويضيف المخطط (https/http)
  static String url(String raw) {
    var s = raw.replaceAll(_invisible, '').replaceAll(RegExp(r'\s+'), '');
    s = _stripQuotes(s);
    while (s.endsWith(';') || s.endsWith(')') || s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return '';
    // "https://https://x.com" أو نص ملصوق مرتين → خذ آخر مخطط
    final all = RegExp(r'https?://', caseSensitive: false).allMatches(s).toList();
    if (all.length > 1) s = s.substring(all.last.start);
    // أزل المراسي والاستعلام
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    if (!s.contains('://')) {
      if (s.startsWith('//')) s = s.substring(2);
      final hostPart = s.split('/').first.split(':').first.toLowerCase();
      final local = hostPart == 'localhost' ||
          RegExp(r'^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
              .hasMatch(hostPart) ||
          hostPart.endsWith('.local');
      s = '${local ? 'http' : 'https'}://$s';
    }
    return s;
  }

  /// يحاول فهم JSON ملصوق في خانة العنوان (مثل {"base_url": "...", "api_key": "..."})
  /// ويعيد حقولاً مستخرجة أو null إن لم يكن JSON.
  static Map<String, String>? parseProviderJson(String raw) {
    final t = raw.trim();
    if (!t.startsWith('{')) return null;
    try {
      final j = jsonDecode(t);
      if (j is! Map) return null;
      String pick(List<String> names) {
        for (final n in names) {
          for (final k in j.keys) {
            if (k.toString().toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '') ==
                n) {
              final v = j[k];
              if (v is String && v.trim().isNotEmpty) return v.trim();
            }
          }
        }
        return '';
      }

      final out = <String, String>{
        'endpoint':
            pick(['baseurl', 'endpoint', 'url', 'apiurl', 'apibase', 'host']),
        'apiKey': pick(['apikey', 'key', 'token', 'secret', 'accesstoken']),
        'model': pick(['model', 'modelname', 'modelid']),
        'name': pick(['name', 'provider', 'title']),
      };
      if (out.values.every((v) => v.isEmpty)) return null;
      return out;
    } catch (_) {
      return null;
    }
  }
}

// ───────────────────────────── كشف نوع الملف من محتواه ─────────────────────────────

class DetectedType {
  final String mime;
  final String ext;
  const DetectedType(this.mime, this.ext);

  /// image | video | audio | pdf | zip | other
  String get kind {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime == 'application/pdf') return 'pdf';
    if (mime == 'application/zip') return 'zip';
    return 'other';
  }
}

bool _asciiAt(Uint8List b, int off, String s) {
  if (b.length < off + s.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[off + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

/// يكشف النوع الحقيقي من البايتات الأولى (لا يعتمد على الامتداد).
DetectedType detectType(Uint8List b) {
  if (b.length >= 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return const DetectedType('image/png', 'png');
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return const DetectedType('image/jpeg', 'jpg');
  }
  if (_asciiAt(b, 0, 'GIF8')) return const DetectedType('image/gif', 'gif');
  if (_asciiAt(b, 0, 'RIFF') && _asciiAt(b, 8, 'WEBP')) {
    return const DetectedType('image/webp', 'webp');
  }
  if (_asciiAt(b, 0, 'RIFF') && _asciiAt(b, 8, 'AVI ')) {
    return const DetectedType('video/x-msvideo', 'avi');
  }
  if (_asciiAt(b, 0, 'BM') &&
      b.length > 30 &&
      b[6] == 0 &&
      b[7] == 0 &&
      b[8] == 0 &&
      b[9] == 0 &&
      const [12, 40, 52, 56, 64, 108, 124].contains(b[14]) &&
      b[15] == 0) {
    return const DetectedType('image/bmp', 'bmp');
  }
  if (_asciiAt(b, 4, 'ftyp')) {
    final brand = b.length >= 12
        ? String.fromCharCodes(b.sublist(8, 12)).toLowerCase()
        : '';
    if (brand.startsWith('hei') ||
        brand.startsWith('hev') ||
        brand == 'mif1' ||
        brand == 'msf1') {
      return const DetectedType('image/heic', 'heic');
    }
    if (brand == 'avif') return const DetectedType('image/avif', 'avif');
    if (brand.startsWith('qt')) {
      return const DetectedType('video/quicktime', 'mov');
    }
    if (brand.startsWith('3g')) return const DetectedType('video/3gpp', '3gp');
    return const DetectedType('video/mp4', 'mp4');
  }
  if (b.length >= 4 &&
      b[0] == 0x1A &&
      b[1] == 0x45 &&
      b[2] == 0xDF &&
      b[3] == 0xA3) {
    final head = String.fromCharCodes(
        b.sublist(0, b.length < 64 ? b.length : 64).where((c) => c < 128));
    if (head.contains('webm')) return const DetectedType('video/webm', 'webm');
    return const DetectedType('video/x-matroska', 'mkv');
  }
  if (_asciiAt(b, 0, '%PDF')) {
    return const DetectedType('application/pdf', 'pdf');
  }
  if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4) {
    return const DetectedType('application/zip', 'zip');
  }
  if (_asciiAt(b, 0, 'OggS')) return const DetectedType('audio/ogg', 'ogg');
  if (_asciiAt(b, 0, 'ID3')) return const DetectedType('audio/mpeg', 'mp3');
  return const DetectedType('application/octet-stream', 'bin');
}

// ───────────────────────────── العناوين ─────────────────────────────

/// يحوّل أي عنوان يلصقه المستخدم إلى عناوين REST صحيحة.
/// يقبل: بدون https، مع /chat/completions، مع /v1، مع .json، مكرراً، إلخ.
class ApiEndpoints {
  ApiEndpoints._({
    required this.base,
    required this.format,
    required this.chatUrl,
    required this.alternates,
    required this.host,
    this.error,
  });

  factory ApiEndpoints._invalid(String message) => ApiEndpoints._(
        base: '',
        format: 'openai',
        chatUrl: '',
        alternates: const [],
        host: '',
        error: message,
      );

  final String base;
  final String format; // openai | anthropic
  final String chatUrl;
  final List<String> alternates;
  final String host;
  final String? error;

  List<String> get chatCandidates => [chatUrl, ...alternates];
  String get imagesUrl => '$base/images/generations';
  String get videosUrl => '$base/videos';
  String get modelsUrl => '$base/models';
  bool get isPollinations => host.endsWith('pollinations.ai');

  static final RegExp _versionSeg = RegExp(r'^v\d+([a-z]+\d*)?$');
  static final RegExp _fileSeg =
      RegExp(r'\.(json|html?|txt|php|xml|yaml|yml)$');
  static const Set<String> _tailWords = {
    'completions',
    'responses',
    'messages',
    'models',
    'embeddings',
    'chat',
    'images',
    'generations',
    'videos',
    'audio',
  };

  static ApiEndpoints parse(String raw, {String format = 'auto'}) {
    final s = Sanitize.url(raw);
    if (s.isEmpty) return ApiEndpoints._invalid('لم يتم إدخال عنوان API.');
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      return ApiEndpoints._invalid('عنوان API غير صالح: $s');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return ApiEndpoints._invalid('العنوان يجب أن يبدأ بـ https:// أو http://');
    }
    final host = uri.host.toLowerCase();
    final origin =
        '$scheme://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    var segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();

    // مزودون لهم عنوان ثابت
    if (host.endsWith('pollinations.ai')) {
      return ApiEndpoints._(
        base: 'https://text.pollinations.ai',
        format: 'openai',
        chatUrl: 'https://text.pollinations.ai/openai',
        alternates: const [],
        host: host,
      );
    }
    if (host == 'generativelanguage.googleapis.com') {
      segs = ['v1beta', 'openai'];
    }
    if (uri.hasPort && uri.port == 11434 && segs.isNotEmpty && segs.first == 'api') {
      segs = ['v1']; // Ollama
    }

    // أزل الذيل: .json / chat/completions / models ...
    var changed = true;
    while (changed && segs.isNotEmpty) {
      changed = false;
      final last = segs.last.toLowerCase();
      if (_fileSeg.hasMatch(last)) {
        segs = segs.sublist(0, segs.length - 1);
        changed = true;
      } else if (_tailWords.contains(last)) {
        segs = segs.sublist(0, segs.length - 1);
        changed = true;
      }
    }

    var fmt = format;
    if (fmt == 'auto') {
      fmt = host.contains('anthropic.com') ? 'anthropic' : 'openai';
    }

    // تأكد من وجود رقم إصدار (v1 ...). أضفه إن لم يوجد وجرّب بدونه عند الفشل
    final hasVersion = segs.any((e) => _versionSeg.hasMatch(e.toLowerCase()));
    final alternates = <String>[];
    final tail = fmt == 'anthropic' ? '/messages' : '/chat/completions';
    final baseNoVersion = segs.isEmpty ? origin : '$origin/${segs.join('/')}';
    var base = baseNoVersion;
    if (!hasVersion) {
      base = '$baseNoVersion/v1';
      alternates.add('$baseNoVersion$tail');
    }
    return ApiEndpoints._(
      base: base,
      format: fmt,
      chatUrl: '$base$tail',
      alternates: alternates,
      host: host,
    );
  }
}

// ───────────────────────────── قراءة الاستجابات ─────────────────────────────

class ResponseParser {
  /// يستخرج النص من أي استجابة: OpenAI / Anthropic / Gemini / Ollama / SSE / NDJSON / نص خام.
  /// لا يرمي أخطاء أبداً.
  static String extractText(String body) {
    final t = body.trim();
    if (t.isEmpty) return '';
    try {
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return textFromJson(jsonDecode(t));
        } catch (_) {
          // قد يكون NDJSON → يُعالج أدناه
        }
      }
      if (t.contains('data:') || t.startsWith('{')) {
        final out = StringBuffer();
        for (final line in const LineSplitter().convert(t)) {
          var v = line.trim();
          if (v.isEmpty || v.startsWith(':') || v.startsWith('event:')) continue;
          if (v.startsWith('data:')) v = v.substring(5).trim();
          if (v == '[DONE]' || v.isEmpty) continue;
          try {
            out.write(deltaFromJson(jsonDecode(v)));
          } catch (_) {}
        }
        if (out.isNotEmpty) return out.toString();
      }
    } catch (_) {}
    if (t.startsWith('{') || t.startsWith('[')) return '';
    return t;
  }

  static String _join(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final p in content) {
        if (p is String) {
          buf.write(p);
        } else if (p is Map) {
          final tx = p['text'];
          if (tx is String) buf.write(tx);
        }
      }
      return buf.toString();
    }
    return '';
  }

  static String textFromJson(dynamic j) {
    if (j is List) return j.map(textFromJson).join();
    if (j is! Map) return '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final c = choices.first as Map;
      final m = c['message'];
      if (m is Map) {
        final s = _join(m['content']);
        if (s.isNotEmpty) return s;
      }
      final d = c['delta'];
      if (d is Map) {
        final s = _join(d['content']);
        if (s.isNotEmpty) return s;
      }
      if (c['text'] is String) return c['text'] as String;
    }
    // Anthropic
    final content = j['content'];
    if (content is List || content is String) {
      final s = _join(content);
      if (s.isNotEmpty) return s;
    }
    // Gemini الأصلي
    final cands = j['candidates'];
    if (cands is List && cands.isNotEmpty && cands.first is Map) {
      final parts = ((cands.first as Map)['content'] as Map?)?['parts'];
      final s = _join(parts);
      if (s.isNotEmpty) return s;
    }
    // Ollama
    final msg = j['message'];
    if (msg is Map) {
      final s = _join(msg['content']);
      if (s.isNotEmpty) return s;
    }
    for (final k in ['response', 'output_text', 'text', 'result', 'answer']) {
      if (j[k] is String && (j[k] as String).isNotEmpty) return j[k] as String;
    }
    final out = j['output'];
    if (out is String) return out;
    if (out is List) {
      final buf = StringBuffer();
      for (final o in out) {
        if (o is Map) {
          buf.write(_join(o['content']));
        } else if (o is String) {
          buf.write(o);
        }
      }
      if (buf.isNotEmpty) return buf.toString();
    }
    return '';
  }

  /// قطعة بث واحدة (SSE)
  static String deltaFromJson(dynamic j) {
    if (j is! Map) return '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final c = choices.first as Map;
      final d = c['delta'];
      if (d is Map) {
        final s = _join(d['content']);
        if (s.isNotEmpty) return s;
        return '';
      }
      if (c['text'] is String) return c['text'] as String;
      final m = c['message'];
      if (m is Map) return _join(m['content']);
      return '';
    }
    final type = j['type'];
    if (type is String) {
      // Anthropic
      if (type == 'content_block_delta') {
        final d = j['delta'];
        if (d is Map && d['text'] is String) return d['text'] as String;
      }
      return '';
    }
    // Ollama
    final msg = j['message'];
    if (msg is Map && msg['content'] is String) return msg['content'] as String;
    if (j['response'] is String) return j['response'] as String;
    final cands = j['candidates'];
    if (cands is List) return textFromJson(j);
    return '';
  }

  /// رسالة خطأ مفهومة من جسم استجابة فاشلة (أو null)
  static String? errorFrom(String body) {
    final t = body.trim();
    if (t.isEmpty) return null;
    try {
      final d = jsonDecode(t);
      dynamic e = d;
      if (d is List && d.isNotEmpty) e = d.first;
      if (e is Map) {
        final err = e['error'];
        if (err is String) return err;
        if (err is Map) {
          final m = err['message'] ?? err['detail'] ?? err['code'];
          if (m != null) return m.toString();
        }
        for (final k in ['message', 'detail', 'error_description', 'msg']) {
          if (e[k] is String) return e[k] as String;
          if (e[k] is List && (e[k] as List).isNotEmpty) {
            return (e[k] as List).first.toString();
          }
        }
        if (e['errors'] is List && (e['errors'] as List).isNotEmpty) {
          return (e['errors'] as List).first.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  static bool looksLikeHtml(String body) {
    final t = body.trimLeft().toLowerCase();
    return t.startsWith('<!doctype') || t.startsWith('<html');
  }
}
