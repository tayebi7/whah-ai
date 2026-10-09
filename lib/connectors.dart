import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_service.dart';
import 'file_processor.dart';
import 'models.dart';
import 'net_utils.dart';

/// أنواع الموصلات المتاحة في الواجهة
class ConnectorType {
  final String id;
  final String title;
  final String description;
  final String urlLabel;
  final String tokenLabel;
  final String extraLabel;

  const ConnectorType({
    required this.id,
    required this.title,
    required this.description,
    this.urlLabel = '',
    this.tokenLabel = '',
    this.extraLabel = '',
  });
}

const List<ConnectorType> kConnectorTypes = [
  ConnectorType(
    id: 'github',
    title: 'GitHub',
    description:
        'ألصق رابط مستودع أو ملف أو Issue في المحادثة وسيقرؤه التطبيق ويضيفه كسياق. '
        'التوكن اختياري للمستودعات الخاصة.',
    tokenLabel: 'Personal Access Token (اختياري)',
  ),
  ConnectorType(
    id: 'telegram',
    title: 'Telegram Bot',
    description: 'أرسل أي إجابة إلى محادثتك على تيليغرام عبر بوت.',
    tokenLabel: 'Bot Token',
    extraLabel: 'Chat ID',
  ),
  ConnectorType(
    id: 'webhook',
    title: 'Webhook (Zapier / Make / n8n / Slack / Discord)',
    description: 'أرسل الإجابة إلى أي خدمة تدعم Webhook وفعّل أتمتة مع تطبيقاتك.',
    urlLabel: 'رابط Webhook',
  ),
  ConnectorType(
    id: 'rest',
    title: 'REST API مخصص',
    description:
        'اربط أي API: الروابط التابعة لنفس المضيف التي تلصقها في المحادثة تُجلب بالتوكن وتُضاف كسياق.',
    urlLabel: 'الرابط الأساسي (https://api.example.com)',
    tokenLabel: 'Bearer Token (اختياري)',
  ),
];

ConnectorType connectorTypeOf(String id) =>
    kConnectorTypes.firstWhere((t) => t.id == id, orElse: () => kConnectorTypes.last);

// ───────────────────────────── جلب سياق الروابط ─────────────────────────────

class UrlContext {
  static final RegExp urlRe = RegExp(r'https?://[^\s<>"\)\]،]+');

  static http.Client get _c => AIService.client;

  /// روابط فريدة من النص (بحد أقصى [max])
  static List<String> extract(String text, {int max = 3}) {
    final out = <String>[];
    for (final m in urlRe.allMatches(text)) {
      var u = m.group(0)!;
      while (u.isNotEmpty && '.,;:!?'.contains(u[u.length - 1])) {
        u = u.substring(0, u.length - 1);
      }
      if (!out.contains(u)) out.add(u);
      if (out.length >= max) break;
    }
    return out;
  }

  static Future<String> build(
      List<String> urls, List<ConnectorConfig> connectors) async {
    final b = StringBuffer();
    for (final u in urls) {
      String body;
      try {
        body = await _fetchOne(u, connectors).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        body = '(انتهت مهلة جلب الرابط)';
      } catch (e) {
        body = '(تعذر جلب الرابط: ${e.toString().replaceFirst('Exception: ', '')})';
      }
      b.writeln('===== رابط: $u =====');
      b.writeln(body.trim());
      b.writeln('===== نهاية الرابط =====');
      b.writeln();
    }
    return b.toString().trim();
  }

