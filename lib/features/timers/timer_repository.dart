import 'package:sqflite/sqflite.dart';

import '../../core/app_database.dart';
import '../../core/models.dart';

class TimerRepository {
  TimerRepository(this.database);

  final AppDatabase database;

  Future<void> create(TimerSession session) async {
    await database.database.insert('timer_sessions', session.toMap());
  }

  Future<void> save(TimerSession session) async {
    await database.database.update(
      'timer_sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<TimerSession?> active() async {
    final rows = await database.database.query(
      'timer_sessions',
      where: "status IN ('running', 'paused')",
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TimerSession.fromMap(rows.single);
  }

  Future<TimerSession?> latest() async {
    final rows = await database.database.query(
      'timer_sessions',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TimerSession.fromMap(rows.single);
  }

  Future<List<TimerSession>> completed() async {
    final rows = await database.database.query(
      'timer_sessions',
      where: 'status = ?',
      whereArgs: ['completed'],
      orderBy: 'started_at DESC',
    );
    return rows.map(TimerSession.fromMap).toList();
  }

  Future<int?> setting(String key) async {
    final rows = await database.database.query(
      'timer_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as int;
  }

  Future<void> setSetting(String key, int value) async {
    await database.database.insert('timer_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
