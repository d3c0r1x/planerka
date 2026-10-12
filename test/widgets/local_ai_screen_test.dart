import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/model/local_ai_screen.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';
import 'package:planerka/features/ai/model/model_store.dart';
import 'package:planerka/features/ai/planning/ai_recommendation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('keeps local mode and sends prompt to local engine', (
    tester,
  ) async {
    final channel = MethodChannel('planerka/local_ai_widget_test');
    final localCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          localCalls.add(call.method);
          if (call.method == 'loadModel') return true;
          if (call.method == 'generate') return 'Один шаг: начни с Inbox.';
          return null;
        });
    final files = MemoryModelFileStore()..seedInstalled('tiny model'.codeUnits);
    final engine = LocalAiEngine(
      store: ModelStore(files),
      manifest: Qwen3ModelManifest.testFixture,
      channel: channel,
    );
    await tester.pumpWidget(MaterialApp(home: LocalAiScreen(engine: engine)));
    expect(find.text('Локальный помощник'), findsOneWidget);
    expect(
      find.text(
        'Ответ создаётся на телефоне. Задачи и дневник не отправляются в интернет.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField),
      'Помоги выбрать следующий шаг',
    );
    await tester.tap(find.text('Получить совет'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Один шаг: начни с Inbox.'), findsOneWidget);
    expect(localCalls, contains('generate'));
    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('uses injected generator for cloud chat and labels it clearly', (
    tester,
  ) async {
    final fixture = await tester.runAsync(_openDatabase);
    if (fixture == null) fail('Database fixture did not initialize');
    addTearDown(() async => tester.runAsync(fixture.dispose));
    final generator = _FakeGenerator('Ответ от выбранной модели.');
    final service = AiRecommendationService(fixture.database, generator);
    final channel = MethodChannel('planerka/local_ai_cloud_chat_test');
    final localCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          localCalls.add(call.method);
          return true;
        });
    final engine = _emptyEngine(channel);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiScreen(
          engine: engine,
          recommendations: service,
          cloudMode: true,
        ),
      ),
    );
    expect(find.text('Облачный помощник'), findsOneWidget);
    expect(
      find.text(
        'Ответ создаётся облачной моделью. Текст запроса и разрешённый контекст передаются провайдеру.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Составь мягкий план');
    await tester.tap(find.text('Получить совет'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ответ от выбранной модели.'), findsOneWidget);
    expect(generator.prompts, ['Составь мягкий план']);
    expect(localCalls, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('cloud mode without a cloud service never calls local AI', (
    tester,
  ) async {
    final channel = MethodChannel('planerka/local_ai_cloud_missing_test');
    final localCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          localCalls.add(call.method);
          return 'Локальный ответ';
        });
    final files = MemoryModelFileStore()..seedInstalled('tiny model'.codeUnits);
    final engine = LocalAiEngine(
      store: ModelStore(files),
      manifest: Qwen3ModelManifest.testFixture,
      channel: channel,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiScreen(
          engine: engine,
          cloudMode: true,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Подскажи следующий шаг');
    await tester.tap(find.text('Получить совет'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(localCalls, isEmpty);
    expect(find.text('Облачный помощник не настроен.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('planning uses injected generator without loading local model', (
    tester,
  ) async {
    final fixture = await tester.runAsync(_openDatabase);
    if (fixture == null) fail('Database fixture did not initialize');
    addTearDown(() async => tester.runAsync(fixture.dispose));
    final generator = _FakeGenerator(
      '{"summary":"План готов","recommendations":[]}',
    );
    final service = AiRecommendationService(fixture.database, generator);
    final channel = MethodChannel('planerka/local_ai_plan_test');
    final localCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          localCalls.add(call.method);
          return true;
        });

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiScreen(
          engine: _emptyEngine(channel),
          recommendations: service,
          cloudMode: true,
        ),
      ),
    );
    await tester.tap(find.text('Предложить план'));
    await tester.pumpAndSettle();

    expect(find.text('План от ИИ'), findsOneWidget);
    expect(find.text('План готов'), findsOneWidget);
    expect(generator.prompts, hasLength(1));
    expect(localCalls, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

LocalAiEngine _emptyEngine(MethodChannel channel) => LocalAiEngine(
  store: ModelStore(MemoryModelFileStore()),
  manifest: Qwen3ModelManifest.testFixture,
  channel: channel,
);

Future<_DatabaseFixture> _openDatabase() async {
  final directory = await Directory.systemTemp.createTemp('local_ai_screen_');
  final database = await AppDatabase.open(
    p.join(directory.path, 'app.db'),
    factory: databaseFactoryFfiNoIsolate,
  );
  return _DatabaseFixture(directory, database);
}

class _DatabaseFixture {
  const _DatabaseFixture(this.directory, this.database);

  final Directory directory;
  final AppDatabase database;

  Future<void> dispose() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _FakeGenerator implements AiTextGenerator {
  _FakeGenerator(this.response);

  final String response;
  final List<String> prompts = [];

  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    prompts.add(prompt);
    return response;
  }
}
