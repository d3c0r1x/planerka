import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_provider_settings.dart';
import 'model/local_ai_engine.dart';
import 'secure_ai_store.dart';

abstract interface class CloudAiProvider {
  Future<String> complete({
    required String prompt,
    required Uri endpoint,
    required String model,
    required String apiKey,
    required int maxTokens,
  });
}

class AiProviderRouter implements AiTextGenerator {
  const AiProviderRouter({
    required this.local,
    required this.cloud,
    required this.settings,
    required this.secrets,
  });

  final AiTextGenerator local;
  final CloudAiProvider cloud;
  final Future<AiProviderSettings> Function() settings;
  final SecureAiStore secrets;

  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    final configuration = await settings();
    if (configuration.mode == AiProviderMode.local) {
      return local.generate(prompt, maxTokens: maxTokens);
    }
    if (!configuration.allowCloudContext) {
      throw const CloudConsentRequiredException();
    }
    final endpoint = Uri.tryParse(configuration.endpoint.trim());
    if (configuration.provider.trim().isEmpty ||
        configuration.model.trim().isEmpty ||
        endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const CloudProviderConfigurationException();
    }
    final apiKey = await secrets.read(AiProviderSettingsStore.apiKeyName);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const CloudProviderConfigurationException();
    }
    return cloud.complete(
      prompt: prompt,
      endpoint: endpoint,
      model: configuration.model.trim(),
      apiKey: apiKey,
      maxTokens: maxTokens.clamp(1, 512).toInt(),
    );
  }
}

class OpenAiCompatibleGenerator implements CloudAiProvider {
  OpenAiCompatibleGenerator({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<String> complete({
    required String prompt,
    required Uri endpoint,
    required String model,
    required String apiKey,
    required int maxTokens,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(
        const Duration(seconds: 20),
      );
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(
        jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': maxTokens.clamp(1, 512),
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudProviderRequestException(response.statusCode);
      }
      final decoded = jsonDecode(body);
      final choices = decoded is Map ? decoded['choices'] : null;
      final first = choices is List && choices.isNotEmpty ? choices.first : null;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is! String || content.trim().isEmpty) {
        throw const CloudProviderResponseException();
      }
      return content.trim();
    } on CloudProviderRequestException {
      rethrow;
    } on CloudProviderResponseException {
      rethrow;
    } on TimeoutException {
      throw const CloudProviderUnavailableException();
    } on SocketException {
      throw const CloudProviderUnavailableException();
    } on FormatException {
      throw const CloudProviderResponseException();
    } finally {
      client.close(force: true);
    }
  }
}

class CloudConsentRequiredException implements Exception {
  const CloudConsentRequiredException();
  @override
  String toString() => 'Сначала проверьте контекст и разрешите его передачу.';
}

class CloudProviderConfigurationException implements Exception {
  const CloudProviderConfigurationException();
  @override
  String toString() => 'Настройте провайдера, HTTPS-адрес, модель и ключ API.';
}

class CloudProviderRequestException implements Exception {
  const CloudProviderRequestException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Облачный провайдер вернул ошибку ($statusCode).';
}

class CloudProviderResponseException implements Exception {
  const CloudProviderResponseException();
  @override
  String toString() => 'Облачный провайдер вернул неожиданный ответ.';
}

class CloudProviderUnavailableException implements Exception {
  const CloudProviderUnavailableException();
  @override
  String toString() => 'Облачный провайдер сейчас недоступен.';
}
