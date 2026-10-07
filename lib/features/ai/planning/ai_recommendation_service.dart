import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/app_database.dart';
import '../model/local_ai_engine.dart';
import 'ai_context_builder.dart';
import 'ai_suggestion.dart';

class AiRecommendationService {
  AiRecommendationService(
    this.database,
    this.generator, {
    DateTime Function()? now,
    AiContextBuilder? contextBuilder,
    AiSuggestionValidator? validator,
  }) : _now = now ?? DateTime.now,
       _contextBuilder = contextBuilder ?? AiContextBuilder(),
       _validator = validator ?? AiSuggestionValidator();

  final AppDatabase database;
  final AiTextGenerator generator;
  final DateTime Function() _now;
  final AiContextBuilder _contextBuilder;
  final AiSuggestionValidator _validator;

  Future<bool> diaryEnabled() async {
    final rows = await database.database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['ai_include_diary'],
    );
    return rows.isEmpty ? true : rows.single['value'] == 'true';
  }

  Future<void> setDiaryEnabled(bool enabled) async {
    await database.database.insert('app_metadata', {
      'key': 'ai_include_diary',
      'value': enabled ? 'true' : 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AiPlanningContext> buildContext() async {
    final taskRows = await database.database.query(
      'tasks',
      columns: ['id', 'title', 'notes', 'status', 'due_at', 'scheduled_date'],
      where: "status IN ('planned', 'quick')",
      orderBy: 'CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at, created_at',
      limit: 50,
    );
    final goalRows = await database.database.query(
      'goals',
      columns: ['id', 'title', 'progress', 'target'],
      orderBy: 'updated_at DESC',
      limit: 10,
    );
    final includeDiary = await diaryEnabled();
    final diaryRows = includeDiary
        ? await database.database.query(
            'journal_entries',
            columns: ['text', 'mood', 'created_at'],
            orderBy: 'created_at DESC',
            limit: 7,
          )
        : const <Map<String, Object?>>[];

    String? day(String? value) {
      if (value == null || value.isEmpty) return null;
      final parsed = DateTime.tryParse(value)?.toLocal();
      if (parsed == null) return null;
      return _formatDay(parsed);
    }

    final tasks = taskRows
        .map(
          (row) => AiTaskContext(
            id: row['id'] as String,
            title: row['title'] as String,
            notes: row['notes'] as String? ?? '',
            status: row['status'] as String,
            dueDay: day(row['due_at'] as String?),
            scheduledDay: day(row['scheduled_date'] as String?),
          ),
        )
        .toList();
    final goals = goalRows
        .map(
          (row) => AiGoalContext(
            id: row['id'] as String,
            title: row['title'] as String,
            progress: (row['progress'] as num).toDouble(),
            target: (row['target'] as num?)?.toDouble(),
          ),
        )
        .toList();
    final diary = diaryRows.map((row) {
      final created = DateTime.parse(row['created_at'] as String).toLocal();
      return AiMoodContext(
        day: _formatDay(created),
        mood: row['mood'] as int?,
        note: row['text'] as String,
      );
    }).toList();
    return _contextBuilder.build(
      tasks: tasks,
      goals: goals,
      diary: diary,
      includeDiary: includeDiary,
    );
  }

  Future<AiSuggestion> generatePlan({
    AiPlanningContext? contextOverride,
  }) async {
    final context = contextOverride ?? await buildContext();
    final prompt = _contextBuilder.prompt(context, today: _now());
    final response = await generator.generate(prompt, maxTokens: 512);
    return _validator.parseAndValidate(
      response,
      context: context,
      today: _now(),
    );
  }

  Future<void> applySelected(
    AiSuggestion suggestion,
    Set<String> selectedTaskIds,
  ) async {
    final selected = suggestion.select(selectedTaskIds);
    if (selected.isEmpty) return;
    final today = DateTime(_now().year, _now().month, _now().day);
    await database.database.transaction((txn) async {
      for (final item in selected) {
        if (item.day.isBefore(today)) {
          throw StateError('Нельзя перенести задачу в прошлое');
        }
        final updated = await txn.update(
          'tasks',
          {
            'scheduled_date': _formatDay(item.day),
            'updated_at': _now().toUtc().toIso8601String(),
          },
          where: "id = ? AND status IN ('planned', 'quick')",
          whereArgs: [item.taskId],
        );
        if (updated != 1) {
          throw StateError('Задача больше недоступна для переноса');
        }
      }
    });
    await database.remindersChanged();
  }

  String _formatDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
