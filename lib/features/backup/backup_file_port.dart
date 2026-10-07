import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

abstract interface class BackupFilePort {
  Future<bool> save(String json);
  Future<String?> pick();
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
}
