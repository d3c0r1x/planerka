import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/backup/backup_file_port.dart';
import 'package:planerka/features/backup/backup_screen.dart';
import 'package:planerka/features/backup/backup_service.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBackupFiles implements BackupFilePort {
  String? picked;
  String? saved;
  String? image;

  @override
  Future<String?> pick() async => picked;

  @override
  Future<String?> pickImage() async => image;

  @override
  Future<String?> saveBackground(String sourcePath) async => sourcePath;

  @override
  Future<bool> save(String json) async {
    saved = json;
    return true;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late FakeBackupFiles files;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_backup_ui_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    files = FakeBackupFiles();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('exports a selectable JSON file and imports by merge', (
    tester,
  ) async {
    await InboxRepository(database).add('Сохранённая задача');
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(service: BackupService(database), files: files),
      ),
    );
    await tester.tap(find.text('Сохранить резервную копию'));
    await tester.pumpAndSettle();
    expect(jsonDecode(files.saved!)['tables']['tasks'], hasLength(1));

    final empty = jsonEncode({
      'version': 1,
      'tables': {
        for (final table in BackupService.userTables) table: <Object>[],
      },
    });
    files.picked = empty;
    await tester.tap(find.text('Восстановить из файла'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Объединить'));
    await tester.pumpAndSettle();
    expect(await InboxRepository(database).listUnsorted(), hasLength(1));
  });
}
