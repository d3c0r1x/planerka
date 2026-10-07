import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_database.dart';

enum ImportMode { merge, replace }

class BackupService {
  BackupService(
    this.database, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase database;
  final DateTime Function() _now;
  final String Function() _newId;

  static const userTables = [
    'goals',
    'projects',
    'tasks',
    'habits',
    'habit_logs',
    'journal_entries',
    'timer_sessions',
    'timer_settings',
  ];

  Future<String> exportJson() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in userTables) {
      tables[table] = await database.database.query(table);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': _now().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  Future<void> importJson(String json, {required ImportMode mode}) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Неподдерживаемый формат резервной копии');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic> ||
        userTables.any((table) => !rawTables.containsKey(table))) {
      throw const FormatException('В резервной копии отсутствуют таблицы');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in userTables) {
      final rows = rawTables[table];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('Некорректные данные таблицы $table');
      }
      tables[table] = rows
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
    }

    await database.database.transaction((transaction) async {
      if (mode == ImportMode.replace) {
        for (final table in userTables.reversed) {
          await transaction.delete(table);
        }
      }
      for (final table in userTables) {
        for (final row in tables[table]!) {
          await transaction.insert(
            table,
            row,
            conflictAlgorithm: mode == ImportMode.merge
                ? ConflictAlgorithm.ignore
                : ConflictAlgorithm.abort,
          );
        }
      }
    });
  }

  Future<int> importPrivateSeed(String? json) async {
    if (json == null || json.isEmpty) return 0;
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['tasks'] is! List ||
        (decoded['tasks'] as List).any((task) => task is! String)) {
      throw const FormatException('Некорректный seed-файл');
    }
    return database.database.transaction<int>((transaction) async {
      final imported = await transaction.query(
        'app_metadata',
        where: 'key = ?',
        whereArgs: ['private_seed_imported'],
      );
      if (imported.isNotEmpty) return 0;
      final now = _now().toUtc().toIso8601String();
      var count = 0;
      for (final rawTitle in (decoded['tasks'] as List).cast<String>()) {
        final title = rawTitle.trim();
        if (title.isEmpty) continue;
        await transaction.insert('tasks', {
          'id': _newId(),
          'title': title,
          'status': 'inbox',
          'created_at': now,
          'updated_at': now,
        });
        count++;
      }
      await transaction.insert('app_metadata', {
        'key': 'private_seed_imported',
        'value': now,
      });
      return count;
    });
  }
}
