import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_database.dart';
import '../../planning/planning_repository.dart';
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

  Future<List<String>> generateGoalSteps(String goalTitle) async {
    final title = goalTitle.trim();
    if (title.isEmpty || title.length > 240) {
      throw ArgumentError.value(goalTitle, 'goalTitle');
    }
    final prompt =
        '''
Ты локальный планировщик. Разбей долгосрочную цель на конкретные небольшие действия.
Цель: $title
Верни только JSON: {"steps":["...", "..."]}. От 3 до 8 действий, каждое короткое, выполнимое и на русском.
Не добавляй вводные фразы, даты или Markdown.
''';
    final response = await generator.generate(prompt, maxTokens: 320);
    return GoalStepValidator().parse(response);
  }

  Future<void> applyGoalSteps(String goalId, List<String> steps) =>
      PlanningRepository(database).addGoalActions(goalId, steps);

  Future<AiInboxSuggestion> classifyInbox() async {
    final rows = await database.database.query(
      'tasks',
      columns: ['id', 'title', 'notes'],
      where: 'status = ?',
      whereArgs: ['inbox'],
      orderBy: 'created_at DESC',
      limit: 20,
    );
    final tasks = rows
        .map(
          (row) => AiInboxTaskContext(
            id: row['id'] as String,
            title: row['title'] as String,
            notes: row['notes'] as String? ?? '',
          ),
        )
        .toList();
    if (tasks.isEmpty) {
      return AiInboxSuggestion(items: const [], titles: const {});
    }
    final answer = await generator.generate(
      _contextBuilder.inboxPrompt(tasks),
      maxTokens: 512,
    );
    return _contextBuilder.parseInbox(answer, tasks);
  }

  Future<void> applyInboxSelected(
    AiInboxSuggestion suggestion,
    Set<String> selectedIds,
  ) async {
    if (selectedIds.isEmpty) return;
    final chosen = suggestion.items
        .where((item) => selectedIds.contains(item.taskId))
        .toList();
    if (chosen.length != selectedIds.length) {
      throw StateError('Рекомендации устарели');
    }
    final idGenerator = const Uuid();
    await database.database.transaction((tx) async {
      for (final item in chosen) {
        final rows = await tx.query(
          'tasks',
          where: "id = ? AND status = 'inbox'",
          whereArgs: [item.taskId],
        );
        if (rows.isEmpty) {
          throw StateError('Запись уже обработана');
        }
        String? projectId;
        if (item.disposition == 'project') {
          projectId = idGenerator.v4();
          await tx.insert('projects', {
            'id': projectId,
            'title': rows.single['title'],
            'created_at': _now().toUtc().toIso8601String(),
          });
        }
        if (item.disposition == 'deleted') {
          await tx.update(
            'tasks',
            {
              'status': 'deleted',
              'updated_at': _now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [item.taskId],
          );
        } else {
          await tx.update(
            'tasks',
            {
              'status': item.disposition,
              'project_id': projectId,
              'updated_at': _now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [item.taskId],
          );
        }
      }
    });
    await database.remindersChanged();
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

class GoalStepValidator {
  List<String> parse(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Ответ не содержит JSON');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.substring(start, end + 1));
    } on FormatException {
      throw const FormatException('Ответ ИИ содержит неверный JSON');
    }
    if (decoded is! Map<String, dynamic> || decoded['steps'] is! List) {
      throw const FormatException('Не найден список шагов цели');
    }
    final raw = decoded['steps'] as List;
    if (raw.length < 3 || raw.length > 8) {
      throw const FormatException('Нужно от 3 до 8 шагов');
    }
    final steps = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw const FormatException('Шаг должен быть текстом');
      }
      final step = item.trim();
      if (step.isEmpty || step.length > 160 || steps.contains(step)) {
        throw const FormatException(
          'Шаг пустой, слишком длинный или повторяется',
        );
      }
      steps.add(step);
    }
    return steps;
  }
}
