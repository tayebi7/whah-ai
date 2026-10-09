import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whah_ai/ai_service.dart';
import 'package:whah_ai/intent.dart';
import 'package:whah_ai/models.dart';
import 'package:whah_ai/net_utils.dart';

void main() {
  group('Sanitize', () {
    test('key strips Bearer, quotes, spaces and non-ascii', () {
      expect(Sanitize.key('  "Bearer sk-abc 123\n"  '), 'sk-abc123');
      expect(Sanitize.key('sk-​xyz'), 'sk-xyz');
      expect(Sanitize.key('Authorization: Bearer abc'), 'abc');
    });
    test('url adds scheme and removes junk', () {
      expect(Sanitize.url('api.groq.com/openai/v1 '), 'https://api.groq.com/openai/v1');
      expect(Sanitize.url('https://https://x.com/v1'), 'https://x.com/v1');
      expect(Sanitize.url('localhost:11434/v1'), 'http://localhost:11434/v1');
    });
    test('provider json is parsed', () {
      final m = Sanitize.parseProviderJson('{"base_url":"https://a.com/v1","api_key":"k","model":"m"}')!;
      expect(m['endpoint'], 'https://a.com/v1');
      expect(m['apiKey'], 'k');
    });
  });

  group('ApiEndpoints', () {
    test('full chat url / json suffix / missing version', () {
      expect(ApiEndpoints.parse('https://api.groq.com/openai/v1/chat/completions').chatUrl,
          'https://api.groq.com/openai/v1/chat/completions');
      expect(ApiEndpoints.parse('https://x.com/v1/models.json').chatUrl,
          'https://x.com/v1/chat/completions');
      final e = ApiEndpoints.parse('x.com');
      expect(e.chatUrl, 'https://x.com/v1/chat/completions');
      expect(e.alternates, ['https://x.com/chat/completions']);
      expect(ApiEndpoints.parse('https://openrouter.ai/api').chatUrl,
          'https://openrouter.ai/api/v1/chat/completions');
      expect(ApiEndpoints.parse('https://generativelanguage.googleapis.com').chatUrl,
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');
      expect(ApiEndpoints.parse('https://api.anthropic.com/v1/messages').chatUrl,
          'https://api.anthropic.com/v1/messages');
      expect(ApiEndpoints.parse('').error, isNotNull);
    });
  });

  group('ResponseParser', () {
    test('openai / anthropic / ollama / sse', () {
      expect(ResponseParser.extractText('{"choices":[{"message":{"content":"مرحبا"}}]}'), 'مرحبا');
      expect(ResponseParser.extractText('{"content":[{"type":"text","text":"hi"}]}'), 'hi');
      expect(ResponseParser.extractText('{"message":{"content":"yo"}}'), 'yo');
      expect(
          ResponseParser.extractText(
              'data: {"choices":[{"delta":{"content":"a"}}]}\n\ndata: {"choices":[{"delta":{"content":"b"}}]}\n\ndata: [DONE]'),
          'ab');
    });
  });

  group('Intent', () {
    test('detects main intents', () {
      expect(IntentDetector.detect('ولّد لي صورة قطة على القمر').intent, Intent.imageGen);
      expect(IntentDetector.detect('اصنع فيديو لغروب الشمس').intent, Intent.videoGen);
      expect(IntentDetector.detect('حلل هذه الصورة', hasImages: true).intent, Intent.vision);
      expect(IntentDetector.detect('راجع هذه الفاتورة وتأكد من الضريبة TVA').intent, Intent.finance);
      expect(IntentDetector.detect('اكتب كابشن لمنشور انستغرام مع هاشتاق').intent, Intent.social);
      expect(IntentDetector.detect('التطبيق لا يعمل ويظهر error exception').intent, Intent.problem);
      expect(IntentDetector.detect('ما هي عاصمة فرنسا؟').intent, Intent.chat);
      expect(IntentDetector.detect('اكتب لي برومبت لصورة قطة').intent, isNot(Intent.imageGen));
    });
  });

  group('ChatRouter', () {
    setUp(ChatRouter.resetState);

    ProviderConfig prov(String n) =>
        ProviderConfig(name: n, endpoint: 'https://$n.test/v1', apiKey: 'k', model: 'm');

    test('fails over to next provider on 429 and 401', () async {
      AIService.client = MockClient((req) async {
        if (req.url.host == 'a.test') return http.Response('{"error":{"message":"rate"}}', 429);
        if (req.url.host == 'b.test') return http.Response('{"error":"bad key"}', 401);
        return http.Response(
            utf8.decode(utf8.encode('{"choices":[{"message":{"content":"تمام"}}]}')), 200,
            headers: {'content-type': 'application/json'});
      });
      final r = await ChatRouter.run(
        providers: [prov('a'), prov('b'), prov('c')],
        messages: const [LlmMessage('user', 'hi')],
        stream: false,
      );
      expect(r.text, 'تمام');
      expect(r.provider, 'c');
    });

    test('404 retries URL without /v1', () async {
      final seen = <String>[];
      AIService.client = MockClient((req) async {
        seen.add(req.url.path);
        if (req.url.path == '/v1/chat/completions') return http.Response('nf', 404);
        return http.Response('{"choices":[{"message":{"content":"ok"}}]}', 200);
      });
      final p = ProviderConfig(name: 'n', endpoint: 'n.test', apiKey: 'k', model: 'm');
      final r = await ChatRouter.run(
          providers: [p], messages: const [LlmMessage('user', 'x')], stream: false);
      expect(r.text, 'ok');
      expect(seen, ['/v1/chat/completions', '/chat/completions']);
    });

    test('sends image as data url', () async {
      Map<String, dynamic>? body;
      AIService.client = MockClient((req) async {
        body = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
        return http.Response('{"choices":[{"message":{"content":"ok"}}]}', 200);
      });
      await ChatRouter.run(
        providers: [prov('v')],
        messages: [
          LlmMessage('user', 'what?', images: const [ImagePart('image/png', 'AAAA')])
        ],
        vision: true,
        stream: false,
      );
      final content = (body!['messages'] as List).first['content'] as List;
      expect(content[1]['image_url']['url'], 'data:image/png;base64,AAAA');
    });

    test('streaming works', () async {
      AIService.client = MockClient.streaming((req, bodyStream) async {
        final sse = 'data: {"choices":[{"delta":{"content":"مر"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"حبا"}}]}\n\ndata: [DONE]\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200,
            headers: {'content-type': 'text/event-stream'});
      });
      final chunks = <String>[];
      final r = await ChatRouter.run(
        providers: [prov('s')],
        messages: const [LlmMessage('user', 'hi')],
        onChunk: chunks.add,
      );
      expect(r.text, 'مرحبا');
      expect(chunks.join(), 'مرحبا');
    });
  });

  test('detectType', () {
    expect(detectType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])).ext, 'png');
    expect(
        detectType(Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])).ext,
        'mp4');
    expect(detectType(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x77, 0x65, 0x62, 0x6D])).ext, 'webm');
  });
}
