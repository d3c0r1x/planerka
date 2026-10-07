import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';
import 'package:planerka/features/ai/model/model_store.dart';

void main() {
  test('verified model is reused and removable', () async {
    final store = MemoryModelFileStore();
    final modelStore = ModelStore(store);
    expect(
      await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
      isNull,
    );
    store.seedPartial('tiny model'.codeUnits);
    await modelStore.installPartial(Qwen3ModelManifest.testFixture);
    expect(
      await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
      isNotNull,
    );
    await modelStore.remove(Qwen3ModelManifest.testFixture);
    expect(
      await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
      isNull,
    );
  });

  test('corrupt installed model is never reported ready', () async {
    final store = MemoryModelFileStore();
    final modelStore = ModelStore(store);
    store.seedInstalled('changed'.codeUnits);
    expect(
      await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
      isNull,
    );
  });

  test('partial file survives store recreation for a later resume', () async {
    final directory = await Directory.systemTemp.createTemp('model-store-');
    try {
      final first = LocalModelFileStore(directory);
      await first.writePartial(Qwen3ModelManifest.testFixture.fileName, [
        1,
        2,
        3,
      ]);
      final reopened = LocalModelFileStore(Directory(directory.path));
      expect(
        await reopened.partialLength(Qwen3ModelManifest.testFixture.fileName),
        3,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
