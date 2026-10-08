import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/reminders/sleep_mode_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_sleep_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('sleep mode defaults off and persists across service instances', () async {
    final sleep = SleepModeService(database);
    expect(await sleep.isEnabled(), isFalse);
    await sleep.setEnabled(true);
    expect(await SleepModeService(database).isEnabled(), isTrue);
    await sleep.setEnabled(false);
    expect(await sleep.isEnabled(), isFalse);
  });
}
