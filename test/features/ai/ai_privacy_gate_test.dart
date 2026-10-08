import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/ai_provider_router.dart';
import 'package:planerka/features/ai/ai_provider_settings.dart';
import 'package:planerka/features/ai/secure_ai_store.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/planning/ai_recommendation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Secrets implements AiSecretBackend {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _NoopGenerator implements AiTextGenerator, CloudAiProvider {
  int localCalls = 0;
  int cloudCalls = 0;
  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    localCalls++;
    return 'local';
  }
  @override
  Future<String> complete({
    required String prompt,
    required Uri endpoint,
    required String model,
    required String apiKey,
    required int maxTokens,
  }) async {
    cloudCalls++;
    return 'cloud';
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late _Secrets backend;
  late AiProviderSettingsStore settings;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_ai_privacy_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    backend = _Secrets();
    settings = AiProviderSettingsStore(
      database,
      SecureAiStore(backend: backend),
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('cloud refuses without saved explicit context permission', () async {
    final generator = _NoopGenerator();
    await settings.save(
      AiProviderSettings.defaults().copyWith(
        mode: AiProviderMode.cloud,
        provider: 'Compatible',
        endpoint: 'https://example.invalid/chat',
        model: 'test',
      ),
      apiKey: 'secret',
    );
    final router = AiProviderRouter(
      local: generator,
      cloud: generator,
      settings: settings.load,
      secrets: SecureAiStore(backend: backend),
    );

    await expectLater(
      router.generate('task details'),
      throwsA(isA<CloudConsentRequiredException>()),
    );
    expect(generator.cloudCalls, 0);
    expect(generator.localCalls, 0);
  });

  test('API key is stored outside SQLite and diary is opt-in', () async {
    await settings.save(
      AiProviderSettings.defaults().copyWith(
        mode: AiProviderMode.cloud,
        provider: 'Compatible',
        endpoint: 'https://example.invalid/chat',
        model: 'test',
        allowCloudContext: true,
      ),
      apiKey: 'secret-never-in-sqlite',
    );
    final storedRows = await database.database.query('app_metadata');
    expect(storedRows.toString(), isNot(contains('secret-never-in-sqlite')));
    expect(backend.values['ai_provider_api_key'], 'secret-never-in-sqlite');
    expect((await settings.load()).includeDiary, isFalse);
    expect(await AiRecommendationService(database, _NoopGenerator()).diaryEnabled(), isFalse);
  });
}
