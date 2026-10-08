import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late AppDatabase database;
  late InboxRepository inbox;
  var id = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_inbox_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    id = 0;
    inbox = InboxRepository(
      database,
      now: () => DateTime.utc(2026, 10, 7, 12),
      newId: () => 'id-${++id}',
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('rejects blank input and preserves long text without a date', () async {
    await expectLater(inbox.add(' \n '), throwsArgumentError);
    final longText = 'Задача ' * 800;
    final entry = await inbox.add(longText);
    expect(entry.title, longText.trim());
    expect(entry.status, 'inbox');
    expect(entry.dueAt, isNull);
    expect((await inbox.listUnsorted()).single.title, longText.trim());
  });

  test('edits and deletes an entry', () async {
    final entry = await inbox.add('  Первая запись  ');
    expect(entry.title, 'Первая запись');
    final edited = await inbox.update(entry.id, '  Новый текст  ');
    expect(edited.title, 'Новый текст');
    await inbox.delete(entry.id);
    expect(await inbox.listUnsorted(), isEmpty);
  });

  test('triage supports quick, planned, project and deleted', () async {
    final quick = await inbox.add('Быстро');
    final planned = await inbox.add('Запланировать');
    final project = await inbox.add('Большой проект');
    final deleted = await inbox.add('Не нужно');

    await inbox.triage(quick.id, TaskDisposition.quick);
    await inbox.triage(planned.id, TaskDisposition.planned);
    await inbox.triage(project.id, TaskDisposition.project);
    await inbox.triage(deleted.id, TaskDisposition.deleted);

    expect(await inbox.listUnsorted(), isEmpty);
    final rows = await database.database.query('tasks', orderBy: 'title');
    expect(rows.map((row) => row['status']).toSet(), {
      'quick',
      'planned',
      'project',
      'deleted',
    });
    final projects = await database.database.query('projects');
    expect(projects.single['title'], 'Большой проект');
    expect(
      rows.singleWhere((row) => row['id'] == project.id)['project_id'],
      projects.single['id'],
    );
    expect(
      rows.singleWhere((row) => row['id'] == quick.id)['scheduled_date'],
      '2026-10-07',
    );
  });

  test('entry persists across database reopen', () async {
    await inbox.add('Незавершённая мысль');
    await database.close();
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    inbox = InboxRepository(database);
    expect((await inbox.listUnsorted()).single.title, 'Незавершённая мысль');
  });
}
