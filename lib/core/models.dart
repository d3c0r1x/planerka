class TaskEntry {
  const TaskEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dueAt,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'due_at': dueAt?.toIso8601String(),
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
  });

  final String id;
  final String kind;
  final int durationSeconds;
  final DateTime startedAt;
  final String status;
  final String? outcome;

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind,
    'duration_seconds': durationSeconds,
    'started_at': startedAt.toIso8601String(),
    'status': status,
    'outcome': outcome,
  };

  factory TimerSession.fromMap(Map<String, Object?> map) => TimerSession(
    id: map['id'] as String,
    kind: map['kind'] as String,
    durationSeconds: map['duration_seconds'] as int,
    startedAt: DateTime.parse(map['started_at'] as String),
    status: map['status'] as String,
    outcome: map['outcome'] as String?,
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
