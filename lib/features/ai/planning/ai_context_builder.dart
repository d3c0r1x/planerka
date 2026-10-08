import 'dart:convert';

class AiTaskContext {
  const AiTaskContext({
    required this.id,
    required this.title,
    this.status = 'planned',
    this.dueDay,
    this.scheduledDay,
    this.dueAt,
    this.scheduledAt,
    this.estimatedMinutes,
    this.notes = '',
  });

  final String id;
  final String title;
  final String status;
  final String? dueDay;
  final String? scheduledDay;
  final DateTime? dueAt;
  final DateTime? scheduledAt;
  final int? estimatedMinutes;
  final String notes;
}

class AiGoalContext {
  const AiGoalContext({
    required this.id,
    required this.title,
    required this.progress,
    this.target,
  });

  final String id;
  final String title;
  final double progress;
  final double? target;
}

class AiInboxTaskContext {
  const AiInboxTaskContext({
    required this.id,
    required this.title,
    this.notes = '',
  });
  final String id;
  final String title;
  final String notes;
}

class AiInboxSuggestion {
  const AiInboxSuggestion({required this.items, required this.titles});
  final List<
    ({String taskId, String disposition, String reason, DateTime? dueAt})
  >
  items;
  final Map<String, String> titles;
}

class AiMoodContext {
  const AiMoodContext({required this.day, required this.mood, this.note = ''});

  final String day;
  final int? mood;
  final String note;
}

class AiPlanningContext {
  const AiPlanningContext({
    required this.tasks,
    required this.goals,
    required this.diary,
    this.busyBlocks = const [],
  });

  final List<AiTaskContext> tasks;
  final List<AiGoalContext> goals;
  final List<AiMoodContext> diary;
  final List<AiBusyBlock> busyBlocks;

  Map<String, Object?> toJson() => {
    'tasks': tasks
        .map(
          (task) => {
            'id': task.id,
            'title': task.title,
            'status': task.status,
            'dueDay': task.dueDay,
            'scheduledDay': task.scheduledDay,
            'scheduledAt': task.scheduledAt?.toIso8601String(),
            'estimatedMinutes': task.estimatedMinutes,
            'dueAt': task.dueAt?.toIso8601String(),
            if (task.notes.isNotEmpty) 'notes': task.notes,
          },
        )
        .toList(),
    'busyBlocks': busyBlocks
        .map(
          (block) => {
            'start': block.start.toIso8601String(),
            'end': block.end.toIso8601String(),
            'label': block.label,
            'taskId': block.taskId,
          },
        )
        .toList(),
    'goals': goals
        .map(
          (goal) => {
            'id': goal.id,
            'title': goal.title,
            'progress': goal.progress,
            'target': goal.target,
          },
        )
        .toList(),
    if (diary.isNotEmpty)
      'diary': diary
          .map(
            (entry) => {
              'day': entry.day,
              'mood': entry.mood,
              'note': entry.note,
            },
          )
          .toList(),
  };
}

class AiBusyBlock {
  const AiBusyBlock({
    required this.start,
    required this.end,
    required this.label,
    this.taskId,
  });
  final DateTime start;
  final DateTime end;
  final String label;
  final String? taskId;
}

class AiContextBuilder {
  AiPlanningContext build({
    required List<AiTaskContext> tasks,
    required List<AiGoalContext> goals,
    required List<AiMoodContext> diary,
    required bool includeDiary,
    List<AiBusyBlock> busyBlocks = const [],
  }) {
    final safeTasks = tasks.take(50).map((task) {
      return AiTaskContext(
        id: task.id,
        title: _limit(task.title, 120),
        status: task.status,
        dueDay: task.dueDay,
        scheduledDay: task.scheduledDay,
        dueAt: task.dueAt,
        scheduledAt: task.scheduledAt,
        estimatedMinutes: task.estimatedMinutes,
        notes: _limit(task.notes, 240),
      );
    }).toList();
    final safeGoals = goals.take(10).map((goal) {
      return AiGoalContext(
        id: goal.id,
        title: _limit(goal.title, 120),
        progress: goal.progress,
        target: goal.target,
      );
    }).toList();
    final safeDiary = includeDiary
        ? diary
              .take(7)
              .map(
                (entry) => AiMoodContext(
                  day: entry.day,
                  mood: entry.mood,
                  note: _limit(entry.note, 240),
                ),
              )
              .toList()
        : const <AiMoodContext>[];
    return AiPlanningContext(
      tasks: safeTasks,
      goals: safeGoals,
      diary: safeDiary,
      busyBlocks: busyBlocks.take(100).toList(),
    );
  }

