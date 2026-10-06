import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// خدمة اتصال سريعة بمزودي OpenAI-compatible API
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

  static final http.Client _sharedClient = http.Client();

  bool get _isPollinations {
    final p = provider.toLowerCase();
    final e = endpoint.toLowerCase();
    return p.contains('pollinations') || e.contains('pollinations.ai');
  }

  String get _url {
    var url = endpoint.trim().replaceAll(RegExp(r'\s+'), '');

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (url.contains('/chat/completions')) {
      return url;
    }

    if (url.contains('generativelanguage.googleapis.com')) {
      if (url.endsWith('/openai')) {
        return '$url/chat/completions';
      }
      if (url.endsWith('/v1beta')) {
        return '$url/openai/chat/completions';
      }
    }

    if (url.contains('openrouter.ai') && !url.endsWith('/v1')) {
      if (url.endsWith('/api')) {
        return '$url/v1/chat/completions';
      }
      return '$url/api/v1/chat/completions';
    }

    if (url.contains('pollinations.ai')) {
      // Pollinations OpenAI-compatible
      if (url.contains('/v1')) {
        return '$url/chat/completions';
      }
      return 'https://text.pollinations.ai/openai';
    }

    if (url.endsWith('/v1') || url.endsWith('/api/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api')) {
      return '$url/v1/chat/completions';
    }

    return '$url/v1/chat/completions';
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Connection': 'keep-alive',
    };

    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
      headers['x-api-key'] = key;
    }

    final p = provider.toLowerCase();
    final ep = endpoint.toLowerCase();

    if (p.contains('openrouter') || ep.contains('openrouter.ai')) {
      headers['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'WHAH AI';
    }

    return headers;
  }

  void _validate() {
    if (endpoint.trim().isEmpty && !_isPollinations) {
      throw Exception('لم يتم إدخال عنوان API.');
    }
    if (model.trim().isEmpty && !_isPollinations) {
      throw Exception('لم يتم إدخال اسم النموذج.');
    }
    // Pollinations و المزودون بدون مفتاح: لا نفرض API Key
    final needsKey = !_isPollinations &&
        !provider.contains('بدون مفتاح') &&
        !provider.toLowerCase().contains('no key');
    if (needsKey && apiKey.trim().isEmpty) {
      // لا نرمي هنا دائماً — بعض السيرفرات المحلية بلا مفتاح
    }
  }

  Future<String> sendMessage({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _validate();

    // مسار Pollinations البسيط بدون مفتاح
    if (_isPollinations && endpoint.contains('text.pollinations.ai') &&
        !endpoint.contains('openai')) {
      return _sendPollinationsSimple(messages, timeout);
    }

    final body = <String, dynamic>{
      'model': model.trim().isEmpty ? 'openai' : model.trim(),
      'messages': messages,
      'stream': false,
      'temperature': temperature,
    };
    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }

    final url = _url;

    try {
      final response = await _sharedClient
          .post(
            Uri.parse(url),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = _extractError(response.body);
        throw Exception(
          'خطأ ${response.statusCode}\nالرابط: $url\n$err',
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
      throw Exception('انتهت مهلة الاتصال (${timeout.inSeconds} ث).');
    } on FormatException {
      throw Exception('عنوان API غير صالح: $url');
    } on http.ClientException catch (e) {
      throw Exception('خطأ في الاتصال: ${e.message}');
    }
  }

  /// Pollinations نصي مجاني بدون API Key
  Future<String> _sendPollinationsSimple(
    List<Map<String, dynamic>> messages,
    Duration timeout,
  ) async {
    final last = messages.isNotEmpty ? messages.last['content']?.toString() ?? '' : '';
    final prompt = last.isEmpty ? 'Hello' : last;
    final uri = Uri.parse(
      'https://text.pollinations.ai/${Uri.encodeComponent(prompt)}',
    );

    try {
      final response = await _sharedClient.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('خطأ ${response.statusCode} من Pollinations');
      }
      final text = response.body.trim();
      if (text.isEmpty) throw Exception('استجابة فارغة');
      return text;
    } on SocketException {
      throw Exception('تعذر الاتصال بـ Pollinations.');
    } on TimeoutException {
      throw Exception('انتهت مهلة Pollinations.');
    }
  }

  Future<String> streamMessage({
    required List<Map<String, dynamic>> messages,
    required void Function(String text) onChunk,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    // Pollinations: لا بث — نرسل دفعة واحدة
    if (_isPollinations) {
      final result = await sendMessage(messages: messages, timeout: timeout);
      onChunk(result);
      return result;
    }

    _validate();

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

    try {
      final streamed = await _sharedClient.send(request).timeout(timeout);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final errorBody = await streamed.stream.bytesToString();
        throw Exception(
          'خطأ ${streamed.statusCode}\nالرابط: $_url\n${_extractError(errorBody)}',
        );
      }

      final result = StringBuffer();

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final value = line.trim();
        if (value.isEmpty) continue;
        if (value == 'data: [DONE]' || value == '[DONE]') break;

        var data = value;
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
        } catch (_) {}
      }

      return result.toString();
    } on SocketException {
      throw Exception('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    } on TimeoutException {
      throw Exception('انتهت مهلة البث.');
    } on FormatException {
      throw Exception('استجابة غير صالحة من الخادم.');
    } on http.ClientException catch (e) {
      throw Exception('خطأ في الاتصال: ${e.message}');
    }
  }

  Future<String> sendSmart({
    required List<Map<String, dynamic>> messages,
    required void Function(String text) onChunk,
    double temperature = 0.7,
    bool preferStream = true,
  }) async {
    var gotStreamData = false;

    if (preferStream && !_isPollinations) {
      try {
        final streamed = await streamMessage(
          messages: messages,
          onChunk: (chunk) {
            gotStreamData = true;
            onChunk(chunk);
          },
          temperature: temperature,
          timeout: const Duration(seconds: 75),
        );
        if (streamed.trim().isNotEmpty) return streamed;
      } catch (_) {
        if (gotStreamData) return '';
      }
    }

    final result = await sendMessage(
      messages: messages,
      temperature: temperature,
      timeout: const Duration(seconds: 55),
    );
    if (result.isNotEmpty) onChunk(result);
    return result;
  }

  Future<String?> testConnectionDetailed() async {
    try {
      final result = await sendMessage(
        messages: const [
          {'role': 'user', 'content': 'Hi'},
        ],
        maxTokens: 5,
        temperature: 0,
        timeout: const Duration(seconds: 15),
      );
      if (result.trim().isEmpty) return 'استجابة فارغة من الخادم';
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<bool> testConnection() async {
    return (await testConnectionDetailed()) == null;
  }

  String _extractDelta(dynamic data) {
    if (data is! Map) return '';
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';

    final delta = first['delta'];
    if (delta is Map && delta['content'] is String) {
      return delta['content'] as String;
    }
    final message = first['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    if (first['text'] is String) return first['text'] as String;
    return '';
  }

  String _extractContent(String raw) {
    if (raw.trim().isEmpty) return '';
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return raw;

      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map) {
            final content = message['content'];
            if (content is String) return content;
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
          if (first['text'] is String) return first['text'] as String;
        }
      }

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
          if (error['message'] is String) return error['message'] as String;
          if (error['detail'] is String) return error['detail'] as String;
          if (error['code'] != null) {
            return '${error['code']}: ${error['message'] ?? error}';
          }
        }
        if (data['message'] is String) return data['message'] as String;
      }
    } catch (_) {}
    if (raw.length > 400) return '${raw.substring(0, 400)}...';
    return raw;
  }
}
