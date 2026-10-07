import 'package:uuid/uuid.dart';

import '../../core/app_database.dart';
import '../../core/models.dart';
import '../gamification/gamification_service.dart';

class PlanningRepository {
  PlanningRepository(
    this.database, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase database;
  final DateTime Function() _now;
  final String Function() _newId;

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> schedule(String taskId, DateTime dueAt) async {
    await database.database.update(
      'tasks',
      {
        'due_at': dueAt.toUtc().toIso8601String(),
        'updated_at': _now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
    await database.remindersChanged();
  }

  Future<void> setToday(String taskId, DateTime date) async {
    await database.database.update(
      'tasks',
      {
        'scheduled_date': _day(date),
        'updated_at': _now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> complete(String taskId) async {
    final now = _now().toUtc().toIso8601String();
    final changed = await database.database.update(
      'tasks',
      {'status': 'completed', 'completed_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    if (changed > 0) {
      await GamificationService(database).awardTask(taskId, occurredAt: _now());
    }
    await database.remindersChanged();
  }

  Future<List<TaskEntry>> listForDay(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day).toUtc();
    final end = DateTime(date.year, date.month, date.day + 1).toUtc();
    final rows = await database.database.rawQuery(
      '''
      SELECT * FROM tasks
      WHERE status IN ('planned', 'quick')
        AND (scheduled_date = ? OR (due_at >= ? AND due_at < ?))
      ORDER BY due_at, created_at
    ''',
      [_day(date), start.toIso8601String(), end.toIso8601String()],
    );
    return rows.map(TaskEntry.fromMap).toList();
  }

  Future<List<TaskEntry>> listOverdue(DateTime now) async {
    final rows = await database.database.query(
      'tasks',
      where: "status IN ('planned', 'quick') AND due_at < ?",
      whereArgs: [now.toUtc().toIso8601String()],
      orderBy: 'due_at',
    );
    return rows.map(TaskEntry.fromMap).toList();
  }

  Future<List<TaskEntry>> listUnscheduled() async {
    final rows = await database.database.query(
      'tasks',
      where: "status IN ('planned', 'quick') AND due_at IS NULL AND scheduled_date IS NULL",
      orderBy: 'created_at',
    );
    return rows.map(TaskEntry.fromMap).toList();
  }

  Future<List<Project>> listProjects() async {
    final rows = await database.database.query(
      'projects',
      where: 'archived_at IS NULL',
      orderBy: 'created_at',
    );
    return rows
        .map(
          (row) => Project(
            id: row['id'] as String,
            title: row['title'] as String,
            goalId: row['goal_id'] as String?,
          ),
        )
        .toList();
  }

  Future<TaskEntry> addAction(String projectId, String title) async {
    final text = title.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Введите действие');
    }
    final now = _now();
    final entry = TaskEntry(
      id: _newId(),
      title: text,
      status: 'planned',
      createdAt: now,
      updatedAt: now,
    );
    await database.database.insert('tasks', {
      ...entry.toMap(),
      'project_id': projectId,
    });
    return entry;
  }

  Future<List<TaskEntry>> listProjectActions(String projectId) async {
    final rows = await database.database.query(
      'tasks',
      where: "project_id = ? AND status != 'project'",
      whereArgs: [projectId],
      orderBy: 'created_at',
    );
    return rows.map(TaskEntry.fromMap).toList();
  }

  Future<Goal> addGoal(String title, {double? target, String unit = ''}) async {
    final text = title.trim();
    if (text.isEmpty) throw ArgumentError.value(title, 'title', 'Введите цель');
    final id = _newId();
    final now = _now().toUtc().toIso8601String();
    await database.database.insert('goals', {
      'id': id,
      'title': text,
      'unit': unit,
      'target': target,
      'progress': 0,
      'created_at': now,
      'updated_at': now,
    });
    return Goal(id: id, title: text, progress: 0, target: target, unit: unit);
  }

  Future<void> linkProjectToGoal(String projectId, String goalId) async {
    await database.database.update(
      'projects',
      {'goal_id': goalId},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateGoalProgress(String goalId, double progress) async {
    if (progress < 0) throw ArgumentError.value(progress, 'progress');
    await database.database.update(
      'goals',
      {'progress': progress, 'updated_at': _now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  Future<List<Goal>> listGoals() async {
    final rows = await database.database.query('goals', orderBy: 'created_at');
    return rows
        .map(
          (row) => Goal(
            id: row['id'] as String,
            title: row['title'] as String,
            progress: (row['progress'] as num).toDouble(),
            target: (row['target'] as num?)?.toDouble(),
            unit: row['unit'] as String,
          ),
        )
        .toList();
  }
}