  String prompt(AiPlanningContext context, {required DateTime today}) {
    return '''Ты помощник планировщика. Предложи до 5 точных временных слотов для существующих задач на сегодня или ближайшие 7 дней.
Не выдумывай id и не добавляй новые дела. Не ставь задачи внутрь busyBlocks. Учитывай dueAt, цели и дневник настроения без осуждения.
Верни только JSON: {"summary":"краткий вывод","recommendations":[{"taskId":"id из контекста","scheduledAt":"ISO8601 local date-time","durationMinutes":30,"reason":"краткое пояснение"}]}.
Если переносы не нужны, верни пустой recommendations.
Сегодня: ${_day(today)}
Длительность бери из estimatedMinutes либо оцени в пределах 15-180 минут. Контекст: ${_encode(context.toJson())}''';
  }

  String inboxPrompt(List<AiInboxTaskContext> tasks) =>
      '''Ты локальный помощник для разбора Inbox.
Для каждой записи выбери категорию: quick, planned, project или deleted. Не выдумывай ID, не удаляй ничего. Для planned предложи dueAt в ISO 8601 или null.
Ответ только JSON: {"items":[{"taskId":"id","disposition":"quick|planned|project|deleted","dueAt":"YYYY-MM-DDTHH:mm:ss" или null,"reason":"короткая причина"}]}.
Записи: ${jsonEncode(tasks.take(20).map((task) => {'id': task.id, 'title': _limit(task.title, 120), 'notes': _limit(task.notes, 160)}).toList())}''';

  AiInboxSuggestion parseInbox(
    String response,
    List<AiInboxTaskContext> tasks,
  ) {
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
    if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
      throw const FormatException('Не найден список рекомендаций');
    }
    final raw = decoded['items'] as List;
    if (raw.length > 20) {
      throw const FormatException('Слишком много рекомендаций');
    }
    final allowed = tasks.map((item) => item.id).toSet();
    final seen = <String>{};
    final output =
        <
          ({String taskId, String disposition, String reason, DateTime? dueAt})
        >[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Неверный пункт');
      }
      final id = item['taskId'];
      final disposition = item['disposition'];
      final reason = item['reason'];
      final dueRaw = item['dueAt'];
      final dueAt = dueRaw == null ? null : DateTime.tryParse(dueRaw as String);
      if (id is! String ||
          !allowed.contains(id) ||
          !seen.add(id) ||
          disposition is! String ||
          !{'quick', 'planned', 'project', 'deleted'}.contains(disposition) ||
          dueRaw != null && (dueAt == null || dueAt.isBefore(DateTime.now())) ||
          disposition == 'planned' && dueAt == null ||
          reason is! String ||
          reason.trim().isEmpty ||
          reason.length > 160) {
        throw const FormatException('Рекомендация не прошла проверку');
      }
      output.add((
        taskId: id,
        disposition: disposition,
        reason: reason.trim(),
        dueAt: dueAt,
      ));
    }
    return AiInboxSuggestion(
      items: output,
      titles: {for (final task in tasks) task.id: task.title},
    );
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _encode(Map<String, Object?> value) => jsonEncode(value);

  String _limit(String value, int maxLength) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.length <= maxLength
        ? cleaned
        : cleaned.substring(0, maxLength);
  }
}
