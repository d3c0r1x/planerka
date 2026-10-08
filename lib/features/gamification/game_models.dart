enum MissedTaskCause {
  externalObstacle,
  estimateWrong,
  priorityChanged,
  avoidableDelay,
}

class PenaltyProposal {
  const PenaltyProposal({
    required this.id,
    required this.taskId,
    required this.cause,
    required this.weekStart,
    required this.points,
  });

  final String id;
  final String taskId;
  final MissedTaskCause cause;
  final DateTime weekStart;
  final int points;
}

class WeeklyReliability {
  const WeeklyReliability({
    required this.weekStart,
    required this.score,
    required this.penaltyCount,
    required this.enabled,
  });

  final DateTime weekStart;
  final int score;
  final int penaltyCount;
  final bool enabled;
}

class AccountabilityEvent {
  const AccountabilityEvent({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.cause,
    required this.points,
    required this.status,
    required this.createdAt,
    this.recoveryTaskId,
  });

  final String id;
  final String taskId;
  final String taskTitle;
  final String cause;
  final int points;
  final String status;
  final DateTime createdAt;
  final String? recoveryTaskId;
}

class RecoveryTask {
  const RecoveryTask({required this.id, required this.title});
  final String id;
  final String title;
}

class PlayerProgress {
  const PlayerProgress({
    required this.totalXp,
    required this.level,
    required this.xpInLevel,
    required this.xpToNextLevel,
  });

  final int totalXp;
  final int level;
  final int xpInLevel;
  final int xpToNextLevel;
}

class GameQuest {
  const GameQuest({
    required this.id,
    required this.kind,
    required this.title,
    required this.progress,
    required this.target,
    required this.rewardXp,
    required this.completed,
  });

  final String id;
  final String kind;
  final String title;
  final int progress;
  final int target;
  final int rewardXp;
  final bool completed;
}

class GameAchievement {
  const GameAchievement({
    required this.key,
    required this.title,
    required this.description,
    required this.unlockedAt,
  });

  final String key;
  final String title;
  final String description;
  final DateTime unlockedAt;
}

class CustomReward {
  const CustomReward({
    required this.id,
    required this.title,
    required this.createdAt,
    this.redeemedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? redeemedAt;
}
