import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/gamification/game_models.dart';
import 'package:planerka/features/gamification/gamification_screen.dart';
import 'package:planerka/features/gamification/gamification_service.dart';

void main() {
  testWidgets('shows weekly reliability, history and recovery action', (
    tester,
  ) async {
    final game = _FakeGameData()
      ..reliability = WeeklyReliability(
        weekStart: DateTime(2026, 10, 5),
        score: 80,
        penaltyCount: 2,
        enabled: true,
      )
      ..history = [
        AccountabilityEvent(
          id: 'penalty-1',
          taskId: 'task-1',
          taskTitle: 'Synthetic task',
          cause: 'avoidableDelay',
          points: 10,
          status: 'confirmed',
          createdAt: DateTime(2026, 10, 7),
        ),
      ]
      ..completed = const [RecoveryTask(id: 'done-1', title: 'Разобрал почту')];
    await tester.pumpWidget(
      MaterialApp(home: GamificationScreen(service: game)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Надёжность недели'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('2 из 3 штрафов на этой неделе'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Причина: избегаемая задержка'),
      250,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic task'), findsOneWidget);
    expect(find.textContaining('Причина: избегаемая задержка'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Снять штраф'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Снять штраф'));
    await tester.pumpAndSettle();
    expect(find.text('Разобрал почту'), findsOneWidget);
    await tester.tap(find.text('Разобрал почту'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить восстановление'));
    await tester.pumpAndSettle();
    expect(game.resolved, ['penalty-1:done-1']);
  });

  testWidgets('accountability can be switched off', (tester) async {
    final game = _FakeGameData();
    await tester.pumpWidget(
      MaterialApp(home: GamificationScreen(service: game)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Switch), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(game.accountabilityChanges, [false]);
  });

  testWidgets('game screen shows levels and quests, saves a personal reward', (
    tester,
  ) async {
    final game = _FakeGameData();
    await tester.pumpWidget(
      MaterialApp(home: GamificationScreen(service: game)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Уровень 1'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    expect(find.text('Заверши одно дело'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Первый шаг'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Первый шаг'), findsOneWidget);

    await tester.tap(find.text('Награда'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Вечер кино');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Вечер кино'), 300);
    expect(find.text('Вечер кино'), findsOneWidget);
    await tester.tap(find.text('Получить'));
    await tester.pumpAndSettle();
    expect(find.text('Получено'), findsOneWidget);
  });
}

class _FakeGameData implements GamificationDataSource {
  final _rewards = <CustomReward>[];
  final _redeemed = <String, DateTime>{};
  var _nextId = 0;
  var _weeklyReviewed = false;
  WeeklyReliability? reliability;
  List<AccountabilityEvent> history = const [];
  List<RecoveryTask> completed = const [];
  final accountabilityChanges = <bool>[];
  final resolved = <String>[];

  @override
  Future<WeeklyReliability> reliabilityForWeek(DateTime date) async =>
      reliability ??
      WeeklyReliability(
        weekStart: DateTime(date.year, date.month, date.day),
        score: 100,
        penaltyCount: 0,
        enabled: true,
      );

  @override
  Future<void> setAccountabilityEnabled(bool enabled) async {
    accountabilityChanges.add(enabled);
  }

  @override
  Future<List<AccountabilityEvent>> accountabilityHistory({
    int limit = 20,
  }) async => history;

  @override
  Future<List<RecoveryTask>> completedTasks() async => completed;

  @override
  Future<void> resolvePenalty(String eventId, String recoveryTaskId) async {
    resolved.add('$eventId:$recoveryTaskId');
  }

  @override
  Future<void> awardWeeklyReview(DateTime date) async {
    _weeklyReviewed = true;
  }

  @override
  Future<bool> weeklyReviewAwarded(DateTime date) async => _weeklyReviewed;

  @override
  Future<PlayerProgress> progress() async => const PlayerProgress(
    totalXp: 15,
    level: 1,
    xpInLevel: 15,
    xpToNextLevel: 100,
  );

  @override
  Future<List<GameQuest>> dailyQuests(DateTime date) async => const [
    GameQuest(
      id: 'daily-task',
      kind: 'task',
      title: 'Заверши одно дело',
      progress: 1,
      target: 1,
      rewardXp: 5,
      completed: true,
    ),
  ];

  @override
  Future<List<GameQuest>> weeklyQuests(DateTime date) async => const [
    GameQuest(
      id: 'weekly-focus',
      kind: 'focus',
      title: 'Проведи 5 фокус-сессий',
      progress: 2,
      target: 5,
      rewardXp: 15,
      completed: false,
    ),
  ];

  @override
  Future<List<GameAchievement>> achievements() async => [
    GameAchievement(
      key: 'first_task',
      title: 'Первый шаг',
      description: 'Завершено первое дело',
      unlockedAt: DateTime(2026, 10, 8),
    ),
  ];

  @override
  Future<CustomReward> addReward(String title) async {
    final reward = CustomReward(
      id: 'reward-${_nextId++}',
      title: title,
      createdAt: DateTime(2026, 10, 8),
    );
    _rewards.add(reward);
    return reward;
  }

  @override
  Future<List<CustomReward>> rewards() async => [
    for (final reward in _rewards)
      CustomReward(
        id: reward.id,
        title: reward.title,
        createdAt: reward.createdAt,
        redeemedAt: _redeemed[reward.id],
      ),
  ];

  @override
  Future<void> redeemReward(String id, {DateTime? at}) async {
    _redeemed[id] = at ?? DateTime(2026, 10, 8);
  }
}
