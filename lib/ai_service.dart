import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'net_utils.dart';

// ───────────────────────────── أنواع مساعدة ─────────────────────────────

class ImagePart {
  final String mime;
  final String b64;
  const ImagePart(this.mime, this.b64);
}

class LlmMessage {
  final String role; // system | user | assistant
  final String text;
  final List<ImagePart> images;
  const LlmMessage(this.role, this.text, {this.images = const []});
}

/// خطأ اتصال بمزود. [kind] يحدد سلوك التبديل التلقائي:
/// auth | notfound | rate | quota | server | timeout | network | empty | bad | config | cancel
class LlmException implements Exception {
  final String message;
  final int? status;
  final String kind;
  const LlmException(this.message, {this.status, this.kind = 'other'});

  @override
  String toString() => message;
}

class ChatResult {
  final String text;
  final String provider;
  const ChatResult(this.text, this.provider);
}

// ───────────────────────────── خدمة مزود واحد ─────────────────────────────

class AIService {
  AIService(this.cfg);

  final ProviderConfig cfg;

  /// قابل للاستبدال في الاختبارات
  static http.Client client = http.Client();

  ApiEndpoints get _ep => ApiEndpoints.parse(cfg.endpoint, format: cfg.format);

  String _model(bool vision) {
    final v = Sanitize.model(cfg.visionModel);
    final m = Sanitize.model(cfg.model);
    if (vision && v.isNotEmpty) return v;
    if (m.isNotEmpty) return m;
    return _ep.isPollinations ? 'openai' : '';
  }

  Map<String, String> _headers({bool stream = false}) {
    final key = Sanitize.key(cfg.apiKey);
    final ep = _ep;
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': stream ? 'text/event-stream' : 'application/json',
    };
    if (ep.format == 'anthropic') {
      if (key.isNotEmpty) h['x-api-key'] = key;
      h['anthropic-version'] = '2023-06-01';
    } else if (key.isNotEmpty) {
      h['Authorization'] = 'Bearer $key';
    }
    if (ep.host.contains('openrouter.ai')) {
      h['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      h['X-Title'] = 'WHAH AI';
    }
    return h;
  }

  // ─── بناء الطلب ───

  List<Map<String, dynamic>> _openAiMessages(List<LlmMessage> ms) {
    return ms.map<Map<String, dynamic>>((m) {
      if (m.images.isEmpty) return {'role': m.role, 'content': m.text};
      return {
        'role': m.role,
        'content': [
          {'type': 'text', 'text': m.text.isEmpty ? 'حلل الصورة.' : m.text},
          for (final i in m.images)
            {
              'type': 'image_url',
              'image_url': {'url': 'data:${i.mime};base64,${i.b64}'},
            },
        ],
      };
    }).toList();
  }

