import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whah_ai/net_utils.dart';

void main() {
  group('ApiEndpoints.parse', () {
    test('adds https and /v1', () {
      final e = ApiEndpoints.parse('api.example.com');
      expect(e.chatUrl, 'https://api.example.com/v1/chat/completions');
      expect(e.alternates, ['https://api.example.com/chat/completions']);
    });
    test('keeps full chat url', () {
      final e = ApiEndpoints.parse('https://api.groq.com/openai/v1/chat/completions');
      expect(e.chatUrl, 'https://api.groq.com/openai/v1/chat/completions');
    });
    test('strips .json and trailing words', () {
      final e = ApiEndpoints.parse('https://x.com/v1/models.json');
      expect(e.base, 'https://x.com/v1');
    });
    test('openrouter /api', () {
      final e = ApiEndpoints.parse('https://openrouter.ai/api');
      expect(e.chatUrl, 'https://openrouter.ai/api/v1/chat/completions');
    });
    test('gemini host', () {
      final e = ApiEndpoints.parse('https://generativelanguage.googleapis.com');
      expect(e.chatUrl,
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');
    });
    test('anthropic', () {
      final e = ApiEndpoints.parse('https://api.anthropic.com/v1/messages');
      expect(e.format, 'anthropic');
      expect(e.chatUrl, 'https://api.anthropic.com/v1/messages');
    });
    test('pollinations', () {
      final e = ApiEndpoints.parse('https://text.pollinations.ai');
      expect(e.chatUrl, 'https://text.pollinations.ai/openai');
    });
    test('duplicated scheme and spaces', () {
      final e = ApiEndpoints.parse(' "https://https://api.groq.com/openai/v1/" ');
      expect(e.base, 'https://api.groq.com/openai/v1');
    });
    test('local http', () {
      final e = ApiEndpoints.parse('192.168.1.5:8080');
      expect(e.chatUrl.startsWith('http://192.168.1.5:8080'), true);
    });
    test('empty', () {
      expect(ApiEndpoints.parse('  ').error, isNotNull);
    });
  });

  group('Sanitize', () {
    test('key', () {
      expect(Sanitize.key('  "Bearer sk-abc\n123"  '), 'sk-abc123');
      expect(Sanitize.key('sk-​abc'), 'sk-abc');
    });
    test('provider json', () {
      final j = Sanitize.parseProviderJson(
          '{"base_url":"https://a.com/v1","api_key":"k","model":"m"}');
      expect(j!['endpoint'], 'https://a.com/v1');
      expect(j['apiKey'], 'k');
      expect(j['model'], 'm');
    });
  });

  group('ResponseParser', () {
    test('openai', () {
      expect(
          ResponseParser.extractText(
              '{"choices":[{"message":{"content":"مرحبا"}}]}'),
          'مرحبا');
    });
    test('anthropic', () {
      expect(
          ResponseParser.extractText(
              '{"content":[{"type":"text","text":"hi"},{"type":"text","text":"!"}]}'),
          'hi!');
    });
    test('ollama', () {
      expect(ResponseParser.extractText('{"message":{"content":"x"}}'), 'x');
    });
    test('sse body', () {
      const body = 'data: {"choices":[{"delta":{"content":"a"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"b"}}]}\n\ndata: [DONE]\n';
      expect(ResponseParser.extractText(body), 'ab');
    });
    test('error', () {
      expect(ResponseParser.errorFrom('{"error":{"message":"bad key"}}'), 'bad key');
    });
  });

  test('detectType', () {
    expect(detectType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])).ext, 'png');
    expect(detectType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])).ext, 'jpg');
    final mp4 = Uint8List.fromList(
        [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]);
    expect(detectType(mp4).ext, 'mp4');
    expect(detectType(Uint8List.fromList('BMW is a car'.codeUnits)).kind, 'other');
  });
}
