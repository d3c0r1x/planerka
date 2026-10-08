import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:planerka/features/widget/widget_snapshot.dart';
import 'package:planerka/features/widget/widget_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late PlanningRepository planning;
  late _FakeWidgetHost host;
  late WidgetSyncService sync;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_widget_sync_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    planning = PlanningRepository(database, now: () => now);
    host = _FakeWidgetHost();
    sync = WidgetSyncService(
      planning: planning,
      shifts: ShiftRepository(database, now: () => now),
      host: host,
      now: () => now,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('refresh persists snapshot and requests native widget update', () async {
    await sync.refresh();

    expect(host.snapshot, isNotNull);
    expect(host.updates, 1);
  });

  test('cold-start widget URI completes a current task only once', () async {
    await _insertTask(database, id: 'task', status: 'planned');
    final uri = Uri.parse('planerka://complete?taskId=task');

    final taps = await Future.wait([
      sync.handleLaunchUri(uri),
      sync.handleLaunchUri(uri),
    ]);
    expect(taps.where((value) => value).length, 1);
    final completedAt = (await database.database.query(
      'tasks',
      columns: ['completed_at'],
      where: 'id = ?',
      whereArgs: ['task'],
    )).single['completed_at'];
    expect(await sync.handleLaunchUri(uri), isFalse);
    expect(
      (await database.database.query(
        'tasks',
        columns: ['completed_at'],
        where: 'id = ?',
        whereArgs: ['task'],
      )).single['completed_at'],
      completedAt,
    );
    final xpEvents = await database.database.query(
      'xp_events',
      where: 'event_id = ?',
      whereArgs: ['task:task'],
    );
    expect(xpEvents, hasLength(1));
    expect(host.updates, 1);
  });

  test(
    'unknown, malformed, and already completed task links are ignored',
    () async {
      await _insertTask(database, id: 'done', status: 'completed');

      expect(
        await sync.handleLaunchUri(
          Uri.parse('planerka://complete?taskId=missing'),
        ),
        isFalse,
      );
      expect(
        await sync.handleLaunchUri(
          Uri.parse('planerka://complete?taskId=done'),
        ),
        isFalse,
      );
      expect(
        await sync.handleLaunchUri(
          Uri.parse('https://example.com/complete?taskId=done'),
        ),
        isFalse,
      );
      expect(
        await sync.handleLaunchUri(Uri.parse('planerka://complete')),
        isFalse,
      );
      expect(host.updates, 0);
    },
  );

  test('revalidates task state immediately before completion', () async {
    await _insertTask(database, id: 'deleted', status: 'deleted');

    expect(
      await sync.handleLaunchUri(
        Uri.parse('planerka://complete?taskId=deleted'),
      ),
      isFalse,
    );
    expect(
      (await database.database.query(
        'tasks',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: ['deleted'],
      )).single['status'],
      'deleted',
    );
  });
}

Future<void> _insertTask(
  AppDatabase database, {
  required String id,
  required String status,
}) async {
  final timestamp = DateTime(2026, 10, 8, 9).toUtc().toIso8601String();
  await database.database.insert('tasks', {
    'id': id,
    'title': 'Задача $id',
    'status': status,
    'scheduled_date': '2026-10-08',
    'created_at': timestamp,
    'updated_at': timestamp,
    if (status == 'completed') 'completed_at': timestamp,
  });
}

class _FakeWidgetHost implements WidgetHost {
  PlannerWidgetSnapshot? snapshot;
  var updates = 0;

  @override
  Future<void> saveSnapshot(PlannerWidgetSnapshot value) async {
    snapshot = value;
  }

  @override
  Future<void> updateWidget() async => updates++;
}