  static Future<String> _fetchOne(String url, List<ConnectorConfig> cons) async {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    if (host == 'github.com' || host == 'www.github.com') {
      String token = '';
      for (final c in cons) {
        if (c.enabled && c.type == 'github') token = Sanitize.key(c.token);
      }
      return _github(uri, token);
    }
    // موصل REST لنفس المضيف
    for (final c in cons) {
      if (!c.enabled || c.type != 'rest') continue;
      final base = Uri.tryParse(Sanitize.url(c.url));
      if (base != null && base.host.toLowerCase() == host) {
        final tok = Sanitize.key(c.token);
        final r = await _c.get(uri, headers: {
          'Accept': 'application/json, text/plain, */*',
          if (tok.isNotEmpty) 'Authorization': 'Bearer $tok',
        });
        final t = utf8.decode(r.bodyBytes, allowMalformed: true);
        if (r.statusCode >= 300) return '(خطأ ${r.statusCode}) ${_cut(t, 500)}';
        return _cut(t, 12000);
      }
    }
    // منصات التواصل (oEmbed)
    final oembed = _oembedUrl(host, url);
    if (oembed != null) {
      try {
        final r = await _c.get(Uri.parse(oembed));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
          if (j is Map) {
            final b = StringBuffer();
            final platform = host.replaceFirst('www.', '');
            b.writeln('المنصة: $platform');
            for (final k in ['title', 'author_name', 'provider_name']) {
              if (j[k] != null) b.writeln('$k: ${j[k]}');
            }
            if (j['html'] != null) {
              b.writeln('النص: ${FileProcessor.htmlToText(j['html'].toString())}');
            }
            return b.toString();
          }
        }
      } catch (_) {}
    }
    return _web(uri);
  }

  static String? _oembedUrl(String host, String url) {
    final enc = Uri.encodeComponent(url);
    if (host.contains('youtube.com') || host == 'youtu.be') {
      return 'https://www.youtube.com/oembed?url=$enc&format=json';
    }
    if (host.contains('tiktok.com')) return 'https://www.tiktok.com/oembed?url=$enc';
    if (host == 'twitter.com' || host.endsWith('.twitter.com') || host == 'x.com' || host == 'www.x.com') {
      return 'https://publish.twitter.com/oembed?url=$enc';
    }
    return null;
  }

  static String _cut(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

  static String _meta(String html, String name) {
    final re1 = RegExp(
        '<meta[^>]+(?:property|name)=["\']$name["\'][^>]+content=["\']([^"\']*)["\']',
        caseSensitive: false);
    final re2 = RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]+(?:property|name)=["\']$name["\']',
        caseSensitive: false);
    final m = re1.firstMatch(html) ?? re2.firstMatch(html);
    return m == null ? '' : FileProcessor.unescapeXml(m.group(1) ?? '');
  }

  static Future<String> _web(Uri uri) async {
    final r = await _c.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
      'Accept': 'text/html,application/json,text/plain;q=0.9,*/*;q=0.8',
      'Accept-Language': 'ar,en;q=0.8',
    });
    if (r.statusCode >= 400) {
      return '(الموقع رفض الطلب: ${r.statusCode}. قد يتطلب تسجيل دخول)';
    }
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final ctype = (r.headers['content-type'] ?? '').toLowerCase();
    if (ctype.contains('json') || ctype.contains('text/plain')) {
      return _cut(body, 12000);
    }
    final title = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
            .firstMatch(body)
            ?.group(1) ??
        '';
    final b = StringBuffer();
    final t = FileProcessor.unescapeXml(title).trim();
    if (t.isNotEmpty) b.writeln('العنوان: $t');
    for (final k in ['og:title', 'og:description', 'description', 'og:site_name', 'og:type']) {
      final v = _meta(body, k);
      if (v.isNotEmpty) b.writeln('$k: $v');
    }
    final text = FileProcessor.htmlToText(body);
    if (text.isNotEmpty) {
      b.writeln('\nالنص الظاهر في الصفحة:');
      b.writeln(_cut(text, 7000));
    }
    if (b.isEmpty) return '(لا يوجد محتوى نصي ظاهر. قد يحتاج الموقع لتسجيل دخول)';
    return b.toString();
  }

  // ─── GitHub ───

  static Map<String, String> _ghHeaders(String token, {bool raw = false}) => {
        'Accept': raw ? 'application/vnd.github.raw' : 'application/vnd.github+json',
        'User-Agent': 'WHAH-AI',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  static Future<String> _github(Uri uri, String token) async {
    final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segs.length < 2) return '(رابط GitHub غير مكتمل)';
    final owner = segs[0];
    var repo = segs[1];
    if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
    final api = 'https://api.github.com/repos/$owner/$repo';
    final b = StringBuffer();

    Future<String> getText(String u, {bool raw = false}) async {
      final r = await _c.get(Uri.parse(u), headers: _ghHeaders(token, raw: raw));
      final t = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 404) {
        throw Exception('غير موجود أو خاص (أضف توكن في الموصل). ');
      }
      if (r.statusCode == 403 || r.statusCode == 429) {
        throw Exception('تجاوز حد GitHub. أضف توكن في موصل GitHub.');
      }
      if (r.statusCode >= 300) throw Exception('GitHub ${r.statusCode}');
      return t;
    }

    final kind = segs.length > 2 ? segs[2] : '';
    if ((kind == 'issues' || kind == 'pull') && segs.length > 3) {
      final n = segs[3];
      final j = jsonDecode(await getText('$api/issues/$n'));
      if (j is Map) {
        b.writeln('${kind == 'pull' ? 'Pull Request' : 'Issue'} #$n: ${j['title']}');
        b.writeln('الحالة: ${j['state']}  |  بواسطة: ${(j['user'] as Map?)?['login']}');
        b.writeln('\n${_cut(j['body']?.toString() ?? '', 8000)}');
      }
      try {
        final cj = jsonDecode(await getText('$api/issues/$n/comments?per_page=10'));
        if (cj is List && cj.isNotEmpty) {
          b.writeln('\nالتعليقات:');
          for (final c in cj) {
            if (c is Map) {
              b.writeln('- ${(c['user'] as Map?)?['login']}: ${_cut(c['body']?.toString() ?? '', 1200)}');
            }
          }
        }
      } catch (_) {}
      return b.toString();
    }

    if ((kind == 'blob' || kind == 'tree') && segs.length > 3) {
      final ref = segs[3];
      final path = segs.sublist(4).join('/');
      final u = '$api/contents/$path?ref=${Uri.encodeComponent(ref)}';
      if (kind == 'blob') {
        final t = await getText(u, raw: true);
        b.writeln('الملف: $path (فرع $ref)');
        b.writeln(_cut(t, 20000));
        return b.toString();
      }
      final j = jsonDecode(await getText(u));
      if (j is List) {
        b.writeln('محتويات المجلد $path:');
        for (final e in j.take(100)) {
          if (e is Map) b.writeln('- ${e['type'] == 'dir' ? '[dir] ' : ''}${e['name']}');
        }
      }
      return b.toString();
    }

    // المستودع نفسه
    final info = jsonDecode(await getText(api));
    if (info is Map) {
      b.writeln('المستودع: ${info['full_name']}');
      b.writeln('الوصف: ${info['description'] ?? '-'}');
      b.writeln('اللغة: ${info['language'] ?? '-'}  |  النجوم: ${info['stargazers_count']}  |  الفرع الافتراضي: ${info['default_branch']}');
      if (info['topics'] is List) b.writeln('المواضيع: ${(info['topics'] as List).join(', ')}');
    }
    try {
      final list = jsonDecode(await getText('$api/contents'));
      if (list is List) {
        b.writeln('\nالملفات في الجذر:');
        for (final e in list.take(60)) {
          if (e is Map) b.writeln('- ${e['type'] == 'dir' ? '[dir] ' : ''}${e['name']}');
        }
      }
    } catch (_) {}
    try {
      final readme = await getText('$api/readme', raw: true);
      b.writeln('\nREADME:');
      b.writeln(_cut(readme, 7000));
    } catch (_) {}
    return b.toString();
  }
}

