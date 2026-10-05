import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AIService {
  final String endpoint;
  final String apiKey;
  final String model;
  final String provider;

  AIService({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.provider = 'custom',
  });

  static Future<String> sendMessage({
    required Map<String, dynamic> settings,
    required List<Map<String, String>> messages,
  }) async {
    final service = AIService(
      endpoint: (settings['endpoint'] ?? '').toString(),
      apiKey: (settings['apiKey'] ?? '').toString(),
      model: (settings['model'] ?? '').toString(),
      provider: (settings['provider'] ?? 'custom').toString(),
    );

    return service.send(
      messages: messages,
      stream: false,
    );
  }

  static Future<String> streamMessage({
    required Map<String, dynamic> settings,
    required List<Map<String, String>> messages,
    required void Function(String text) onChunk,
  }) async {
    final service = AIService(
      endpoint: (settings['endpoint'] ?? '').toString(),
      apiKey: (settings['apiKey'] ?? '').toString(),
      model: (settings['model'] ?? '').toString(),
      provider: (settings['provider'] ?? 'custom').toString(),
    );

    return service.sendStream(
      messages: messages,
      onChunk: onChunk,
    );
  }

  String _normalizeEndpoint(String value) {
    var url = value.trim();

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (url.endsWith('/chat/completions')) {
      return url;
    }

    if (url.endsWith('/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api')) {
      return '$url/v1/chat/completions';
    }

    return '$url/v1/chat/completions';
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    if (provider.toLowerCase() == 'openrouter' ||
        endpoint.toLowerCase().contains('openrouter.ai')) {
      headers['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'WHAH AI';
    }

    return headers;
  }

  Future<String> send({
    required List<Map<String, String>> messages,
    bool stream = false,
  }) async {
    final url = _normalizeEndpoint(endpoint);

    if (url.isEmpty) {
      throw Exception('لم يتم إدخال عنوان API');
    }

    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج');
    }

    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse(url),
      );

      request.headers.addAll(_headers());

      request.body = jsonEncode({
        'model': model.trim(),
        'messages': messages,
        'stream': stream,
      });

      final response = await client.send(request);

      final body = await response.stream.bytesToString();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'خطأ ${response.statusCode}: ${_extractError(body)}',
        );
      }

      return _extractContent(body);
    } on SocketException {
      throw Exception(
        'تعذر الاتصال بالخادم. تحقق من الإنترنت وعنوان API.',
      );
    } on FormatException {
      throw Exception(
        'عنوان API غير صالح.',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'خطأ في الاتصال: ${e.message}',
      );
    } finally {
      client.close();
    }
  }

  Future<String> sendStream({
    required List<Map<String, String>> messages,
    required void Function(String text) onChunk,
  }) async {
    final url = _normalizeEndpoint(endpoint);

    if (url.isEmpty) {
      throw Exception('لم يتم إدخال عنوان API');
    }

    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج');
    }

    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse(url),
      );

      final headers = _headers();

      headers['Accept'] = 'text/event-stream';

      request.headers.addAll(headers);

      request.body = jsonEncode({
        'model': model.trim(),
        'messages': messages,
        'stream': true,
      });

      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = await response.stream.bytesToString();

        throw Exception(
          'خطأ ${response.statusCode}: ${_extractError(error)}',
        );
      }

      final result = StringBuffer();

      await for (final line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        final value = line.trim();

        if (value.isEmpty) {
          continue;
        }

        if (value == 'data: [DONE]' || value == '[DONE]') {
          break;
        }

        if (!value.startsWith('data:')) {
          continue;
        }

        final data = value.substring(5).trim();

        if (data.isEmpty || data == '[DONE]') {
          break;
        }

        try {
          final json = jsonDecode(data);

          final text = _extractDelta(json);

          if (text.isNotEmpty) {
            result.write(text);
            onChunk(text);
          }
        } catch (_) {
          // تجاهل أجزاء SSE غير الصالحة
        }
      }

      return result.toString();
    } on SocketException {
      throw Exception(
        'تعذر الاتصال بالخادم. تحقق من الإنترنت.',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'خطأ في الاتصال: ${e.message}',
      );
    } finally {
      client.close();
    }
  }

  String _extractDelta(dynamic json) {
    if (json is! Map) {
      return '';
    }

    final choices = json['choices'];

    if (choices is! List || choices.isEmpty) {
      return '';
    }

    final first = choices.first;

    if (first is! Map) {
      return '';
    }

    final delta = first['delta'];

    if (delta is Map) {
      final content = delta['content'];

      if (content is String) {
        return content;
      }
    }

    final message = first['message'];

    if (message is Map) {
      final content = message['content'];

      if (content is String) {
        return content;
      }
    }

    final text = first['text'];

    if (text is String) {
      return text;
    }

    return '';
  }

  String _extractContent(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }

    try {
      final json = jsonDecode(raw);

      if (json is Map) {
        final choices = json['choices'];

        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;

          if (first is Map) {
            final message = first['message'];

            if (message is Map) {
              final content = message['content'];

              if (content is String) {
                return content;
              }
            }

            final text = first['text'];

            if (text is String) {
              return text;
            }
          }
        }

        final candidates = json['candidates'];

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

                if (result.isNotEmpty) {
                  return result.toString();
                }
              }
            }
          }
        }
      }
    } catch (_) {
      return raw;
    }

    return _extractError(raw);
  }

  String _extractError(String raw) {
    if (raw.trim().isEmpty) {
      return 'استجابة فارغة من الخادم';
    }

    try {
      final json = jsonDecode(raw);

      if (json is Map) {
        final error = json['error'];

        if (error is String) {
          return error;
        }

        if (
