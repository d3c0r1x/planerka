import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/ai_provider_settings.dart';
import 'package:planerka/features/ai/ai_provider_settings_screen.dart';
import 'package:planerka/features/ai/gemini_rest_provider.dart';
import 'package:planerka/features/ai/secure_ai_store.dart';
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

class _Catalog implements GeminiModelCatalog {
  _Catalog(this.models);

  final List<GeminiModelInfo> models;
  String? receivedApiKey;

  @override
  Future<List<GeminiModelInfo>> listModels({required String apiKey}) async {
    receivedApiKey = apiKey;
    return models;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late AppDatabase database;
  late _Secrets secrets;
  late AiProviderSettingsStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planner_ai_settings_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    secrets = _Secrets();
    store = AiProviderSettingsStore(database, SecureAiStore(backend: secrets));
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    GeminiModelCatalog? modelCatalog,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiProviderSettingsScreen(
          database: database,
          settingsStore: store,
          modelCatalog: modelCatalog,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveGeminiSettings() => store.save(
    AiProviderSettings.defaults().copyWith(
      mode: AiProviderMode.cloud,
      provider: 'Google Gemini',
      endpoint: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'custom-model',
    ),
  );

  testWidgets('keeps local AI as default and explains cloud privacy', (
    tester,
  ) async {
    await pumpSettings(tester);

    final group = tester.widget<RadioGroup<AiProviderMode>>(
      find.byType(RadioGroup<AiProviderMode>),
    );
    expect(group.groupValue, AiProviderMode.local);
    expect(
      find.textContaining('без задач и данных планировщика'),
      findsOneWidget,
    );
    expect(find.textContaining('Android Secure Storage'), findsOneWidget);
    expect(find.textContaining('прокси-сервер'), findsOneWidget);
    expect(find.textContaining('улучшения продуктов'), findsOneWidget);
  });

  testWidgets('selecting Gemini presets its endpoint and recommended model', (
    tester,
  ) async {
    await store.save(
      AiProviderSettings.defaults().copyWith(
        mode: AiProviderMode.cloud,
        provider: 'OpenAI compatible',
        endpoint: 'https://api.example.test/v1/chat/completions',
        model: 'custom-model',
      ),
    );
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('ai-provider-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Gemini').last);
    await tester.pumpAndSettle();

    final endpointFinder = find.byKey(const Key('ai-endpoint-field'));
    await _scrollTo(tester, endpointFinder);
    final endpoint = tester.widget<TextField>(
      endpointFinder,
    );
    expect(endpoint.readOnly, isTrue);
    final modelFinder = find.byKey(const Key('ai-model-field'));
    await _scrollTo(tester, modelFinder);
    final model = tester.widget<TextField>(
      modelFinder,
    );
    expect(
      endpoint.controller!.text,
      'https://generativelanguage.googleapis.com/v1beta',
    );
    expect(model.controller!.text, 'gemini-3.5-flash-lite');

    final saveButton = find.byKey(const Key('save-ai-provider-settings'));
    await _scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final saved = await store.load();
    expect(saved.provider, 'Google Gemini');
    expect(saved.endpoint, 'https://generativelanguage.googleapis.com/v1beta');
    expect(saved.model, 'gemini-3.5-flash-lite');
  });

  testWidgets('model discovery uses only the entered key and surfaces models', (
    tester,
  ) async {
    await saveGeminiSettings();
    final catalog = _Catalog([
      GeminiModelInfo(id: 'gemini-3.5-flash-lite', displayName: 'Flash Lite'),
      GeminiModelInfo(id: 'gemini-3.5-flash', displayName: 'Flash'),
    ]);
    await pumpSettings(tester, modelCatalog: catalog);

    final apiKeyField = find.byKey(const Key('ai-api-key-field'));
    await _scrollTo(tester, apiKeyField);
    await tester.enterText(apiKeyField, 'unit-test-api-key');
    final discoverButton = find.byKey(const Key('discover-gemini-models'));
    await _scrollTo(tester, discoverButton, delta: 120);
    await tester.tap(discoverButton);
    await tester.pumpAndSettle();

    expect(catalog.receivedApiKey, 'unit-test-api-key');
    expect(find.text('gemini-3.5-flash-lite'), findsWidgets);
    expect(find.text('gemini-3.5-flash'), findsOneWidget);
    final model = tester.widget<TextField>(
      find.byKey(const Key('ai-model-field')),
    );
    expect(model.controller!.text, 'gemini-3.5-flash-lite');
  });

  testWidgets('key stays obscured and saves only through secure storage', (
    tester,
  ) async {
    await saveGeminiSettings();
    await pumpSettings(tester);

    const key = 'screen-test-secret';
    final apiKeyField = find.byKey(const Key('ai-api-key-field'));
    await _scrollTo(tester, apiKeyField);
    expect(tester.widget<TextField>(apiKeyField).obscureText, isTrue);
    await tester.enterText(apiKeyField, key);
    final saveButton = find.byKey(const Key('save-ai-provider-settings'));
    await _scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(secrets.values[AiProviderSettingsStore.apiKeyName], key);
    final metadata = await database.database.query('app_metadata');
    expect(metadata.toString(), isNot(contains(key)));
    expect(tester.widget<TextField>(apiKeyField).controller!.text, isEmpty);
  });

  testWidgets(
    'context permission still requires confirmation and diary stays separate',
    (tester) async {
      await store.save(
        AiProviderSettings.defaults().copyWith(
          mode: AiProviderMode.cloud,
          provider: 'OpenAI compatible',
          endpoint: 'https://api.example.test/v1/chat/completions',
          model: 'test-model',
        ),
      );
      await pumpSettings(tester);

      final contextToggle = find.byKey(const Key('cloud-context-consent'));
      await _scrollTo(tester, contextToggle);
      await tester.tap(contextToggle);
      await tester.pumpAndSettle();
      expect(find.text('Что может увидеть облачный ИИ'), findsOneWidget);
      await tester.tap(find.text('Разрешить контекст'));
      await tester.pumpAndSettle();

      final contextConsent = tester.widget<SwitchListTile>(
        find.byKey(const Key('cloud-context-consent')),
      );
      expect(contextConsent.value, isTrue);

      final diaryConsent = tester.widget<SwitchListTile>(
        find.byKey(const Key('ai-diary-consent')),
      );
      expect(diaryConsent.value, isFalse);
      final diaryToggle = find.byKey(const Key('ai-diary-consent'));
      await _scrollTo(tester, diaryToggle);
      await tester.tap(diaryToggle);
      await tester.pumpAndSettle();
      final updatedDiaryConsent = tester.widget<SwitchListTile>(
        find.byKey(const Key('ai-diary-consent')),
      );
      expect(updatedDiaryConsent.value, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('cloud-context-consent')),
            )
            .value,
        isTrue,
      );
    },
  );
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  double delta = 180,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
}
