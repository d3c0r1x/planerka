import 'dart:io';

import 'package:crypto/crypto.dart';

import 'model_manifest.dart';

abstract interface class ModelFileStore {
  Future<int> partialLength(String fileName);
  Stream<List<int>> readPartial(String fileName);
  Future<void> writePartial(
    String fileName,
    List<int> bytes, {
    bool append = true,
  });
  Future<bool> installedExists(String fileName);
  Stream<List<int>> readInstalled(String fileName);
  Future<void> install(String fileName);
  Future<void> delete(String fileName);
}

class ModelStore {
  ModelStore(this.files);
  final ModelFileStore files;

  Future<String?> verifiedModel(ModelManifest manifest) async {
    if (!await files.installedExists(manifest.fileName)) {
      return null;
    }
    if (await _digest(files.readInstalled(manifest.fileName)) !=
        manifest.sha256) {
      return null;
    }
    return manifest.fileName;
  }

  Future<bool> installPartial(ModelManifest manifest) async {
    if (await _digest(files.readPartial(manifest.fileName)) !=
        manifest.sha256) {
      return false;
    }
    await files.install(manifest.fileName);
    return true;
  }

  Future<void> remove(ModelManifest manifest) =>
      files.delete(manifest.fileName);

  Future<String> _digest(Stream<List<int>> bytes) async {
    return (await sha256.bind(bytes).first).toString();
  }
}

class LocalModelFileStore implements ModelFileStore {
  LocalModelFileStore(this.directory);
  final Directory directory;

  Future<void> _ensure() => directory.create(recursive: true);
  File _partial(String name) => File('${directory.path}/$name.part');
  File _installed(String name) => File('${directory.path}/$name');

  @override
  Future<int> partialLength(String fileName) async {
    await _ensure();
    final file = _partial(fileName);
    return await file.exists() ? file.length() : 0;
  }

  @override
  Stream<List<int>> readPartial(String fileName) async* {
    await _ensure();
    final file = _partial(fileName);
    if (await file.exists()) yield* file.openRead();
  }

  @override
  Future<void> writePartial(
    String fileName,
    List<int> bytes, {
    bool append = true,
  }) async {
    await _ensure();
    await _partial(fileName)
        .writeAsBytes(bytes, mode: append ? FileMode.append : FileMode.write);
  }

  @override
  Future<bool> installedExists(String fileName) =>
      _installed(fileName).exists();

  @override
  Stream<List<int>> readInstalled(String fileName) async* {
    final file = _installed(fileName);
    if (await file.exists()) yield* file.openRead();
  }

  @override
  Future<void> install(String fileName) async {
    await _ensure();
    await _partial(fileName).rename(_installed(fileName).path);
  }

  @override
  Future<void> delete(String fileName) async {
    for (final file in [_partial(fileName), _installed(fileName)]) {
      if (await file.exists()) await file.delete();
    }
  }
}

class MemoryModelFileStore implements ModelFileStore {
  List<int> partial = [];
  List<int>? installed;

  void seedPartial(List<int> bytes) => partial = [...bytes];

  void seedInstalled(List<int> bytes) => installed = [...bytes];

  @override
  Future<int> partialLength(String fileName) async => partial.length;
  @override
  Stream<List<int>> readPartial(String fileName) async* {
    if (partial.isNotEmpty) yield [...partial];
  }

  @override
  Future<bool> installedExists(String fileName) async => installed != null;
  @override
  Stream<List<int>> readInstalled(String fileName) async* {
    if (installed != null) yield [...installed!];
  }

  @override
  Future<void> writePartial(
    String fileName,
    List<int> bytes, {
    bool append = true,
  }) async => partial = [...(append ? partial : <int>[]), ...bytes];
  @override
  Future<void> install(String fileName) async {
    installed = [...partial];
    partial.clear();
  }

  @override
  Future<void> delete(String fileName) async {
    partial.clear();
    installed = null;
  }
}
