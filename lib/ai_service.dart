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

  String normalizeEndpoint(String value) {
    var url = value.trim();

    if (url.isEmpty) {
      return url;
    }

    // Remove trailing slash.
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // Already a chat completions endpoint.
    if (url.endsWith('/chat/completions')) {
      return url;
    }

    // Common API base paths.
    if (url.endsWith('/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api/v1')) {
      return '$url/chat/completions';
    }

    if (url.endsWith('/api')) {
      return '$url/v1/chat/completions';
    }

    // Generic OpenAI-compatible endpoint.
    return '$url/v1/chat/completions';
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    // OpenRouter recommended headers.
    if (provider.toLowerCase() == 'openrouter' ||
        endpoint.toLowerCase().contains('openrouter.ai')) {
      headers['HTTP-Referer'] = 'https://github.com/tayebi7/whah-ai';
      headers['X-Title'] = 'WHAH AI';
    }

    return headers;
  }

  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    bool stream = true,
  }) async {
    final url = normalizeEndpoint(endpoint);

    if (url.isEmpty) {
      throw Exception('لم يتم إدخال عنوان API');
    }

    if (model.trim().isEmpty) {
      throw Exception('لم يتم إدخال اسم النموذج');
    }

    final body = jsonEncode({
      'model': model.trim(),
      'messages': messages,
      'stream': stream,
    });

    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse(url),
      );

      request.headers.addAll(_headers());
      request.body = body;

      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();

        throw Exception(
          'خطأ ${response.statusCode}: ${_extractError(errorBody)}',
        );
      }

      if (!stream) {
        final data = await response.stream.bytesToString();

        return _extractContentFromJson(data);
      }

      return await _readStreamingResponse(response);
    } on SocketException {
      throw Exception(
        'تعذر الاتصال بالخادم. تحقق من الإنترنت وعنوان API.',
      );
    } on TimeoutException {
      throw Exception(
        'انتهت مهلة الاتصال بالخادم.',
      );
    } on FormatException catch (e) {
      throw Exception(
        'استجابة الخادم غير صالحة: ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'خطأ في الاتصال: ${e.message}',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _readStreamingResponse(
    http.StreamedResponse response,
  ) async {
    final buffer = StringBuffer();
    final completer = Completer<String>();

    StreamSubscription<String>? subscription;

    subscription = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        final text = line.trim();

        if (text.isEmpty) {
          return;
        }

        if (text == 'data: [DONE]' ||
            text == '[DONE]') {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }

          subscription?.cancel();
          return;
        }

        if (!text.startsWith('data:')) {
          return;
        }

        final data = text.substring(5).trim();

        if (data.isEmpty || data == '[DONE]') {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }

          subscription?.cancel();
          return;
        }

        try {
          final json = jsonDecode(data);

          final content = _extractDelta(json);

          if (content.isNotEmpty) {
            buffer.write(content);
          }
        } catch (_) {
          // Some gateways may return non-standard SSE data.
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.toString());
        }
      },
      cancelOnError: true,
    );

    return completer.future;
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

    // OpenAI / OpenRouter streaming format.
    final delta = first['delta'];

    if (delta is Map) {
      final content = delta['content'];

      if (content is String) {
        return content;
      }
    }

    // Some APIs return message.content.
    final message = first['message'];

    if (message is Map) {
      final content = message['content'];

      if (content is String) {
        return content;
      }
    }

    // Some gateways use text directly.
    final text = first['text'];

    if (text is String) {
      return text;
    }

    return '';
  }

  String _extractContentFromJson(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }

    dynamic json;

    try {
      json = jsonDecode(raw);
    } catch (_) {
      return raw;
    }

    if (json is! Map) {
      return raw;
    }

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

    // Gemini-like response compatibility.
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

        final message = json['message'];

        if (message is String) {
          return message;
        }

        final detail = json['detail'];

        if (detail is String) {
          return detail;
        }
      }
    } catch (_) {
      // Return raw text below.
    }

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
        stream: false,
      );

      return result.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
