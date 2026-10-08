import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;

import 'model_manifest.dart';
import 'model_store.dart';

abstract interface class ModelTransport {
  Future<ModelResponse> get(Uri uri, {int? rangeStart});
}

class ModelResponse {
  const ModelResponse({
    required this.statusCode,
    required this.bytes,
    this.contentLength,
  });
  final int statusCode;
  final int? contentLength;
  final Stream<List<int>> bytes;
}

class IoModelTransport implements ModelTransport {
  final HttpClient _client = HttpClient();

  @override
  Future<ModelResponse> get(Uri uri, {int? rangeStart}) async {
    final request = await _client.getUrl(uri);
    if (rangeStart != null && rangeStart > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
    }
    final response = await request.close();
    return ModelResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength,
      bytes: response,
    );
  }

  void close() => _client.close(force: true);
}

enum ModelDownloadStatus { checking, downloading, paused, ready, failed }

class ModelDownloadState {
  const ModelDownloadState(
    this.status, {
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });
  final ModelDownloadStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? message;
  double? get progress => totalBytes <= 0 ? null : receivedBytes / totalBytes;
}

class ModelDownloader {
  ModelDownloader(this.transport, this.store);
  final ModelTransport transport;
  final ModelStore store;
  bool _paused = false;

  final StreamController<ModelDownloadState> _backgroundStates =
      StreamController<ModelDownloadState>.broadcast();
  Stream<ModelDownloadState> get backgroundStates => _backgroundStates.stream;
  ModelDownloadState? _lastState;
  bg.Transfer? _nativeTransfer;
  bool _finishingNativeTransfer = false;

  Future<void> initializeBackground() async {
    await bg.FileDownloader().start(autoCleanDatabase: true);
    bg.FileDownloader().configureNotification(
      running: const bg.TaskNotification(
        'Скачивается локальный ИИ',
        '{progress} · {timeRemaining}',
      ),
      complete: const bg.TaskNotification(
        'Модель готова',
        'ИИ работает офлайн',
      ),
      error: const bg.TaskNotification(
        'Не удалось скачать модель',
        'Откройте Планёрку, чтобы продолжить',
      ),
      paused: const bg.TaskNotification(
        'Загрузка модели приостановлена',
        '{progress}',
      ),
      progressBar: true,
    );
    await bg.FileDownloader().resumeFromBackground();
    final restored = await bg.FileDownloader().transfers.rehydrateFromDatabase(
      group: 'planerka-model',
    );
    for (final transfer in restored) {
      if (transfer.task.taskId ==
          'planerka-model-${Qwen3ModelManifest.manifest.sha256.substring(0, 12)}') {
        _nativeTransfer = transfer;
        _emitNative(transfer);
        _watchNativeTransfer(transfer, Qwen3ModelManifest.manifest);
        if (transfer.status == bg.TaskStatus.complete) {
          await _finishNativeTransfer(transfer, Qwen3ModelManifest.manifest);
        }
        break;
      }
    }
  }

  ModelDownloadState? get currentState => _lastState;

  Future<ModelDownloadState> runNativeInBackground(
    ModelManifest manifest,
  ) async {
    _lastState = const ModelDownloadState(ModelDownloadStatus.checking);
    _emit(_lastState!);
    final installed = await store.verifiedModel(manifest);
    if (installed != null) {
      _lastState = ModelDownloadState(
        ModelDownloadStatus.ready,
        receivedBytes: manifest.expectedBytes,
        totalBytes: manifest.expectedBytes,
      );
      _emit(_lastState!);
      return _lastState!;
    }
    await initializeBackground();
    final task = bg.DownloadTask(
      taskId: 'planerka-model-${manifest.sha256.substring(0, 12)}',
      url: manifest.url,
      filename: '${manifest.fileName}.part',
      directory: 'models',
      baseDirectory: bg.BaseDirectory.applicationSupport,
      group: 'planerka-model',
      retries: 10,
      allowPause: true,
      requiresWiFi: false,
      displayName: 'Qwen3 · 0.6B',
      updates: bg.Updates.statusAndProgress,
      notificationConfig: bg.TaskNotificationConfig(
        running: const bg.TaskNotification(
          'Скачивается локальный ИИ',
          '{progress} · {timeRemaining}',
        ),
        complete: const bg.TaskNotification(
          'Модель готова',
          'ИИ работает офлайн',
        ),
        error: const bg.TaskNotification(
          'Не удалось скачать модель',
          'Откройте Планёрку, чтобы продолжить',
        ),
        paused: const bg.TaskNotification(
          'Загрузка модели приостановлена',
          '{progress}',
        ),
        progressBar: true,
      ),
    );
    final transfer = await bg.FileDownloader().transfers.getOrStart(task);
    _nativeTransfer = transfer;
    _emitNative(transfer);
    _watchNativeTransfer(transfer, manifest);
    try {
      if (transfer.status == bg.TaskStatus.paused) await transfer.resume();
      await _finishNativeTransfer(transfer, manifest);
    } catch (error) {
      final status = transfer.status;
      _lastState = ModelDownloadState(
        status == bg.TaskStatus.paused
            ? ModelDownloadStatus.paused
            : ModelDownloadStatus.failed,
        receivedBytes: ((transfer.progress ?? 0) * manifest.expectedBytes)
            .round(),
        totalBytes: manifest.expectedBytes,
        message: error.toString(),
      );
    }
    _emit(_lastState!);
    return _lastState!;
  }

  Future<void> pauseNative() async {
    await _nativeTransfer?.pause();
  }

