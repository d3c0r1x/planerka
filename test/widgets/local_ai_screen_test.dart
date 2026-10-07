import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/model/local_ai_screen.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';
import 'package:planerka/features/ai/model/model_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sends prompt to local engine and shows its answer', (
    tester,
  ) async {
    final channel = MethodChannel('planerka/local_ai_widget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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
    await tester.enterText(
      find.byType(TextField),
      'Помоги выбрать следующий шаг',
    );
    await tester.tap(find.text('Получить совет'));
    await tester.pumpAndSettle();
    expect(find.text('Один шаг: начни с Inbox.'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
