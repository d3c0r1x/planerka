import 'dart:async';
import 'dart:io';

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

  void pause() => _paused = true;
  void resume() => _paused = false;

  void close() {
    if (transport is IoModelTransport) (transport as IoModelTransport).close();
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