  Map<String, dynamic> _anthropicBody(
      List<LlmMessage> ms, String model, bool stream, double temp, int? maxTokens) {
    final system = ms
        .where((m) => m.role == 'system')
        .map((m) => m.text)
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
    final msgs = <Map<String, dynamic>>[];
    for (final m in ms) {
      if (m.role == 'system') continue;
      final role = m.role == 'assistant' ? 'assistant' : 'user';
      final blocks = <Map<String, dynamic>>[
        for (final i in m.images)
          {
            'type': 'image',
            'source': {'type': 'base64', 'media_type': i.mime, 'data': i.b64},
          },
        {'type': 'text', 'text': m.text.isEmpty ? '.' : m.text},
      ];
      if (msgs.isNotEmpty && msgs.last['role'] == role) {
        (msgs.last['content'] as List).addAll(blocks);
      } else {
        msgs.add({'role': role, 'content': blocks});
      }
    }
    if (msgs.isEmpty || msgs.first['role'] != 'user') {
      msgs.insert(0, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '.'}
        ],
      });
    }
    return {
      'model': model,
      'max_tokens': maxTokens ?? 4096,
      if (system.isNotEmpty) 'system': system,
      'messages': msgs,
      'stream': stream,
      'temperature': temp.clamp(0.0, 1.0),
    };
  }

  String _body(List<LlmMessage> ms,
      {required bool vision,
      required bool stream,
      required double temperature,
      int? maxTokens}) {
    final model = _model(vision);
    if (_ep.format == 'anthropic') {
      return jsonEncode(
          _anthropicBody(ms, model, stream, temperature, maxTokens));
    }
    final body = <String, dynamic>{
      'model': model,
      'messages': _openAiMessages(ms),
      'stream': stream,
      'temperature': temperature,
    };
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    return jsonEncode(body);
  }

  // ─── الأخطاء ───

  LlmException _errorFor(int status, String body, String url) {
    final detail = ResponseParser.errorFrom(body) ??
        (ResponseParser.looksLikeHtml(body)
            ? 'الخادم أعاد صفحة HTML'
            : (body.length > 300 ? '${body.substring(0, 300)}…' : body));
    String msg;
    String kind;
    if (status == 401 || status == 403) {
      kind = 'auth';
      msg = 'مفتاح API غير صحيح أو لا يملك صلاحية ($status).';
    } else if (status == 404) {
      kind = 'notfound';
      msg = 'العنوان أو اسم النموذج غير صحيح (404).';
    } else if (status == 429) {
      kind = 'rate';
      msg = 'تجاوزت حد الاستخدام المؤقت (429).';
    } else if (status == 402) {
      kind = 'quota';
      msg = 'الرصيد أو الحصة منتهية (402).';
    } else if (status == 408 || status >= 500) {
      kind = 'server';
      msg = 'خطأ في خادم المزود ($status).';
    } else {
      kind = 'bad';
      msg = 'الطلب مرفوض ($status).';
    }
    final d = detail.trim();
    return LlmException(d.isEmpty ? msg : '$msg\n$d', status: status, kind: kind);
  }

  Future<T> _guard<T>(Future<T> Function() fn, Duration timeout) async {
    try {
      return await fn();
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw LlmException('انتهت مهلة الاتصال (${timeout.inSeconds} ث).',
          kind: 'timeout');
    } on SocketException {
      throw const LlmException('تعذر الاتصال بالخادم. تحقق من الإنترنت أو العنوان.',
          kind: 'network');
    } on HandshakeException {
      throw const LlmException(
          'فشل التشفير (SSL). تأكد أن العنوان https صحيح وأن وقت الجهاز مضبوط.',
          kind: 'network');
    } on http.ClientException catch (e) {
      throw LlmException('خطأ في الاتصال: ${e.message}', kind: 'network');
    } on FormatException {
      throw const LlmException('العنوان أو الاستجابة غير صالحة.', kind: 'config');
    }
  }

  String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  // ─── طلب عادي ───

  Future<String> complete(
    List<LlmMessage> messages, {
    bool vision = false,
    double temperature = 0.7,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final ep = _ep;
    if (ep.error != null) throw LlmException(ep.error!, kind: 'config');
    if (_model(vision).isEmpty) {
      throw const LlmException('لم يتم إدخال اسم النموذج.', kind: 'config');
    }
    final body = _body(messages,
        vision: vision, stream: false, temperature: temperature, maxTokens: maxTokens);
    LlmException? last;
    for (final url in ep.chatCandidates) {
      try {
        return await _guard(() async {
          final resp = await client
              .post(Uri.parse(url), headers: _headers(), body: utf8.encode(body))
              .timeout(timeout);
          final text = _decode(resp.bodyBytes);
          if (resp.statusCode < 200 || resp.statusCode >= 300) {
            throw _errorFor(resp.statusCode, text, url);
          }
          if (ResponseParser.looksLikeHtml(text)) {
            throw const LlmException(
                'العنوان يُرجع صفحة ويب وليس JSON. استخدم رابط API الصحيح (مثل .../v1).',
                kind: 'config');
          }
          final out = ResponseParser.extractText(text);
          if (out.trim().isEmpty) {
            final err = ResponseParser.errorFrom(text);
            if (err != null) throw LlmException(err, kind: 'bad');
            throw const LlmException('استجابة فارغة من الخادم', kind: 'empty');
          }
          return out;
        }, timeout);
      } on LlmException catch (e) {
        last = e;
        if ((e.status == 404 || e.status == 405) && url != ep.chatCandidates.last) {
          continue;
        }
        rethrow;
      }
    }
    throw last ?? const LlmException('فشل الاتصال');
  }

  // ─── بث (SSE) ───

  Future<String> stream(
    List<LlmMessage> messages, {
    required void Function(String chunk) onChunk,
    bool Function()? isCancelled,
    bool vision = false,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final ep = _ep;
    if (ep.error != null) throw LlmException(ep.error!, kind: 'config');
    if (_model(vision).isEmpty) {
      throw const LlmException('لم يتم إدخال اسم النموذج.', kind: 'config');
    }
    final body = _body(messages,
        vision: vision, stream: true, temperature: temperature);
    LlmException? last;
    for (final url in ep.chatCandidates) {
      try {
        return await _guard(() async {
          final req = http.Request('POST', Uri.parse(url));
          req.headers.addAll(_headers(stream: true));
          req.bodyBytes = utf8.encode(body);
          final streamed = await client.send(req).timeout(timeout);

          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            final errBody = _decode(await streamed.stream.toBytes());
            throw _errorFor(streamed.statusCode, errBody, url);
          }

          final ctype = (streamed.headers['content-type'] ?? '').toLowerCase();
          final result = StringBuffer();
          final raw = StringBuffer();

          void emit(String c) {
            if (c.isEmpty) return;
            result.write(c);
            onChunk(c);
          }

          final lines = streamed.stream
              .timeout(timeout)
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          await for (final line in lines) {
            if (isCancelled != null && isCancelled()) break;
            final v = line.trim();
            if (v.isEmpty || v.startsWith(':') || v.startsWith('event:')) continue;
            var data = v;
            if (v.startsWith('data:')) data = v.substring(5).trim();
            if (data == '[DONE]') break;
            if (data.isEmpty) continue;
            if (!ctype.contains('event-stream') && !v.startsWith('data:')) {
              // قد يكون JSON كامل (بدون SSE) أو NDJSON
              raw.writeln(v);
            }
            try {
              final j = jsonDecode(data);
              if (j is Map && j['error'] != null && result.isEmpty) {
                final err = ResponseParser.errorFrom(data) ?? 'خطأ من المزود';
                throw LlmException(err, kind: 'bad');
              }
              emit(ResponseParser.deltaFromJson(j));
            } on LlmException {
              rethrow;
            } catch (_) {}
          }

          if (result.isEmpty && raw.isNotEmpty) {
            // الخادم تجاهل stream وأعاد JSON عادياً
            if (ResponseParser.looksLikeHtml(raw.toString())) {
              throw const LlmException(
                  'العنوان يُرجع صفحة ويب وليس JSON. استخدم رابط API الصحيح.',
                  kind: 'config');
            }
            emit(ResponseParser.extractText(raw.toString()));
          }
          if (result.isEmpty && !(isCancelled != null && isCancelled())) {
            throw const LlmException('استجابة فارغة من الخادم', kind: 'empty');
          }
          return result.toString();
        }, timeout);
      } on LlmException catch (e) {
        last = e;
        if ((e.status == 404 || e.status == 405) && url != ep.chatCandidates.last) {
          continue;
        }
        rethrow;
      }
    }
    throw last ?? const LlmException('فشل الاتصال');
  }

  /// اختبار بسيط: يعيد null عند النجاح أو رسالة الخطأ
  Future<String?> test() async {
    try {
      final r = await complete(
        const [LlmMessage('user', 'Hi')],
        maxTokens: 8,
        temperature: 0,
        timeout: const Duration(seconds: 20),
      );
      return r.trim().isEmpty ? 'استجابة فارغة من الخادم' : null;
    } on LlmException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}

// ───────────────────────────── الموجّه: تبديل تلقائي بين المزودين ─────────────────────────────

class ChatRouter {
  static final Map<String, DateTime> _cooldown = {};

  static void resetState() => _cooldown.clear();

  static bool _cooling(ProviderConfig p) {
    final t = _cooldown[p.id];
    return t != null && t.isAfter(DateTime.now());
  }

  static void _markFailed(ProviderConfig p, LlmException e) {
    int secs;
    switch (e.kind) {
      case 'rate':
        secs = 60;
        break;
      case 'quota':
      case 'auth':
        secs = 600;
        break;
      case 'notfound':
        secs = 120;
        break;
      case 'server':
      case 'timeout':
        secs = 30;
        break;
      case 'network':
        secs = 15;
        break;
      case 'empty':
        secs = 20;
        break;
      default:
        secs = 0;
    }
    if (secs > 0) {
      _cooldown[p.id] = DateTime.now().add(Duration(seconds: secs));
    }
  }

  /// ترتيب التجربة: المزود المحدد أولاً (إن وُجد) ثم الباقي بترتيب القائمة،
  /// والمزودون المتعثرون مؤخراً في النهاية، وعند الصور يتقدم من له نموذج رؤية.
  static List<ProviderConfig> candidates(
    List<ProviderConfig> all, {
    String activeId = 'auto',
    bool autoSwitch = true,
    bool vision = false,
  }) {
    final usable = all.where((p) => p.usable).toList();
    ProviderConfig? active;
    for (final p in usable) {
      if (p.id == activeId) active = p;
    }
    if (active != null && !autoSwitch) return [active];

    final rest = usable.where((p) => p.id != active?.id).toList();
    final ok = rest.where((p) => !_cooling(p)).toList();
    final cooling = rest.where((p) => _cooling(p)).toList();
    var ordered = [...ok, ...cooling];
    if (vision) {
      final withVision =
          ordered.where((p) => p.visionModel.trim().isNotEmpty).toList();
      final others =
          ordered.where((p) => p.visionModel.trim().isEmpty).toList();
      ordered = [...withVision, ...others];
    }
    return [if (active != null) active, ...ordered];
  }

  static Future<ChatResult> run({
    required List<ProviderConfig> providers,
    required List<LlmMessage> messages,
    String activeId = 'auto',
    bool autoSwitch = true,
    bool vision = false,
    bool stream = true,
    double temperature = 0.7,
    void Function(String chunk)? onChunk,
    void Function(String providerName)? onProvider,
    bool Function()? isCancelled,
  }) async {
    final list = candidates(providers,
        activeId: activeId, autoSwitch: autoSwitch, vision: vision);
    if (list.isEmpty) {
      throw const LlmException(
          'لا يوجد مزود جاهز. أضف مزوداً وأدخل مفتاح API من «المزودون».',
          kind: 'config');
    }

    final errors = <String>[];
    for (final p in list) {
      if (isCancelled != null && isCancelled()) {
        throw const LlmException('تم الإيقاف', kind: 'cancel');
      }
      onProvider?.call(p.name);
      final svc = AIService(p);
      final got = StringBuffer();
      try {
        String text;
        if (stream) {
          try {
            text = await svc.stream(
              messages,
              vision: vision,
              temperature: temperature,
              isCancelled: isCancelled,
              onChunk: (c) {
                got.write(c);
                onChunk?.call(c);
              },
            );
          } on LlmException catch (e) {
            if (got.isNotEmpty) rethrow;
            const noRetry = {
              'auth', 'config', 'rate', 'quota', 'notfound', 'cancel'
            };
            if (noRetry.contains(e.kind)) rethrow;
            // بعض المزودين لا يدعمون البث → جرّب الطلب العادي
            text = await svc.complete(messages,
                vision: vision, temperature: temperature);
            onChunk?.call(text);
          }
        } else {
          text = await svc.complete(messages,
              vision: vision, temperature: temperature);
          onChunk?.call(text);
        }
        _cooldown.remove(p.id);
        return ChatResult(text, p.name);
      } on LlmException catch (e) {
        if (got.isNotEmpty) {
          // وصل جزء من الإجابة قبل الانقطاع: نحتفظ به بدل التبديل وتكرار النص
          return ChatResult(got.toString(), p.name);
        }
        errors.add('• ${p.name}: ${e.message.split('\n').first}');
        _markFailed(p, e);
      }
    }
    throw LlmException(errors.join('\n'), kind: 'all');
  }

  /// طلب سريع بدون بث (للمهام الخلفية كترجمة وصف الصورة)
  static Future<String> quick({
    required List<ProviderConfig> providers,
    required String system,
    required String user,
    String activeId = 'auto',
    bool autoSwitch = true,
  }) async {
    final r = await run(
      providers: providers,
      messages: [LlmMessage('system', system), LlmMessage('user', user)],
      activeId: activeId,
      autoSwitch: autoSwitch,
      stream: false,
      temperature: 0.4,
    );
    return r.text.trim();
  }
}
