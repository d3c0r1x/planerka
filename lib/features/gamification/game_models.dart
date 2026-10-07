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