  Future<void> resumeNative() async {
    await _nativeTransfer?.resume();
  }

  Future<void> cancelNative() async => _nativeTransfer?.cancel();

  void _watchNativeTransfer(bg.Transfer transfer, ModelManifest manifest) {
    unawaited(
      transfer.updates.listen((_) {
        _emitNative(transfer);
        if (transfer.status == bg.TaskStatus.complete) {
          unawaited(_finishNativeTransfer(transfer, manifest));
        }
      }).asFuture<void>(),
    );
  }

  Future<void> _finishNativeTransfer(
    bg.Transfer transfer,
    ModelManifest manifest,
  ) async {
    if (_finishingNativeTransfer) return;
    _finishingNativeTransfer = true;
    try {
      final file = await transfer.file;
      await store.files.installDownloaded(file.path, manifest.fileName);
      if (await store.verifiedModel(manifest) == null) {
        await store.remove(manifest);
        _lastState = const ModelDownloadState(
          ModelDownloadStatus.failed,
          message: 'Размер или SHA-256 модели не совпал',
        );
      } else {
        _lastState = ModelDownloadState(
          ModelDownloadStatus.ready,
          receivedBytes: manifest.expectedBytes,
          totalBytes: manifest.expectedBytes,
        );
      }
    } catch (error) {
      _lastState = ModelDownloadState(
        transfer.status == bg.TaskStatus.paused
            ? ModelDownloadStatus.paused
            : ModelDownloadStatus.failed,
        receivedBytes: ((transfer.progress ?? 0) * manifest.expectedBytes)
            .round(),
        totalBytes: manifest.expectedBytes,
        message: error.toString(),
      );
    } finally {
      _finishingNativeTransfer = false;
      _emit(_lastState!);
    }
  }

  void _emitNative(bg.Transfer transfer) {
    final status = switch (transfer.status) {
      bg.TaskStatus.complete => ModelDownloadStatus.checking,
      bg.TaskStatus.running ||
      bg.TaskStatus.enqueued ||
      bg.TaskStatus.waitingToRetry => ModelDownloadStatus.downloading,
      bg.TaskStatus.paused => ModelDownloadStatus.paused,
      _ => ModelDownloadStatus.failed,
    };
    final size = transfer.task is bg.DownloadTask ? transfer.progress : null;
    _lastState = ModelDownloadState(
      status,
      receivedBytes: ((size ?? 0) * Qwen3ModelManifest.expectedBytes).round(),
      totalBytes: Qwen3ModelManifest.expectedBytes,
    );
    _emit(_lastState!);
  }

  void _emit(ModelDownloadState state) {
    if (!_backgroundStates.isClosed) _backgroundStates.add(state);
  }

  Future<ModelDownloadState> runInBackground(ModelManifest manifest) async {
    await for (final state in download(manifest)) {
      _lastState = state;
      if (!_backgroundStates.isClosed) _backgroundStates.add(state);
    }
    return _lastState ?? const ModelDownloadState(ModelDownloadStatus.failed);
  }

  void pause() => _paused = true;
  void resume() => _paused = false;

  void close() {
    if (transport is IoModelTransport) (transport as IoModelTransport).close();
    _backgroundStates.close();
  }

  Stream<ModelDownloadState> download(ModelManifest manifest) async* {
    _paused = false;
    yield const ModelDownloadState(ModelDownloadStatus.checking);
    if (await store.verifiedModel(manifest) != null) {
      yield ModelDownloadState(
        ModelDownloadStatus.ready,
        receivedBytes: manifest.expectedBytes,
        totalBytes: manifest.expectedBytes,
      );
      return;
    }
    var offset = await store.files.partialLength(manifest.fileName);
    var received = offset;
    try {
      var response = await transport.get(
        manifest.uri,
        rangeStart: offset == 0 ? null : offset,
      );
      if (offset > 0 && response.statusCode == HttpStatus.ok) {
        offset = 0;
        received = 0;
        await store.files.writePartial(
          manifest.fileName,
          const [],
          append: false,
        );
      } else if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        yield ModelDownloadState(
          ModelDownloadStatus.failed,
          message: 'HTTP ${response.statusCode}',
        );
        return;
      }
      yield ModelDownloadState(
        ModelDownloadStatus.downloading,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
      );
      await for (final chunk in response.bytes) {
        if (_paused) {
          yield ModelDownloadState(
            ModelDownloadStatus.paused,
            receivedBytes: received,
            totalBytes: manifest.expectedBytes,
          );
          return;
        }
        await store.files.writePartial(manifest.fileName, chunk);
        received += chunk.length;
        yield ModelDownloadState(
          ModelDownloadStatus.downloading,
          receivedBytes: received,
          totalBytes: manifest.expectedBytes,
        );
      }
      if (received != manifest.expectedBytes) {
        yield ModelDownloadState(
          ModelDownloadStatus.failed,
          receivedBytes: received,
          totalBytes: manifest.expectedBytes,
          message: 'Размер модели не совпал',
        );
        return;
      }
      if (!await store.installPartial(manifest)) {
        await store.remove(manifest);
        yield ModelDownloadState(
          ModelDownloadStatus.failed,
          message: 'SHA-256 не совпал',
        );
        return;
      }
      yield ModelDownloadState(
        ModelDownloadStatus.ready,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
      );
    } on SocketException {
      yield ModelDownloadState(
        ModelDownloadStatus.failed,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
        message: 'Нет подключения. Частичная загрузка сохранена.',
      );
    } catch (error) {
      yield ModelDownloadState(
        ModelDownloadStatus.failed,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
        message: error.toString(),
      );
    }
  }
}
