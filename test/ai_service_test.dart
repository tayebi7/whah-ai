import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whah_ai/ai_service.dart';
import 'package:whah_ai/models.dart';

http.Response okJson(String text) => http.Response(
      jsonEncode({
        'choices': [
          {'message': {'content': text}}
        ]
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUp(ChatRouter.resetState);

  test('sanitizes key header and decodes arabic utf8 without charset', () async {
    late http.Request seen;
    AIService.client = MockClient((req) async {
      seen = req;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {'message': {'content': 'مرحباً'}}
            ]
          })),
          200,
          headers: {'content-type': 'application/json'});
    });
    final p = ProviderConfig(
        name: 'a', endpoint: 'api.x.com', apiKey: ' Bearer sk-1\n2 ', model: 'm');
    final r = await AIService(p).complete([const LlmMessage('user', 'hi')]);
    expect(r, 'مرحباً');
    expect(seen.headers['Authorization'], 'Bearer sk-12');
    expect(seen.url.toString(), 'https://api.x.com/v1/chat/completions');
  });

  test('falls back to alternate url on 404', () async {
    final urls = <String>[];
    AIService.client = MockClient((req) async {
      urls.add(req.url.toString());
      if (urls.length == 1) return http.Response('{"error":"nf"}', 404);
      return okJson('ok');
    });
    final p = ProviderConfig(name: 'a', endpoint: 'https://h.com', apiKey: 'k', model: 'm');
    expect(await AIService(p).complete([const LlmMessage('user', 'hi')]), 'ok');
    expect(urls.length, 2);
  });

  test('html response gives clear error', () async {
    AIService.client = MockClient((req) async => http.Response('<!DOCTYPE html><html>', 200));
    final p = ProviderConfig(name: 'a', endpoint: 'https://h.com/v1', apiKey: 'k', model: 'm');
    expect(
      () => AIService(p).complete([const LlmMessage('user', 'hi')]),
      throwsA(isA<LlmException>()),
    );
  });

  test('router switches to next provider on failure', () async {
    AIService.client = MockClient((req) async {
      if (req.url.host == 'bad.com') return http.Response('{"error":"quota"}', 429);
      return okJson('from-good');
    });
    final bad = ProviderConfig(name: 'bad', endpoint: 'https://bad.com/v1', apiKey: 'k', model: 'm');
    final good = ProviderConfig(name: 'good', endpoint: 'https://good.com/v1', apiKey: 'k', model: 'm');
    final res = await ChatRouter.run(
      providers: [bad, good],
      messages: const [LlmMessage('user', 'hi')],
      stream: false,
    );
    expect(res.text, 'from-good');
    expect(res.provider, 'good');
  });

  test('router fails with summary when all fail', () async {
    AIService.client = MockClient((req) async => http.Response('{"error":"x"}', 401));
    final a = ProviderConfig(name: 'A', endpoint: 'https://a.com/v1', apiKey: 'k', model: 'm');
    expect(
      () => ChatRouter.run(providers: [a], messages: const [LlmMessage('user', 'hi')], stream: false),
      throwsA(isA<LlmException>()),
    );
  });

  test('vision request sends image_url and uses vision model', () async {
    late Map body;
    AIService.client = MockClient((req) async {
      body = jsonDecode(req.body) as Map;
      return okJson('saw');
    });
    final p = ProviderConfig(
        name: 'a', endpoint: 'https://h.com/v1', apiKey: 'k', model: 'text', visionModel: 'vis');
    await AIService(p).complete(
      [const LlmMessage('user', 'what', images: [ImagePart('image/png', 'AAA')])],
      vision: true,
    );
    expect(body['model'], 'vis');
    final content = (body['messages'] as List).first['content'] as List;
    expect(content[1]['image_url']['url'], 'data:image/png;base64,AAA');
  });
}
