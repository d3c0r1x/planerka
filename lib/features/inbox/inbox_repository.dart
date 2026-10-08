import '../../core/app_database.dart';
import '../../core/models.dart';

import 'package:uuid/uuid.dart';

enum TaskDisposition { quick, planned, project, deleted }

class InboxRepository {
  InboxRepository(
    this.database, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase database;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<TaskEntry> add(String text) async {
    final title = text.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Введите задачу');
    }
    final now = _now();
    final entry = TaskEntry(
      id: _newId(),
      title: title,
      status: 'inbox',
      createdAt: now,
      updatedAt: now,
    );
    await database.database.insert('tasks', entry.toMap());
    return entry;
  }

  Future<TaskEntry> update(String id, String text) async {
    final title = text.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Введите задачу');
    }
    final count = await database.database.update(
      'tasks',
      {'title': title, 'updated_at': _now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count == 0) throw StateError('Запись не найдена');
    await database.remindersChanged();
    final rows = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    return TaskEntry.fromMap(rows.single);
  }

  Future<void> delete(String id) async {
    await database.database.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await database.remindersChanged();
  }

  Future<List<TaskEntry>> listUnsorted() async {
    final rows = await database.database.query(
      'tasks',
      where: 'status = ?',
      whereArgs: ['inbox'],
      orderBy: "CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC, created_at DESC",
    );
    return rows.map(TaskEntry.fromMap).toList();
  }

  Future<void> triage(
    String id,
    TaskDisposition disposition, {
    DateTime? dueAt,
    DateTime? remindAt,
  }) async {
    await database.database.transaction((tx) async {
      final rows = await tx.query(
        'tasks',
        where: 'id = ? AND status = ?',
        whereArgs: [id, 'inbox'],
      );
      if (rows.isEmpty) throw StateError('Запись уже разобрана или не найдена');
      String? projectId;
      final now = _now();
      if (disposition == TaskDisposition.project) {
        projectId = _newId();
        await tx.insert('projects', {
          'id': projectId,
          'title': rows.single['title'],
          'created_at': now.toUtc().toIso8601String(),
        });
      }
      await tx.update(
        'tasks',
        {
          'status': disposition.name,
          'project_id': projectId,
          'parent_task_id': null,
          'due_at': dueAt?.toUtc().toIso8601String(),
          'scheduled_date': disposition == TaskDisposition.quick
              ? _day(now)
              : disposition == TaskDisposition.planned && dueAt != null
              ? _day(dueAt)
              : null,
          'remind_at': disposition == TaskDisposition.quick
              ? (remindAt ?? now.add(const Duration(hours: 2)))
                    .toUtc()
                    .toIso8601String()
              : remindAt?.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await database.remindersChanged();
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> classifyWithAi(
    String id,
    TaskDisposition disposition, {
    DateTime? dueAt,
  }) => triage(id, disposition, dueAt: dueAt);
}
