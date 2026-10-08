import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_database.dart';
import '../../../core/models.dart';
import '../../planning/planning_repository.dart';
import '../../shifts/shift_repository.dart';
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
    return rows.isEmpty ? false : rows.single['value'] == 'true';
  }

  Future<void> setDiaryEnabled(bool enabled) async {
    await database.database.insert('app_metadata', {
      'key': 'ai_include_diary',
      'value': enabled ? 'true' : 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Goal>> listGoals() => PlanningRepository(database).listGoals();

  Future<void> updateTaskGoalLinks(
    String taskId,
    Set<String> goalIds, {
    String source = 'manual',
  }) =>
      PlanningRepository(database)
          .setTaskGoalLinks(taskId, goalIds, source: source);

  Future<Set<String>> linkedGoals(String taskId) =>
      PlanningRepository(database).listTaskGoalLinks(taskId);

  Future<void> setTaskGoalLinks(String taskId, Set<String> goalIds) async {
    await PlanningRepository(database).setTaskGoalLinks(taskId, goalIds);
  }

  Future<List<AiGoalLink>> suggestGoalLinks(List<String> taskIds) async {
    final ids = taskIds.toSet();
    if (ids.isEmpty || ids.length > 20) return const [];
    final tasks = await database.database.query(
      'tasks',
      columns: ['id', 'title', 'notes'],
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids.toList(),
    );
    final goals = await listGoals();
    if (tasks.isEmpty || goals.isEmpty) return const [];
    final prompt =
        '''
Предложи, каким целям пользователя помогают задачи. Не выдумывай задачу и цель.
Задачи: ${jsonEncode(tasks.map((row) => {'id': row['id'], 'title': row['title'], 'notes': row['notes']}).toList())}
Цели: ${jsonEncode(goals.map((goal) => {'id': goal.id, 'title': goal.title}).toList())}
Верни JSON: {"links":[{"taskId":"...","goalId":"...","reason":"..."}]}. Только явные полезные связи, до 3 на задачу.
''';
    final response = await generator.generate(prompt, maxTokens: 512);
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('ИИ вернул не JSON');
    }
    final decoded = jsonDecode(response.substring(start, end + 1));
    if (decoded is! Map<String, dynamic> ||
        decoded['links'] is! List ||
        (decoded['links'] as List).length > ids.length * 3) {
      throw const FormatException('ИИ вернул неверный список связей');
    }
    final knownGoals = goals.map((goal) => goal.id).toSet();
    final knownTasks = tasks.map((row) => row['id'] as String).toSet();
    final result = <AiGoalLink>[];
    final seen = <String>{};
    for (final raw in decoded['links'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Неверная связь цели');
      }
      final taskId = raw['taskId'];
      final goalId = raw['goalId'];
      final reason = raw['reason'];
      if (taskId is! String ||
          !knownTasks.contains(taskId) ||
          goalId is! String ||
          !knownGoals.contains(goalId) ||
          reason is! String ||
          reason.trim().isEmpty ||
          reason.length > 240 ||
          !seen.add('$taskId:$goalId')) {
        throw const FormatException(
          'ИИ предложил неизвестную или повторную связь',
        );
      }
      result.add(
        AiGoalLink(taskId: taskId, goalId: goalId, reason: reason.trim()),
      );
    }
    return result;
  }

  Future<AiPlanningContext> buildContext() async {
    final taskRows = await database.database.query(
      'tasks',
      columns: [
        'id',
        'title',
        'notes',
        'status',
        'due_at',
        'scheduled_date',
        'scheduled_at',
        'estimated_minutes',
      ],
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
            dueAt: row['due_at'] == null
                ? null
                : DateTime.parse(row['due_at'] as String).toLocal(),
            scheduledAt: row['scheduled_at'] == null
                ? null
                : DateTime.parse(row['scheduled_at'] as String).toLocal(),
            estimatedMinutes: row['estimated_minutes'] as int?,
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
    final shiftRepository = ShiftRepository(database);
    final shiftDays = await shiftRepository.calendar(
      _now(),
      DateTime(_now().year, _now().month, _now().day + 8),
    );
    final teams = await shiftRepository.listTeams();
    final attending = teams
        .where((team) => team.attends)
        .map((team) => team.id)
        .toSet();
    final busyBlocks = <AiBusyBlock>[
      for (final shift in shiftDays)
        if (attending.contains(shift.teamId) &&
            shift.blockStart != null &&
            shift.blockEnd != null)
          AiBusyBlock(
            start: shift.blockStart!,
            end: shift.blockEnd!,
            label: 'Смена',
          ),
      for (final task in tasks)
        if (task.scheduledAt != null)
          AiBusyBlock(
            start: task.scheduledAt!,
            end: task.scheduledAt!.add(
              Duration(minutes: task.estimatedMinutes ?? 30),
            ),
            label: task.title,
            taskId: task.id,
          ),
    ];
    return _contextBuilder.build(
      tasks: tasks,
      goals: goals,
      diary: diary,
      includeDiary: includeDiary,
      busyBlocks: busyBlocks,
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
        DateTime? quickReminder;
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
          final now = _now();
          if (item.disposition == 'quick') {
            final first = DateTime(
              now.year,
              now.month,
              now.day,
              9,
            ).subtract(const Duration(hours: 1));
            quickReminder = first.isAfter(now)
                ? first
                : now.add(
                    Duration(hours: 2 - (now.difference(first).inHours % 2)),
                  );
          }
          await tx.update(
            'tasks',
            {
              'status': item.disposition,
              'project_id': projectId,
              'parent_task_id': null,
              'scheduled_date': item.disposition == 'quick'
                  ? '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
                  : item.disposition == 'planned' && item.dueAt != null
                  ? _formatDay(item.dueAt!)
                  : null,
              'due_at': item.dueAt?.toUtc().toIso8601String(),
              'remind_at':
                  (item.disposition == 'quick'
                          ? quickReminder
                          : item.disposition == 'planned'
                          ? item.dueAt
                          : null)
                      ?.toUtc()
                      .toIso8601String(),
              'updated_at': now.toUtc().toIso8601String(),
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
    final freshContext = await buildContext();
    final selectedIds = selected.map((item) => item.taskId).toSet();
    for (var i = 0; i < selected.length; i++) {
      final item = selected[i];
      final start = item.scheduledAt!;
      final end = start.add(Duration(minutes: item.durationMinutes));
      final task = freshContext.tasks.where((task) => task.id == item.taskId);
      if (task.isEmpty || start.isBefore(_now())) {
        throw StateError('Временной слот устарел; составь план заново');
      }
      final dueAt = task.single.dueAt;
      if (dueAt != null && end.isAfter(dueAt)) {
        throw StateError('Слот выходит за актуальный дедлайн');
      }
      if (freshContext.busyBlocks.any(
        (block) =>
            !selectedIds.contains(block.taskId) &&
            start.isBefore(block.end) &&
            end.isAfter(block.start),
      )) {
        throw StateError('Слот пересекается с занятым временем');
      }
      for (final other in selected.skip(i + 1)) {
        final otherStart = other.scheduledAt!;
        final otherEnd = otherStart.add(
          Duration(minutes: other.durationMinutes),
        );
        if (start.isBefore(otherEnd) && end.isAfter(otherStart)) {
          throw StateError('Выбранные слоты пересекаются');
        }
      }
    }
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
            'scheduled_at': item.scheduledAt!.toUtc().toIso8601String(),
            'estimated_minutes': item.durationMinutes,
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
