import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('new database stores an inbox entry across reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planerka_db_test_',
    );
    final path = p.join(directory.path, 'planerka.db');
    addTearDown(() => directory.delete(recursive: true));

    final first = await AppDatabase.open(path, factory: databaseFactoryFfi);
    await first.database.insert('tasks', {
      'id': 'entry-1',
      'title': 'Купить корм',
      'status': 'inbox',
      'created_at': '2026-10-07T12:00:00.000Z',
      'updated_at': '2026-10-07T12:00:00.000Z',
    });
    await first.close();

    final second = await AppDatabase.open(path, factory: databaseFactoryFfi);
    final rows = await second.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );
    expect(rows.single['title'], 'Купить корм');
    expect(rows.single['status'], 'inbox');
    await second.close();
  });

  test('new database creates all v1 data tables', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planerka_schema_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final db = await AppDatabase.open(
      p.join(directory.path, 'planerka.db'),
      factory: databaseFactoryFfi,
    );

    final tables = await db.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'tasks',
        'projects',
        'goals',
        'habits',
        'habit_logs',
        'journal_entries',
        'timer_sessions',
      ]),
    );
    await db.close();
  });
}
