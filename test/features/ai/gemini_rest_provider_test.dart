import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/ai_provider_router.dart';
import 'package:planerka/features/ai/gemini_rest_provider.dart';

typedef _RequestHandler = Future<void> Function(
  HttpRequest request,
  String body,
);

class _CapturedRequest {
  const _CapturedRequest(this.method, this.uri, this.apiKey, this.body);

  final String method;
  final Uri uri;
  final String? apiKey;
  final String body;
}

void main() {
  late HttpServer server;
  late Uri apiBaseUri;
  late _RequestHandler handler;
  late List<_CapturedRequest> requests;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    apiBaseUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/v1beta',
    );
    requests = [];
    handler = (request, _) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{}');
    };
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(
        _CapturedRequest(
          request.method,
          request.uri,
          request.headers.value('x-goog-api-key'),
          body,
        ),
      );
      await handler(request, body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('publishes the approved recommended model id and catalog interface', () {
    expect(GeminiRestProvider.recommendedModelId, 'gemini-3.5-flash-lite');
    expect(
      GeminiRestProvider.defaultEndpoint,
      'https://generativelanguage.googleapis.com/v1beta',
    );
    expect(
      GeminiRestProvider(apiBaseUri: apiBaseUri),
      isA<GeminiModelCatalog>(),
    );
  });

  test(
    'lists only generateContent models and sends key in header only',
    () async {
      handler = (request, body) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemma-4-26b-a4b-it',
                  'displayName': 'Gemma 4 26B',
                  'inputTokenLimit': 1000000,
                  'outputTokenLimit': 8192,
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/gemini-embedding',
                  'displayName': 'Embedding',
                  'supportedGenerationMethods': ['embedContent'],
                },
                {
                  'name': 'models/gemini-no-methods',
                  'supportedGenerationMethods': ['countTokens'],
                },
              ],
            }),
          );
      };

      final catalog = GeminiRestProvider(apiBaseUri: apiBaseUri);
      final models = await catalog.listModels(apiKey: 'test-api-key');

      expect(models, hasLength(1));
      expect(models.single.id, 'gemma-4-26b-a4b-it');
      expect(models.single.displayName, 'Gemma 4 26B');
      expect(models.single.inputTokenLimit, 1000000);
      expect(models.single.outputTokenLimit, 8192);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.uri.path, '/v1beta/models');
      expect(requests.single.uri.queryParameters, {'pageSize': '1000'});
      expect(requests.single.apiKey, 'test-api-key');
      expect(requests.single.body, isEmpty);
      expect(requests.single.uri.toString(), isNot(contains('test-api-key')));
    },
  );

  test('follows nextPageToken until the model catalog is complete', () async {
    var page = 0;
    handler = (request, body) async {
      page++;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(
            page == 1
                ? {
                    'models': [
                      {
                        'name': 'models/gemini-first',
                        'supportedGenerationMethods': ['generateContent'],
                      },
                    ],
                    'nextPageToken': 'page-token-2',
                  }
                : {
                    'models': [
                      {
                        'name': 'models/gemini-second',
                        'supportedGenerationMethods': ['generateContent'],
                      },
                    ],
                  },
          ),
        );
    };

    final models = await GeminiRestProvider(apiBaseUri: apiBaseUri)
        .listModels(apiKey: 'test-api-key');

    expect(models.map((model) => model.id), ['gemini-first', 'gemini-second']);
    expect(requests, hasLength(2));
    expect(requests[0].uri.queryParameters, {'pageSize': '1000'});
    expect(requests[1].uri.queryParameters, {
      'pageSize': '1000',
      'pageToken': 'page-token-2',
    });
    expect(
      requests.every((request) => request.apiKey == 'test-api-key'),
      isTrue,
    );
  });

  test('does not follow a redirect while sending the API key', () async {
    final redirectServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    var redirectedRequestCount = 0;
    String? redirectedApiKey;
    redirectServer.listen((request) async {
      redirectedRequestCount++;
      redirectedApiKey = request.headers.value('x-goog-api-key');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"models":[]}');
      await request.response.close();
    });

    handler = (request, body) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://${InternetAddress.loopbackIPv4.address}:${redirectServer.port}/collect',
        );
    };

    try {
      await expectLater(
        GeminiRestProvider(apiBaseUri: apiBaseUri)
            .listModels(apiKey: 'test-api-key'),
        throwsA(
          isA<CloudProviderRequestException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.found,
          ),
        ),
      );
      expect(redirectedRequestCount, 0);
      expect(redirectedApiKey, isNull);
    } finally {
      await redirectServer.close(force: true);
    }
  });

  test('generates through Gemini endpoint with bounded tokens and joins text parts', () async {
    handler = (request, body) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Первая часть. '},
                    {'text': 'Вторая часть.'},
                  ],
                },
              },
            ],
          }),
        );
    };

    final provider = GeminiRestProvider(apiBaseUri: apiBaseUri);
    final result = await provider.complete(
      prompt: 'Синтетический запрос без личных данных',
      endpoint: Uri.parse(GeminiRestProvider.defaultEndpoint),
      model: 'gemini-3.5-flash-lite',
      apiKey: 'test-api-key',
      maxTokens: 9000,
    );

    expect(result, 'Первая часть. Вторая часть.');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(
      requests.single.uri.path,
      '/v1beta/models/gemini-3.5-flash-lite:generateContent',
    );
    expect(requests.single.apiKey, 'test-api-key');
    expect(requests.single.uri.toString(), isNot(contains('test-api-key')));
    final payload = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(payload['contents'], [
      {
        'role': 'user',
        'parts': [
          {'text': 'Синтетический запрос без личных данных'},
        ],
      },
    ]);
    expect(payload['generationConfig']['maxOutputTokens'], 512);
    expect(
      payload['generationConfig'].containsKey('responseMimeType'),
      isFalse,
    );
  });

  test('requests application/json only when prompt requires JSON', () async {
    handler = (request, body) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"items":[]}'},
                  ],
                },
              },
            ],
          }),
        );
    };

    final provider = GeminiRestProvider(apiBaseUri: apiBaseUri);
    await provider.complete(
      prompt: 'Верни только JSON: {"items":[]}',
      endpoint: Uri.parse(GeminiRestProvider.defaultEndpoint),
      model: GeminiRestProvider.recommendedModelId,
      apiKey: 'test-api-key',
      maxTokens: 32,
    );

    final payload = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(payload['generationConfig']['responseMimeType'], 'application/json');
  });

  test('rejects a non-Google endpoint before sending the API key', () async {
    final provider = GeminiRestProvider(apiBaseUri: apiBaseUri);

    await expectLater(
      provider.complete(
        prompt: 'synthetic prompt',
        endpoint: Uri.parse('https://attacker.example/v1beta'),
        model: 'gemini-3.5-flash-lite',
        apiKey: 'test-api-key',
        maxTokens: 32,
      ),
      throwsA(isA<CloudProviderConfigurationException>()),
    );

    expect(requests, isEmpty);
  });

  test(
    'reports HTTP status without exposing response body or API key',
    () async {
      handler = (request, body) async {
        request.response
          ..statusCode = HttpStatus.tooManyRequests
          ..write('sensitive-response-body test-api-key');
      };

      final provider = GeminiRestProvider(apiBaseUri: apiBaseUri);
      await expectLater(
        provider.listModels(apiKey: 'test-api-key'),
        throwsA(
          isA<CloudProviderRequestException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('sensitive-response-body')),
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('test-api-key')),
              ),
        ),
      );
    },
  );

  test(
    'maps malformed JSON and missing candidate text to safe response errors',
    () async {
      handler = (request, body) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{broken-json');
      };
      final provider = GeminiRestProvider(apiBaseUri: apiBaseUri);
      await expectLater(
        provider.listModels(apiKey: 'test-api-key'),
        throwsA(isA<CloudProviderResponseException>()),
      );

      handler = (request, body) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'candidates': [
                {
                  'content': {'parts': []},
                },
              ],
            }),
          );
      };
      await expectLater(
        provider.complete(
          prompt: 'prompt',
          endpoint: Uri.parse(GeminiRestProvider.defaultEndpoint),
          model: 'gemini-3.5-flash-lite',
          apiKey: 'test-api-key',
          maxTokens: 16,
        ),
        throwsA(isA<CloudProviderResponseException>()),
      );
    },
  );
}
