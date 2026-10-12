import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_provider_router.dart';

abstract interface class GeminiModelCatalog {
  Future<List<GeminiModelInfo>> listModels({required String apiKey});
}

class GeminiModelInfo {
  const GeminiModelInfo({
    required this.id,
    required this.displayName,
    this.inputTokenLimit,
    this.outputTokenLimit,
  });

  /// Model name without the `models/` API prefix.
  final String id;
  final String displayName;
  final int? inputTokenLimit;
  final int? outputTokenLimit;
}

class GeminiRestProvider implements CloudAiProvider, GeminiModelCatalog {
  GeminiRestProvider({HttpClient Function()? clientFactory, Uri? apiBaseUri})
    : _clientFactory = clientFactory ?? HttpClient.new,
      _apiBaseUri = apiBaseUri ?? Uri.parse(defaultEndpoint);

  static const recommendedModelId = 'gemini-3.5-flash-lite';
  static const defaultEndpoint =
      'https://generativelanguage.googleapis.com/v1beta';

  static const _apiKeyHeader = 'x-goog-api-key';
  static const _maxOutputTokens = 512;
  static const _connectTimeout = Duration(seconds: 20);
  static const _responseTimeout = Duration(seconds: 60);

  final HttpClient Function() _clientFactory;
  final Uri _apiBaseUri;

  @override
  Future<List<GeminiModelInfo>> listModels({required String apiKey}) async {
    final result = <GeminiModelInfo>[];
    final seenPageTokens = <String>{};
    String? pageToken;
    do {
      final response = await _requestJson(
        uri: _modelsUri(_apiBaseUri, pageToken: pageToken),
        method: 'GET',
        apiKey: apiKey,
      );
      if (response is! Map) {
        throw const CloudProviderResponseException();
      }

      final models = response['models'];
      if (models is! List) {
        throw const CloudProviderResponseException();
      }
      result.addAll([
        for (final model in models)
          if (_isGenerationModel(model)) _modelInfo(model as Map),
      ]);

      final nextPageToken = response['nextPageToken'];
      if (nextPageToken != null && nextPageToken is! String) {
        throw const CloudProviderResponseException();
      }
      pageToken = nextPageToken is String && nextPageToken.isNotEmpty
          ? nextPageToken
          : null;
      if (pageToken != null && !seenPageTokens.add(pageToken)) {
        throw const CloudProviderResponseException();
      }
    } while (pageToken != null);

    return result;
  }

  @override
  Future<String> complete({
    required String prompt,
    required Uri endpoint,
    required String model,
    required String apiKey,
    required int maxTokens,
  }) async {
    final modelId = model.startsWith('models/')
        ? model.substring('models/'.length)
        : model;
    if (modelId.trim().isEmpty) {
      throw const CloudProviderConfigurationException();
    }

    final baseUri = _baseUriFor(endpoint);
    final response = await _requestJson(
      uri: _generateUri(baseUri, modelId),
      method: 'POST',
      apiKey: apiKey,
      payload: {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens.clamp(1, _maxOutputTokens).toInt(),
          if (prompt.contains('только JSON'))
            'responseMimeType': 'application/json',
        },
      },
    );
    return _candidateText(response);
  }

  Future<dynamic> _requestJson({
    required Uri uri,
    required String method,
    required String apiKey,
    Object? payload,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const CloudProviderConfigurationException();
    }

    final client = _clientFactory();
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_connectTimeout);
      request.followRedirects = false;
      request.headers.set(_apiKeyHeader, apiKey);
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
      }

      final response = await request.close().timeout(_responseTimeout);
      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        final statusCode = response.statusCode;
        await response.drain<void>();
        throw CloudProviderRequestException(statusCode);
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_responseTimeout);
      return jsonDecode(body);
    } on CloudProviderRequestException {
      rethrow;
    } on CloudProviderConfigurationException {
      rethrow;
    } on CloudProviderResponseException {
      rethrow;
    } on TimeoutException {
      throw const CloudProviderUnavailableException();
    } on SocketException {
      throw const CloudProviderUnavailableException();
    } on HttpException {
      throw const CloudProviderUnavailableException();
    } on FormatException {
      throw const CloudProviderResponseException();
    } finally {
      client.close(force: true);
    }
  }

  Uri _modelsUri(Uri baseUri, {String? pageToken}) => _appendPath(
    baseUri,
    'models',
    queryParameters: {
      'pageSize': '1000',
      ...?(pageToken == null ? null : {'pageToken': pageToken}),
    },
  );

  Uri _generateUri(Uri baseUri, String modelId) =>
      _appendPath(baseUri, 'models/$modelId:generateContent');

  Uri _appendPath(
    Uri baseUri,
    String suffix, {
    Map<String, String>? queryParameters,
  }) {
    final prefix = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    return baseUri.replace(
      path: '$prefix/$suffix',
      queryParameters: queryParameters ?? const {},
      fragment: '',
    );
  }

  Uri _baseUriFor(Uri endpoint) {
    final defaultUri = Uri.parse(defaultEndpoint);
    final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    if (endpoint.scheme != defaultUri.scheme ||
        endpoint.host != defaultUri.host ||
        endpoint.port != defaultUri.port ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        path != defaultUri.path) {
      throw const CloudProviderConfigurationException();
    }
    return _apiBaseUri;
  }

  bool _isGenerationModel(Object? value) {
    if (value is! Map) return false;
    final methods = value['supportedGenerationMethods'];
    return methods is List && methods.contains('generateContent');
  }

  GeminiModelInfo _modelInfo(Map<dynamic, dynamic> value) {
    final rawName = value['name'];
    if (rawName is! String || rawName.trim().isEmpty) {
      throw const CloudProviderResponseException();
    }
    final id = rawName.startsWith('models/')
        ? rawName.substring('models/'.length)
        : rawName;
    final displayName = value['displayName'];
    return GeminiModelInfo(
      id: id,
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName
          : id,
      inputTokenLimit: _optionalInt(value['inputTokenLimit']),
      outputTokenLimit: _optionalInt(value['outputTokenLimit']),
    );
  }

  int? _optionalInt(Object? value) => value is int ? value : null;

  String _candidateText(dynamic response) {
    if (response is! Map) throw const CloudProviderResponseException();
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      throw const CloudProviderResponseException();
    }
    final content = (candidates.first as Map)['content'];
    if (content is! Map) throw const CloudProviderResponseException();
    final parts = content['parts'];
    if (parts is! List) throw const CloudProviderResponseException();

    final text = parts
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join()
        .trim();
    if (text.isEmpty) throw const CloudProviderResponseException();
    return text;
  }
}
