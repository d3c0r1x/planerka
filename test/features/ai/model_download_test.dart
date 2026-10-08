import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/model_downloader.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';
import 'package:planerka/features/ai/model/model_store.dart';

void main() {
  test(
    'native download in the app model directory survives SHA install',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planerka_native_model_',
      );
      try {
        final content = utf8.encode('tiny model');
        final modelStore = ModelStore(LocalModelFileStore(directory));
        final nativePart = File(
          '${directory.path}/${Qwen3ModelManifest.testFixture.fileName}.part',
        );
        await nativePart.writeAsBytes(content);
        await modelStore.files.installDownloaded(
          nativePart.path,
          Qwen3ModelManifest.testFixture.fileName,
        );
        expect(
          await modelStore.installPartial(Qwen3ModelManifest.testFixture),
          isTrue,
        );
        expect(
          await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
          isNotNull,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'completed transfer does not replace an already verified model',
    () async {
      final files = MemoryModelFileStore()
        ..seedInstalled(utf8.encode('tiny model'));
      final store = ModelStore(files);
      var requestedTransferFile = false;

      final installed = await store.installCompletedDownload(
        Qwen3ModelManifest.testFixture,
        () async {
          requestedTransferFile = true;
          throw StateError('completed transfer file was already consumed');
        },
      );

      expect(installed, isTrue);
      expect(requestedTransferFile, isFalse);
      expect(
        await store.verifiedModel(Qwen3ModelManifest.testFixture),
        isNotNull,
      );
    },
  );

  test(
    'partial and native files cannot install before exact size and SHA',
    () async {
      final store = MemoryModelFileStore()..seedPartial(utf8.encode('bad'));
      final modelStore = ModelStore(store);
      expect(
        await modelStore.installPartial(Qwen3ModelManifest.testFixture),
        isFalse,
      );
      expect(store.installed, isNull);
      expect(
        await modelStore.verifiedModel(Qwen3ModelManifest.testFixture),
        isNull,
      );
    },
  );

  test('downloads, verifies, installs and reuses model', () async {
    final bytes = utf8.encode('tiny model');
    final store = MemoryModelFileStore();
    final transport = FakeModelTransport(bytes);
    final downloader = ModelDownloader(transport, ModelStore(store));
    final states = await downloader
        .download(Qwen3ModelManifest.testFixture)
        .toList();
    expect(states.last.status, ModelDownloadStatus.ready);
    expect(transport.requests, 1);
    expect(
      (await downloader.download(Qwen3ModelManifest.testFixture).toList())
          .last
          .status,
      ModelDownloadStatus.ready,
    );
    expect(transport.requests, 1);
  });

  test('resumes by HTTP range after persisted partial bytes', () async {
    final content = utf8.encode('tiny model');
    final store = MemoryModelFileStore()..seedPartial(content.take(4).toList());
    final transport = FakeModelTransport(content, rangeStatus: 206);
    final downloader = ModelDownloader(transport, ModelStore(store));
    final states = await downloader
        .download(Qwen3ModelManifest.testFixture)
        .toList();
    expect(states.last.status, ModelDownloadStatus.ready);
    expect(transport.rangeStarts, [4]);
  });

  test('restarts when server ignores range and blocks hash mismatch', () async {
    final content = utf8.encode('tiny model');
    final store = MemoryModelFileStore()..seedPartial([1, 2, 3]);
    final ignoredRange = FakeModelTransport(content, rangeStatus: 200);
    final downloader = ModelDownloader(ignoredRange, ModelStore(store));
    expect(
      (await downloader.download(Qwen3ModelManifest.testFixture).toList())
          .last
          .status,
      ModelDownloadStatus.ready,
    );
    expect(ignoredRange.rangeStarts, [3]);

    final mismatch = ModelDownloader(
      FakeModelTransport(utf8.encode('bad model')),
      ModelStore(MemoryModelFileStore()),
    );
    final badStates = await mismatch
        .download(Qwen3ModelManifest.testFixture)
        .toList();
    expect(badStates.last.status, ModelDownloadStatus.failed);
    expect(
      await mismatch.store.verifiedModel(Qwen3ModelManifest.testFixture),
      isNull,
    );
  });

  test(
    'keeps partial bytes after offline error and resumes from saved offset',
    () async {
      final bytes = utf8.encode('tiny model');
      final store = MemoryModelFileStore();
      final interrupted = ModelDownloader(
        _InterruptedTransport(),
        ModelStore(store),
      );
      final failed = await interrupted
          .download(Qwen3ModelManifest.testFixture)
          .toList();
      expect(failed.last.status, ModelDownloadStatus.failed);
      expect(store.partial, bytes.take(5));

      final resumedTransport = FakeModelTransport(bytes, rangeStatus: 206);
      final resumed = ModelDownloader(resumedTransport, ModelStore(store));
      expect(
        (await resumed.download(Qwen3ModelManifest.testFixture).toList())
            .last
            .status,
        ModelDownloadStatus.ready,
      );
      expect(resumedTransport.rangeStarts, [5]);
    },
  );

  test('pause preserves bytes and next run resumes with Range', () async {
    final store = MemoryModelFileStore();
    final controlled = _ControlledTransport();
    final downloader = ModelDownloader(controlled, ModelStore(store));
    final paused = Completer<void>();
    final subscription = downloader
        .download(Qwen3ModelManifest.testFixture)
        .listen((state) {
          if (state.status == ModelDownloadStatus.downloading &&
              state.receivedBytes == 5) {
            downloader.pause();
            controlled.controller.add(utf8.encode('model'));
          }
          if (state.status == ModelDownloadStatus.paused &&
              !paused.isCompleted) {
            paused.complete();
          }
        });
    await Future<void>.delayed(Duration.zero);
    controlled.controller.add(utf8.encode('tiny '));
    await paused.future.timeout(const Duration(seconds: 2));
    expect(store.partial, utf8.encode('tiny '));
    await subscription.cancel();
    await controlled.controller.close();

    final resumeTransport = FakeModelTransport(
      utf8.encode('tiny model'),
      rangeStatus: 206,
    );
    final resumed = ModelDownloader(resumeTransport, ModelStore(store));
    expect(
      (await resumed.download(Qwen3ModelManifest.testFixture).toList())
          .last
          .status,
      ModelDownloadStatus.ready,
    );
    expect(resumeTransport.rangeStarts, [5]);
  });
}

class _InterruptedTransport implements ModelTransport {
  @override
  Future<ModelResponse> get(Uri uri, {int? rangeStart}) async => ModelResponse(
    statusCode: 200,
    contentLength: 10,
    bytes: _chunksThenDisconnect(),
  );

  Stream<List<int>> _chunksThenDisconnect() async* {
    yield utf8.encode('tiny ');
    throw const SocketException('offline');
  }
}

class _ControlledTransport implements ModelTransport {
  final StreamController<List<int>> controller = StreamController<List<int>>();

  @override
  Future<ModelResponse> get(Uri uri, {int? rangeStart}) async => ModelResponse(
    statusCode: 200,
    contentLength: 10,
    bytes: controller.stream,
  );
}

class FakeModelTransport implements ModelTransport {
  FakeModelTransport(this.content, {this.rangeStatus = 200});
  final List<int> content;
  final int rangeStatus;
  int requests = 0;
  final List<int?> rangeStarts = [];

  @override
  Future<ModelResponse> get(Uri uri, {int? rangeStart}) async {
    requests++;
    rangeStarts.add(rangeStart);
    final start = rangeStart != null && rangeStatus == 206 ? rangeStart : 0;
    return ModelResponse(
      statusCode: rangeStart != null ? rangeStatus : 200,
      contentLength: content.length - start,
      bytes: Stream.value(content.skip(start).toList()),
    );
  }
}
