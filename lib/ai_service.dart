import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

  String get _url {
    var url = endpoint.trim();

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

  Map<String, String> get _headers {
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

  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    bool stream = false,
  }) async {
    if (endpoint.trim().isEmpty) {
      throw Exception('لم يتم إدخال عنوان API');
    }

    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج');
    }

    final client = http.Client();

    try {
      final response = await client
          .post(
            Uri.parse(_url),
            headers: _headers,
            body: jsonEncode({
              'model': model.trim(),
              'messages': messages,
              'stream': stream,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'خطأ ${response.statusCode}: ${_extractError(response.body)}',
        );
      }

      return _extractContent(response.body);
    } on SocketException {
      throw Exception('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالخادم.');
    } on FormatException {
      throw Exception('عنوان API غير صالح.');
    } on http.ClientException catch (e) {
      throw Exception('خطأ في الاتصال: ${e.message}');
    } finally {
      client.close();
    }
  }

  Future<String> streamMessage({
    required List<Map<String, String>> messages,
    required void Function(String text) onChunk,
  }) async {
    if (endpoint.trim().isEmpty) {
      throw Exception('لم يتم إدخال عنوان API');
    }

    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج');
    }

    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse(_url),
      );

      final headers = Map<String, String>.from(_headers);
      headers['Accept'] = 'text/event-stream';

      request.headers.addAll(headers);

      request.body = jsonEncode({
        'model': model.trim(),
        'messages': messages,
        'stream': true,
      });

      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();

        throw Exception(
          'خطأ ${response.statusCode}: ${_extractError(errorBody)}',
        );
      }

      final result = StringBuffer();

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
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
          final decoded = jsonDecode(data);
          final chunk = _extractDelta(decoded);

          if (chunk.isNotEmpty) {
            result.write(chunk);
            onChunk(chunk);
          }
        } catch (_) {
          // بعض الخوادم ترسل أسطر SSE غير JSON.
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

  String _extractDelta(dynamic data) {
    if (data is! Map) {
      return '';
    }

    final choices = data['choices'];

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
      final data = jsonDecode(raw);

      if (data is! Map) {
        return raw;
      }

      final choices = data['choices'];

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

              if (result.isNotEmpty) {
                return result.toString();
              }
            }
          }
        }
      }

      return _extractError(raw);
    } catch (_) {
      return raw;
    }
  }

  String _extractError(String raw) {
    if (raw.trim().isEmpty) {
      return 'استجابة فارغة من الخادم';
    }

    try {
      final data = jsonDecode(raw);

      if (data is Map) {
        final error = data['error'];

        if (error is String) {
          return error;
        }

        if (error is Map) {
          final message = error['message'];

          if (message is String) {
            return message;
          }

          final detail = error['detail'];

          if (detail is String) {
            return detail;
          }
        }

        final message = data['message'];

        if (message is String) {
          return message;
        }

        final detail = data['detail'];

        if (detail is String) {
          return detail;
        }
      }
    } catch (_) {}

    if (raw.length > 1000) {
      return raw.substring(0, 1000);
    }

    return raw;
  }

  Future<bool> testConnection() async {
    try {
      final result = await sendMessage(
        messages: const [
          {
            'role': 'user',
            'content': 'Reply with OK only.',
          },
        ],
      );

      return result.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