// ───────────────────────────── إرسال إلى الموصلات ─────────────────────────────

class ConnectorActions {
  static http.Client get _c => AIService.client;

  static bool canSend(ConnectorConfig c) =>
      c.enabled && (c.type == 'telegram' || c.type == 'webhook');

  /// يرسل نصاً عبر الموصل. يعيد رسالة نجاح أو يرمي Exception بسبب الفشل.
  static Future<String> send(ConnectorConfig c, String text) async {
    switch (c.type) {
      case 'telegram':
        return _sendTelegram(c, text);
      case 'webhook':
        return _sendWebhook(c, text);
      default:
        throw Exception('هذا الموصل لا يدعم الإرسال.');
    }
  }

  static Future<String> _sendTelegram(ConnectorConfig c, String text) async {
    final token = Sanitize.key(c.token);
    final chat = Sanitize.text(c.extra);
    if (token.isEmpty || chat.isEmpty) {
      throw Exception('أدخل Bot Token و Chat ID.');
    }
    final t = text.length > 4000 ? text.substring(0, 4000) : text;
    final r = await _c
        .post(Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({'chat_id': chat, 'text': t})))
        .timeout(const Duration(seconds: 25));
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode != 200) {
      throw Exception(ResponseParser.errorFrom(body) ??
          (body.contains('description') ? body : 'خطأ ${r.statusCode}'));
    }
    return 'تم الإرسال إلى تيليغرام';
  }

  static Future<String> _sendWebhook(ConnectorConfig c, String text) async {
    final url = Sanitize.url(c.url);
    if (url.isEmpty) throw Exception('أدخل رابط Webhook.');
    final isDiscord = url.contains('discord.com') || url.contains('discordapp.com');
    final t = isDiscord && text.length > 1900 ? text.substring(0, 1900) : text;
    final r = await _c
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({
              'text': t,
              'content': t,
              'message': t,
              'source': 'WHAH AI',
            })))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode >= 300) {
      throw Exception('رفض الـ Webhook الطلب (${r.statusCode}).');
    }
    return 'تم الإرسال عبر ${c.name}';
  }

  /// اختبار الاتصال: null = ناجح
  static Future<String?> test(ConnectorConfig c) async {
    try {
      final tok = Sanitize.key(c.token);
      const to = Duration(seconds: 20);
      if (c.type == 'github') {
        final r = await _c
            .get(Uri.parse('https://api.github.com/rate_limit'), headers: {
          'User-Agent': 'WHAH-AI',
          if (tok.isNotEmpty) 'Authorization': 'Bearer $tok',
        }).timeout(to);
        if (r.statusCode == 401) return 'التوكن غير صحيح';
        return r.statusCode == 200 ? null : 'خطأ ${r.statusCode}';
      }
      if (c.type == 'telegram') {
        if (tok.isEmpty) return 'أدخل Bot Token';
        final r = await _c
            .get(Uri.parse('https://api.telegram.org/bot$tok/getMe'))
            .timeout(to);
        return r.statusCode == 200 ? null : 'Bot Token غير صحيح (${r.statusCode})';
      }
      if (c.type == 'rest') {
        final u = Sanitize.url(c.url);
        if (u.isEmpty) return 'أدخل الرابط';
        final r = await _c.get(Uri.parse(u), headers: {
          if (tok.isNotEmpty) 'Authorization': 'Bearer $tok',
        }).timeout(to);
        return r.statusCode < 500 ? null : 'الخادم أعاد ${r.statusCode}';
      }
      if (c.type == 'webhook') {
        return Sanitize.url(c.url).isEmpty ? 'أدخل رابط Webhook' : null;
      }
      return null;
    } on TimeoutException {
      return 'انتهت مهلة الاتصال';
    } catch (e) {
      return 'تعذر الاتصال: $e';
    }
  }
}
