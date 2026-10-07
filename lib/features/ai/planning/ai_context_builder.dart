import 'dart:convert';

class AiTaskContext {
  const AiTaskContext({
    required this.id,
    required this.title,
    this.status = 'planned',
    this.dueDay,
    this.scheduledDay,
    this.notes = '',
  });

  final String id;
  final String title;
  final String status;
  final String? dueDay;
  final String? scheduledDay;
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
  });

  final List<AiTaskContext> tasks;
  final List<AiGoalContext> goals;
  final List<AiMoodContext> diary;

  Map<String, Object?> toJson() => {
    'tasks': tasks
        .map(
          (task) => {
            'id': task.id,
            'title': task.title,
            'status': task.status,
            'dueDay': task.dueDay,
            'scheduledDay': task.scheduledDay,
            if (task.notes.isNotEmpty) 'notes': task.notes,
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

class AiContextBuilder {
  AiPlanningContext build({
    required List<AiTaskContext> tasks,
    required List<AiGoalContext> goals,
    required List<AiMoodContext> diary,
    required bool includeDiary,
  }) {
    final safeTasks = tasks.take(50).map((task) {
      return AiTaskContext(
        id: task.id,
        title: _limit(task.title, 120),
        status: task.status,
        dueDay: task.dueDay,
        scheduledDay: task.scheduledDay,
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
    );
  }

  String prompt(AiPlanningContext context, {required DateTime today}) {
    return '''Ты локальный помощник планировщика. Предложи до 5 переносов существующих задач на сегодня или будущие даты.
Не выдумывай id и не добавляй новые дела. Учитывай дедлайны, цели и переданный дневник настроения без осуждения.
Верни только JSON: {"summary":"краткий вывод","recommendations":[{"taskId":"id из контекста","day":"YYYY-MM-DD","reason":"краткое пояснение"}]}.
Если переносы не нужны, верни пустой recommendations.
Сегодня: ${_day(today)}
Контекст: ${_encode(context.toJson())}''';
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
