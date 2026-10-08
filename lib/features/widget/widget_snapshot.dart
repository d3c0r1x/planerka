import '../../core/models.dart';
import '../planning/planning_repository.dart';
import '../shifts/shift_repository.dart';

class PlannerWidgetTask {
  const PlannerWidgetTask({
    required this.id,
    required this.title,
    required this.isOverdue,
  });

  final String id;
  final String title;
  final bool isOverdue;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'isOverdue': isOverdue,
  };
}

class PlannerWidgetShift {
  const PlannerWidgetShift({
    required this.teamId,
    required this.name,
    required this.start,
    required this.end,
  });

  final String teamId;
  final String name;
  final DateTime start;
  final DateTime end;

  Map<String, Object?> toJson() => {
    'teamId': teamId,
    'name': name,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };
}

class PlannerWidgetSnapshot {
  const PlannerWidgetSnapshot({
    required this.goalTitle,
    required this.goalPercent,
    required this.tasks,
    required this.nextShift,
  });

  final String goalTitle;
  final int goalPercent;
  final List<PlannerWidgetTask> tasks;
  final PlannerWidgetShift? nextShift;

  static Future<PlannerWidgetSnapshot> fromRepositories({
    required PlanningRepository planning,
    required ShiftRepository shifts,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final goal = await planning.primaryGoal();
    var goalPercent = 0;
    if (goal != null) {
      if (goal.target != null && goal.target! > 0) {
        goalPercent = (goal.progress / goal.target! * 100).round().clamp(
          0,
          100,
        );
      } else {
        final taskProgress = await planning.goalTaskProgress(goal.id);
        if (taskProgress.total > 0) {
          goalPercent = (taskProgress.completed / taskProgress.total * 100)
              .round()
              .clamp(0, 100);
        }
      }
    }

    final today = await planning.listForDay(current);
    final overdue = await planning.listOverdue(current);
    final overdueIds = overdue.map((task) => task.id).toSet();
    final byId = <String, TaskEntry>{
      for (final task in [...overdue, ...today]) task.id: task,
    };
    final tasks = byId.values.toList()
      ..sort((a, b) {
        final overdueOrder =
            (overdueIds.contains(b.id) ? 1 : 0) -
            (overdueIds.contains(a.id) ? 1 : 0);
        if (overdueOrder != 0) return overdueOrder;
        final aTime = a.scheduledAt ?? a.dueAt;
        final bTime = b.scheduledAt ?? b.dueAt;
        if (aTime == null) return bTime == null ? 0 : 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });

    final teams = await shifts.listTeams();
    final selected = {
      for (final team in teams)
        if (team.attends) team.id: team,
    };
    PlannerWidgetShift? nextShift;
    if (selected.isNotEmpty) {
      final days = await shifts.calendar(
        DateTime(current.year, current.month, current.day),
        DateTime(current.year, current.month, current.day + 15),
      );
      final candidates =
          days
              .where(
                (day) =>
                    selected.containsKey(day.teamId) &&
                    !day.cancelled &&
                    day.blockStart != null &&
                    day.blockEnd != null &&
                    day.blockEnd!.isAfter(current),
              )
              .toList()
            ..sort((a, b) => a.blockStart!.compareTo(b.blockStart!));
      if (candidates.isNotEmpty) {
        final day = candidates.first;
        nextShift = PlannerWidgetShift(
          teamId: day.teamId,
          name: selected[day.teamId]!.name,
          start: day.blockStart!,
          end: day.blockEnd!,
        );
      }
    }

    return PlannerWidgetSnapshot(
      goalTitle: goal?.title ?? 'Добавь цель',
      goalPercent: goalPercent,
      tasks: tasks
          .take(3)
          .map(
            (task) => PlannerWidgetTask(
              id: task.id,
              title: task.title,
              isOverdue: overdueIds.contains(task.id),
            ),
          )
          .toList(),
      nextShift: nextShift,
    );
  }

  Map<String, Object?> toJson() => {
    'goalTitle': goalTitle,
    'goalPercent': goalPercent,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'nextShift': nextShift?.toJson(),
  };
}
