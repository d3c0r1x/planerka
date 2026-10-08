import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/ai_provider_router.dart';
import 'package:planerka/features/ai/ai_provider_settings.dart';
import 'package:planerka/features/ai/secure_ai_store.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';

class _Generator implements AiTextGenerator {
  _Generator(this.result);
  final String result;
  int calls = 0;
  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    calls++;
    return result;
  }
}

class _Cloud implements CloudAiProvider {
  int calls = 0;
  String? lastPrompt;
  bool fail = false;
  @override
  Future<String> complete({
    required String prompt,
    required Uri endpoint,
    required String model,
    required String apiKey,
    required int maxTokens,
  }) async {
    calls++;
    lastPrompt = prompt;
    if (fail) throw const CloudProviderUnavailableException();
    return 'cloud answer';
  }
}

class _Secrets implements AiSecretBackend {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('local mode routes locally and never calls cloud', () async {
    final local = _Generator('local answer');
    final cloud = _Cloud();
    final secrets = _Secrets();
    final settings = AiProviderSettings.defaults();
    final router = AiProviderRouter(
      local: local,
      cloud: cloud,
      settings: () async => settings,
      secrets: SecureAiStore(backend: secrets),
    );

    expect(await router.generate('prompt'), 'local answer');
    expect(local.calls, 1);
    expect(cloud.calls, 0);
  });

  test('approved cloud mode routes to configured provider without fallback', () async {
    final local = _Generator('local answer');
    final cloud = _Cloud();
    final secrets = _Secrets()..values['ai_provider_api_key'] = 'test-secret';
    final settings = AiProviderSettings.defaults().copyWith(
      mode: AiProviderMode.cloud,
      provider: 'OpenAI compatible',
      endpoint: 'https://example.invalid/v1/chat/completions',
      model: 'small-model',
      allowCloudContext: true,
    );
    final router = AiProviderRouter(
      local: local,
      cloud: cloud,
      settings: () async => settings,
      secrets: SecureAiStore(backend: secrets),
    );

    expect(await router.generate('minimal preview'), 'cloud answer');
    expect(cloud.calls, 1);
    expect(cloud.lastPrompt, 'minimal preview');
    expect(local.calls, 0);
  });

  test('cloud error does not fall back to local generation', () async {
    final local = _Generator('local answer');
    final cloud = _Cloud()..fail = true;
    final secrets = _Secrets()..values['ai_provider_api_key'] = 'test-secret';
    final settings = AiProviderSettings.defaults().copyWith(
      mode: AiProviderMode.cloud,
      provider: 'OpenAI compatible',
      endpoint: 'https://example.invalid/v1/chat/completions',
      model: 'small-model',
      allowCloudContext: true,
    );
    final router = AiProviderRouter(
      local: local,
      cloud: cloud,
      settings: () async => settings,
      secrets: SecureAiStore(backend: secrets),
    );

    await expectLater(
      router.generate('approved context'),
      throwsA(isA<CloudProviderUnavailableException>()),
    );
    expect(local.calls, 0);
    expect(cloud.calls, 1);
  });
}
