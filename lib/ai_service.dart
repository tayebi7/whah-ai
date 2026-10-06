import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// خدمة الاتصال بمزودي الذكاء الاصطناعي المتوافقين مع OpenAI API
class AIService {
  AIService({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.provider = 'custom',
  });

  final String endpoint;
  final String apiKey;
  final String model;
  final String provider;

  /// بناء رابط chat/completions بشكل صحيح دون تكرار المسار
  String get _url {
    var url = endpoint.trim();

    // إزالة مسافات وأخطاء لصق شائعة
    url = url.replaceAll(RegExp(r'\s+'), '');

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // إذا كان الرابط كاملاً بالفعل
    if (url.contains('/chat/completions')) {
      return url;
    }

    // OpenRouter base
    if (url.contains('openrouter.ai') && !url.endsWith('/v1')) {
      if (url.endsWith('/api')) {
        return '$url/v1/chat/completions';
      }
      return '$url/api/v1/chat/completions';
    }

    // حالات شائعة
    if (url.endsWith('/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api')) {
      return '$url/v1/chat/completions';
    }

    // افتراضي: أضف /v1/chat/completions
    return '$url/v1/chat/completions';
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }

    final p = provider.toLowerCase();
    final ep = endpoint.toLowerCase();

    // OpenRouter يطلب رؤوس إضافية
    if (p == 'openrouter' || ep.contains('openrouter.ai')) {
      headers['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'WHAH AI';
    }

    // بعض الـ Gateways تحتاج Accept مختلف
    if (p == 'gateway' || p == 'custom') {
      headers['Accept'] = 'application/json, text/event-stream';
    }

    return headers;
  }

  /// إرسال رسالة عادية (بدون بث)
  Future<String> sendMessage({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    _validate();

    final client = http.Client();

    try {
      final body = <String, dynamic>{
        'model': model.trim(),
        'messages': messages,
        'stream': false,
        'temperature': temperature,
      };

      if (maxTokens != null) {
        body['max_tokens'] = maxTokens;
      }

      final response = await client
          .post(
            Uri.parse(_url),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'خطأ ${response.statusCode} على $_url\n${_extractError(response.body)}',
        );
      }

      final content = _extractContent(response.body);
      if (content.trim().isEmpty) {
        throw Exception('استجابة فارغة من الخادم');
      }
      return content;
    } on SocketException {
      throw Exception('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالخادم (120 ثانية).');
    } on FormatException {
      throw Exception('عنوان API غير صالح.');
    } on http.ClientException catch (e) {
      throw Exception('خطأ في الاتصال: ${e.message}');
    } finally {
      client.close();
    }
  }

  /// بث الرسالة (Streaming) لسرعة استجابة مشابهة لـ ChatGPT / Claude
  Future<String> streamMessage({
    required List<Map<String, dynamic>> messages,
    required void Function(String text) onChunk,
    double temperature = 0.7,
  }) async {
    _validate();

    final client = http.Client();

    try {
      final request = http.Request('POST', Uri.parse(_url));

      final headers = Map<String, String>.from(_headers);
      headers['Accept'] = 'text/event-stream';
      request.headers.addAll(headers);

      request.body = jsonEncode({
        'model': model.trim(),
        'messages': messages,
        'stream': true,
        'temperature': temperature,
      });

      final streamed = await client.send(request).timeout(
            const Duration(seconds: 120),
          );

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final errorBody = await streamed.stream.bytesToString();
        throw Exception(
          'خطأ ${streamed.statusCode} على $_url\n${_extractError(errorBody)}',
        );
      }

      final result = StringBuffer();

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final value = line.trim();

        if (value.isEmpty) continue;

        if (value == 'data: [DONE]' || value == '[DONE]') {
          break;
        }

        // بعض الخوادم ترسل بدون بادئة data:
        String data = value;
        if (value.startsWith('data:')) {
          data = value.substring(5).trim();
        }

        if (data.isEmpty || data == '[DONE]') break;

        try {
          final decoded = jsonDecode(data);
          final chunk = _extractDelta(decoded);

          if (chunk.isNotEmpty) {
            result.write(chunk);
            onChunk(chunk);
          }
        } catch (_) {
          // تجاهل أسطر SSE غير JSON
        }
      }

      return result.toString();
    } on SocketException {
      throw Exception('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالخادم.');
    } on FormatException {
      throw Exception('استجابة الخادم غير صالحة.');
    } on http.ClientException catch (e) {
      throw Exception('خطأ في الاتصال: ${e.message}');
    } finally {
      client.close();
    }
  }

  void _validate() {
    if (endpoint.trim().isEmpty) {
      throw Exception('لم يتم إدخال عنوان API. افتح الإعدادات وأدخل الرابط.');
    }
    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج.');
    }
  }

  String _extractDelta(dynamic data) {
    if (data is! Map) return '';

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return '';

    final first = choices.first;
    if (first is! Map) return '';

    final delta = first['delta'];
    if (delta is Map) {
      final content = delta['content'];
      if (content is String) return content;
    }

    final message = first['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content;
    }

    final text = first['text'];
    if (text is String) return text;

    return '';
  }

  String _extractContent(String raw) {
    if (raw.trim().isEmpty) return '';

    try {
      final data = jsonDecode(raw);
      if (data is! Map) return raw;

      // OpenAI / OpenRouter / NVIDIA / Gateway
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map) {
            final content = message['content'];
            if (content is String) return content;

            // content قد يكون قائمة (vision)
            if (content is List) {
              final buf = StringBuffer();
              for (final part in content) {
                if (part is Map && part['text'] is String) {
                  buf.write(part['text']);
                } else if (part is String) {
                  buf.write(part);
                }
              }
              if (buf.isNotEmpty) return buf.toString();
            }
          }

          final text = first['text'];
          if (text is String) return text;
        }
      }

      // Google Gemini style
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final candidate = candidates.first;
        if (candidate is Map) {
          final content = candidate['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List) {
              final result = StringBuffer();
              for (final part in parts) {
                if (part is Map && part['text'] is String) {
                  result.write(part['text']);
                }
              }
              if (result.isNotEmpty) return result.toString();
            }
          }
        }
      }

      // بعض الـ Gateways ترجع النص مباشرة
      final text = data['text'] ?? data['output'] ?? data['response'];
      if (text is String && text.isNotEmpty) return text;

      return _extractError(raw);
    } catch (_) {
      return raw;
    }
  }

  String _extractError(String raw) {
    if (raw.trim().isEmpty) return 'استجابة فارغة من الخادم';

    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        final error = data['error'];
        if (error is String) return error;
        if (error is Map) {
          final message = error['message'];
          if (message is String) return message;
          final detail = error['detail'];
          if (detail is String) return detail;
        }
        final message = data['message'];
        if (message is String) return message;
        final detail = data['detail'];
        if (detail is String) return detail;
      }
    } catch (_) {}

    if (raw.length > 800) return '${raw.substring(0, 800)}...';
    return raw;
  }

  /// اختبار الاتصال السريع — يرجع null عند النجاح أو رسالة الخطأ
  Future<String?> testConnectionDetailed() async {
    try {
      final result = await sendMessage(
        messages: const [
          {'role': 'user', 'content': 'Reply with OK only.'},
        ],
        maxTokens: 16,
      );
      if (result.trim().isEmpty) {
        return 'استجابة فارغة من الخادم';
      }
      return null; // نجاح
    } catch (e) {
      return e.toString();
    }
  }

  Future<bool> testConnection() async {
    final err = await testConnectionDetailed();
    return err == null;
  }
}
