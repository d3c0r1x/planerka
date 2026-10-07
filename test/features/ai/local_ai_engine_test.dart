import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';
import 'package:planerka/features/ai/model/model_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not invoke native inference without a verified model', () async {
    final channel = MethodChannel('planerka/local_ai_test');
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls++;
          return 'unexpected';
        });
    final engine = LocalAiEngine(
      store: ModelStore(MemoryModelFileStore()),
      channel: channel,
    );
    await expectLater(engine.generate('Plan my tasks'), throwsStateError);
    expect(nativeCalls, 0);
  });

  test(
    'sends local prompt to native engine after model SHA verification',
    () async {
      final channel = MethodChannel('planerka/local_ai_test');
      final store = MemoryModelFileStore()
        ..seedInstalled('tiny model'.codeUnits);
      var received = <String, Object?>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'loadModel') return true;
            received = Map<String, Object?>.from(call.arguments as Map);
            return 'Локальный ответ';
          });
      final engine = LocalAiEngine(
        store: ModelStore(store),
        manifest: Qwen3ModelManifest.testFixture,
        channel: channel,
      );
      expect(
        await engine.generate('Подскажи следующий шаг'),
        'Локальный ответ',
      );
      expect(received['prompt'], 'Подскажи следующий шаг');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test('cancels native generation when response exceeds timeout', () async {
    final channel = MethodChannel('planerka/local_ai_timeout_test');
    var cancelCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'loadModel') return true;
          if (call.method == 'cancel') {
            cancelCalls++;
            return null;
          }
          return Completer<String?>().future;
        });
    final files = MemoryModelFileStore()..seedInstalled('tiny model'.codeUnits);
    final engine = LocalAiEngine(
      store: ModelStore(files),
      manifest: Qwen3ModelManifest.testFixture,
      channel: channel,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      engine.generate('Задача'),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelCalls, 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
