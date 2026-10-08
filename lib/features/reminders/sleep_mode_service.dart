import 'package:sqflite_common/sqlite_api.dart';

import '../../core/app_database.dart';

class SleepModeService {
  SleepModeService(this.database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase database;
  final DateTime Function() _now;

  Future<bool> isEnabled() async {
    final rows = await database.database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sleep_mode_enabled'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  Future<void> setEnabled(bool enabled, {DateTime? at}) async {
    final now = (at ?? _now()).toUtc().toIso8601String();
    await database.database.transaction((tx) async {
      await tx.insert('app_metadata', {
        'key': 'sleep_mode_enabled',
        'value': enabled.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (!enabled) {
        await tx.insert('app_metadata', {
          'key': 'sleep_mode_woke_at',
          'value': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<DateTime?> lastWakeAt() async {
    final rows = await database.database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sleep_mode_woke_at'],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['value'] as String).toLocal();
  }
}
