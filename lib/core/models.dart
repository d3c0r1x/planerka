class TaskEntry {
  const TaskEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dueAt,
    this.parentTaskId,
    this.scheduledAt,
    this.estimatedMinutes,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueAt;
  final String? parentTaskId;
  final DateTime? scheduledAt;
  final int? estimatedMinutes;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'due_at': dueAt?.toIso8601String(),
    'parent_task_id': parentTaskId,
    'scheduled_at': scheduledAt?.toIso8601String(),
    'estimated_minutes': estimatedMinutes,
  };

  factory TaskEntry.fromMap(Map<String, Object?> map) => TaskEntry(
    id: map['id'] as String,
    title: map['title'] as String,
    status: map['status'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    dueAt: map['due_at'] == null
        ? null
        : DateTime.parse(map['due_at'] as String),
    parentTaskId: map['parent_task_id'] as String?,
    scheduledAt: map['scheduled_at'] == null
        ? null
        : DateTime.parse(map['scheduled_at'] as String),
    estimatedMinutes: map['estimated_minutes'] as int?,
  );
}

class TimerSession {
  const TimerSession({
    required this.id,
    required this.kind,
    required this.durationSeconds,
    required this.startedAt,
    required this.status,
    this.outcome,
    this.taskId,
    this.deadlineAt,
    this.endedAt,
    this.remainingSeconds,
    this.elapsedSeconds,
  });

  final String id;
  final String kind;
  final int durationSeconds;
  final DateTime startedAt;
  final String status;
  final String? outcome;
  final String? taskId;
  final DateTime? deadlineAt;
  final DateTime? endedAt;
  final int? remainingSeconds;
  final int? elapsedSeconds;

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind,
    'duration_seconds': durationSeconds,
    'started_at': startedAt.toIso8601String(),
    'status': status,
    'outcome': outcome,
    'task_id': taskId,
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'remaining_seconds': remainingSeconds,
    'elapsed_seconds': elapsedSeconds,
  };

  factory TimerSession.fromMap(Map<String, Object?> map) => TimerSession(
    id: map['id'] as String,
    kind: map['kind'] as String,
    durationSeconds: map['duration_seconds'] as int,
    startedAt: DateTime.parse(map['started_at'] as String),
    status: map['status'] as String,
    outcome: map['outcome'] as String?,
    taskId: map['task_id'] as String?,
    deadlineAt: map['deadline_at'] == null
        ? null
        : DateTime.parse(map['deadline_at'] as String),
    endedAt: map['ended_at'] == null
        ? null
        : DateTime.parse(map['ended_at'] as String),
    remainingSeconds: map['remaining_seconds'] as int?,
    elapsedSeconds: map['elapsed_seconds'] as int?,
  );
}

class Project {
  const Project({required this.id, required this.title, this.goalId});

  final String id;
  final String title;
  final String? goalId;
}

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.progress,
    this.target,
    this.unit = '',
  });

  final String id;
  final String title;
  final double progress;
  final double? target;
  final String unit;
}
