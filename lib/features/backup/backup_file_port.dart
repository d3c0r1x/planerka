import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

typedef BackgroundDirectoryProvider = Future<Directory> Function();

abstract interface class BackupFilePort {
  Future<bool> save(String json);
  Future<String?> pick();
  Future<String?> pickImage();
  Future<String?> saveBackground(String sourcePath);
}

class NativeBackupFilePort implements BackupFilePort {
  const NativeBackupFilePort();

  @override
  Future<bool> save(String json) async {
    final saved = await FilePicker.saveFile(
      fileName: 'planerka_backup.json',
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return saved != null;
  }

  @override
  Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }

  @override
  Future<String?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
    );
    return file?.path;
  }

  @override
  Future<String?> saveBackground(
    String sourcePath, {
    BackgroundDirectoryProvider? directoryProvider,
  }) async {
    final root = await (directoryProvider ?? getApplicationSupportDirectory)();
    final folder = Directory('${root.path}/backgrounds');
    await folder.create(recursive: true);
    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.image';
    final target = File('${folder.path}/background$extension');
    final temporary = File('${target.path}.part');
    await File(sourcePath).copy(temporary.path);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }
}
