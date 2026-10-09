import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ai_service.dart';
import 'models.dart';
import 'net_utils.dart';

class MediaResult {
  final Uint8List bytes;
  final DetectedType type;
  final String provider;
  const MediaResult(this.bytes, this.type, this.provider);
}

/// توليد الصور والفيديو + حفظ الوسائط بالامتداد الحقيقي (من محتوى الملف).
class MediaService {
  static http.Client get _c => AIService.client;

  static String _utf8(List<int> b) => utf8.decode(b, allowMalformed: true);

  static Map<String, String> _authHeaders(ProviderConfig p,
      {bool json = true}) {
    final key = Sanitize.key(p.apiKey);
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    if (key.isNotEmpty) h['Authorization'] = 'Bearer $key';
    return h;
  }

  // ───────────── الصور ─────────────

  static Future<MediaResult> generateImage({
    required String prompt,
    required List<ProviderConfig> providers,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final errors = <String>[];
    final list = providers
        .where((p) => p.usable && Sanitize.model(p.imageModel).isNotEmpty)
        .toList();
    var triedPollinations = false;

    for (final p in list) {
      if (isCancelled != null && isCancelled()) {
        throw const LlmException('تم الإيقاف', kind: 'cancel');
      }
      onStatus?.call('توليد الصورة عبر ${p.name}…');
      try {
        final ep = ApiEndpoints.parse(p.endpoint, format: p.format);
        if (ep.isPollinations) {
          triedPollinations = true;
          return await _pollinationsImage(prompt, Sanitize.model(p.imageModel), p);
        }
        return await _openAiImage(p, ep, prompt);
      } catch (e) {
        errors.add('• ${p.name}: ${_short(e)}');
      }
    }

    if (!triedPollinations) {
      if (isCancelled != null && isCancelled()) {
        throw const LlmException('تم الإيقاف', kind: 'cancel');
      }
      onStatus?.call('توليد الصورة عبر Pollinations (مجاني)…');
      try {
        return await _pollinationsImage(prompt, 'flux', null);
      } catch (e) {
        errors.add('• Pollinations: ${_short(e)}');
      }
    }
    throw LlmException(errors.join('\n'), kind: 'all');
  }

  static String _short(Object e) {
    final s = e is LlmException ? e.message : e.toString();
    return s.replaceFirst('Exception: ', '').split('\n').first;
  }

  static Future<MediaResult> _openAiImage(
      ProviderConfig p, ApiEndpoints ep, String prompt) async {
    if (ep.error != null) throw LlmException(ep.error!, kind: 'config');
    final model = Sanitize.model(p.imageModel);

    Future<http.Response> post(bool withFormat) {
      final body = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'n': 1,
        'size': '1024x1024',
      };
      if (withFormat && !model.startsWith('gpt-image')) {
        body['response_format'] = 'b64_json';
      }
      return _c
          .post(Uri.parse(ep.imagesUrl),
              headers: _authHeaders(p), body: utf8.encode(jsonEncode(body)))
          .timeout(const Duration(seconds: 150));
    }

    var resp = await post(true);
    if (resp.statusCode == 400) {
      final t = _utf8(resp.bodyBytes);
      if (t.contains('response_format')) resp = await post(false);
    }
    final text = _utf8(resp.bodyBytes);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LlmException(
          'خطأ ${resp.statusCode}: ${ResponseParser.errorFrom(text) ?? text}',
          status: resp.statusCode);
    }
    final bytes = await _bytesFromJson(text, p);
    final type = detectType(bytes);
    if (type.kind != 'image') {
      throw const LlmException('المزود لم يُرجع صورة صالحة.');
    }
    return MediaResult(bytes, type, p.name);
  }

  static Future<MediaResult> _pollinationsImage(
      String prompt, String model, ProviderConfig? p) async {
    final seed = Random().nextInt(1 << 30);
    final short = prompt.length > 700 ? prompt.substring(0, 700) : prompt;
    final enc = Uri.encodeComponent(short);
    final urls = <String>[
      'https://image.pollinations.ai/prompt/$enc?width=1024&height=1024&nologo=true&model=$model&seed=$seed',
      'https://image.pollinations.ai/prompt/$enc?width=1024&height=1024&nologo=true&seed=$seed',
    ];
    Object? last;
    for (final u in urls) {
      try {
        final resp = await _c
            .get(Uri.parse(u),
                headers: p == null ? <String, String>{} : _authHeaders(p, json: false))
            .timeout(const Duration(seconds: 120));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          last = LlmException('خطأ ${resp.statusCode} من Pollinations',
              status: resp.statusCode);
          continue;
        }
        final type = detectType(resp.bodyBytes);
        if (type.kind != 'image') {
          last = const LlmException('Pollinations لم يُرجع صورة صالحة.');
          continue;
        }
        return MediaResult(resp.bodyBytes, type, 'Pollinations');
      } catch (e) {
        last = e;
      }
    }
    throw last ?? const LlmException('فشل توليد الصورة.');
  }

  // ───────────── الفيديو ─────────────

  static Future<MediaResult> generateVideo({
    required String prompt,
    required List<ProviderConfig> providers,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final list = providers
        .where((p) => p.usable && Sanitize.model(p.videoModel).isNotEmpty)
        .toList();
    if (list.isEmpty) {
      throw const LlmException(
          'لا يوجد مزود فيديو. أضف مزوداً يدعم توليد الفيديو واكتب اسم «نموذج الفيديو» في إعداداته.',
          kind: 'config');
    }
    final errors = <String>[];
    for (final p in list) {
      try {
        return await _openAiVideo(p, prompt, onStatus, isCancelled);
      } on LlmException catch (e) {
        if (e.kind == 'cancel') rethrow;
        errors.add('• ${p.name}: ${_short(e)}');
      } catch (e) {
        errors.add('• ${p.name}: ${_short(e)}');
      }
    }
    throw LlmException(errors.join('\n'), kind: 'all');
  }

  static Future<MediaResult> _openAiVideo(
    ProviderConfig p,
    String prompt,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  ) async {
    final ep = ApiEndpoints.parse(p.endpoint, format: p.format);
    if (ep.error != null) throw LlmException(ep.error!, kind: 'config');
    final model = Sanitize.model(p.videoModel);
    onStatus?.call('إرسال طلب الفيديو إلى ${p.name}…');

    final resp = await _c
        .post(Uri.parse(ep.videosUrl),
            headers: _authHeaders(p),
            body: utf8.encode(jsonEncode({'model': model, 'prompt': prompt})))
        .timeout(const Duration(seconds: 90));
    final text = _utf8(resp.bodyBytes);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LlmException(
          'خطأ ${resp.statusCode}: ${ResponseParser.errorFrom(text) ?? text}',
          status: resp.statusCode);
    }

    dynamic j;
    try {
      j = jsonDecode(text);
    } catch (_) {}

    // نتيجة مباشرة (رابط أو base64)؟
    final direct = await _tryBytesFromJson(j, p);
    if (direct != null && detectType(direct).kind == 'video') {
      return MediaResult(direct, detectType(direct), p.name);
    }

    // مهمة غير متزامنة (نمط OpenAI Sora): id + status
    final id = j is Map ? j['id']?.toString() : null;
    if (id == null || id.isEmpty) {
      throw const LlmException('استجابة الفيديو غير مفهومة من المزود.');
    }
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled != null && isCancelled()) {
        throw const LlmException('تم الإيقاف', kind: 'cancel');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      final r = await _c
          .get(Uri.parse('${ep.videosUrl}/$id'),
              headers: _authHeaders(p, json: false))
          .timeout(const Duration(seconds: 60));
      final t = _utf8(r.bodyBytes);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw LlmException('خطأ ${r.statusCode}: ${ResponseParser.errorFrom(t) ?? t}',
            status: r.statusCode);
      }
      dynamic s;
      try {
        s = jsonDecode(t);
      } catch (_) {}
      final status = s is Map ? (s['status']?.toString() ?? '') : '';
      final progress = s is Map && s['progress'] != null ? ' ${s['progress']}%' : '';
      if (status == 'failed' || status == 'error' || status == 'cancelled') {
        final err = s is Map ? ResponseParser.errorFrom(t) : null;
        throw LlmException(err ?? 'فشل توليد الفيديو.');
      }
      if (status == 'completed' || status == 'succeeded' || status == 'done') {
        final dl = await _c
            .get(Uri.parse('${ep.videosUrl}/$id/content'),
                headers: _authHeaders(p, json: false))
            .timeout(const Duration(minutes: 3));
        if (dl.statusCode >= 200 && dl.statusCode < 300) {
          final type = detectType(dl.bodyBytes);
          if (type.kind == 'video') return MediaResult(dl.bodyBytes, type, p.name);
        }
        final viaJson = await _tryBytesFromJson(s, p);
        if (viaJson != null && detectType(viaJson).kind == 'video') {
          return MediaResult(viaJson, detectType(viaJson), p.name);
        }
        throw const LlmException('اكتمل التوليد لكن تعذر تنزيل الفيديو.');
      }
      onStatus?.call('جارٍ توليد الفيديو…$progress');
    }
    throw const LlmException('انتهت مهلة توليد الفيديو (10 دقائق).', kind: 'timeout');
  }

  // ───────────── استخراج الوسائط من JSON ─────────────

  static Future<Uint8List> _bytesFromJson(String body, ProviderConfig p) async {
    dynamic j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      throw const LlmException('استجابة غير صالحة (ليست JSON).');
    }
    final b = await _tryBytesFromJson(j, p);
    if (b == null) {
      throw const LlmException('لم يتم العثور على صورة في استجابة المزود.');
    }
    return b;
  }

  static const _b64Keys = {'b64_json', 'base64', 'b64', 'image_base64', 'video_base64'};
  static const _urlKeys = {
    'url',
    'image_url',
    'video_url',
    'download_url',
    'uri',
    'output_url',
    'image',
    'video',
  };

  static Future<Uint8List?> _tryBytesFromJson(dynamic j, ProviderConfig p) async {
    final ref = _findRef(j, 0);
    if (ref == null) return null;
    if (ref.startsWith('data:')) {
      final i = ref.indexOf('base64,');
      if (i > 0) return _decodeB64(ref.substring(i + 7));
    }
    if (ref.startsWith('http')) {
      final r = await _c
          .get(Uri.parse(ref), headers: _authHeadersFor(ref, p))
          .timeout(const Duration(minutes: 3));
      if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
      return null;
    }
    return _decodeB64(ref);
  }

  static Map<String, String> _authHeadersFor(String url, ProviderConfig p) {
    // لا نرسل المفتاح إلى مضيف مختلف عن مضيف المزود (روابط CDN موقّعة)
    final ph = ApiEndpoints.parse(p.endpoint).host;
    final uh = Uri.tryParse(url)?.host ?? '';
    if (ph.isNotEmpty && uh == ph) return _authHeaders(p, json: false);
    return <String, String>{};
  }

  static Uint8List? _decodeB64(String s) {
    try {
      return base64.decode(s.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }

  static String? _findRef(dynamic j, int depth) {
    if (depth > 4 || j == null) return null;
    if (j is Map) {
      for (final k in j.keys) {
        final v = j[k];
        if (v is String && v.isNotEmpty) {
          final key = k.toString();
          if (_b64Keys.contains(key)) return v;
          if (_urlKeys.contains(key) && (v.startsWith('http') || v.startsWith('data:'))) {
            return v;
          }
        }
      }
      for (final k in ['data', 'images', 'videos', 'output', 'result', 'results']) {
        final r = _findRef(j[k], depth + 1);
        if (r != null) return r;
      }
      for (final v in j.values) {
        if (v is Map || v is List) {
          final r = _findRef(v, depth + 1);
          if (r != null) return r;
        }
      }
    } else if (j is List) {
      for (final v in j) {
        if (v is String && v.startsWith('http')) return v;
        final r = _findRef(v, depth + 1);
        if (r != null) return r;
      }
    } else if (j is String && j.startsWith('http')) {
      return j;
    }
    return null;
  }

  // ───────────── الحفظ ─────────────

  /// يحفظ الوسائط بالامتداد الحقيقي المكتشف من المحتوى (png/jpg/webp/mp4/webm...).
  static Future<MediaItem> save(MediaResult r) async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/media');
    if (!await d.exists()) await d.create(recursive: true);
    final name = '${DateTime.now().millisecondsSinceEpoch}.${r.type.ext}';
    final f = File('${d.path}/$name');
    await f.writeAsBytes(r.bytes, flush: true);
    return MediaItem(
      path: f.path,
      kind: r.type.kind == 'video' ? 'video' : 'image',
      mime: r.type.mime,
    );
  }
}
