import 'package:flutter/material.dart';

import 'game_models.dart';
import 'gamification_service.dart';

class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key, required this.service});

  final GamificationDataSource service;

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends State<GamificationScreen> {
  late Future<_GameDashboard> _dashboard;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _dashboard = _load();
  }

  Future<_GameDashboard> _load() async {
    final now = DateTime.now();
    final daily = await widget.service.dailyQuests(now);
    final weekly = await widget.service.weeklyQuests(now);
    final progress = await widget.service.progress();
    final achievements = await widget.service.achievements();
    final rewards = await widget.service.rewards();
    final reviewed = await widget.service.weeklyReviewAwarded(now);
    final reliability = await widget.service.reliabilityForWeek(now);
    final accountabilityHistory = await widget.service.accountabilityHistory();
    return _GameDashboard(
      progress: progress,
      dailyQuests: daily,
      weeklyQuests: weekly,
      achievements: achievements,
      rewards: rewards,
      weeklyReviewed: reviewed,
      reliability: reliability,
      accountabilityHistory: accountabilityHistory,
    );
  }

  Future<void> _addReward() async {
    var draft = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Своя награда'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'За что себя порадовать?',
          ),
          onChanged: (value) => draft = value,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    await widget.service.addReward(title);
    if (mounted) setState(_refresh);
  }

  Future<void> _redeem(CustomReward reward) async {
    await widget.service.redeemReward(reward.id);
    if (mounted) setState(_refresh);
  }

  Future<void> _reviewWeek() async {
    await widget.service.awardWeeklyReview(DateTime.now());
    if (mounted) setState(_refresh);
  }

  Future<void> _setAccountabilityEnabled(bool enabled) async {
    try {
      await widget.service.setAccountabilityEnabled(enabled);
      if (mounted) setState(_refresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось изменить настройку')),
        );
      }
    }
  }

  Future<void> _resolvePenalty(AccountabilityEvent event) async {
    final tasks = await widget.service.completedTasks();
    if (!mounted) return;
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сначала заверши дело, которое станет шагом восстановления',
          ),
        ),
      );
      return;
    }
    final task = await showDialog<RecoveryTask>(
      context: context,
      builder: (context) => _RecoveryTaskDialog(tasks: tasks),
    );
    if (task == null || !mounted) return;
    try {
      await widget.service.resolvePenalty(event.id, task.id);
      if (mounted) setState(_refresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отметить восстановление')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Игровой прогресс')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReward,
        icon: const Icon(Icons.card_giftcard_rounded),
        label: const Text('Награда'),
      ),
      body: FutureBuilder<_GameDashboard>(
        future: _dashboard,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Не удалось загрузить прогресс: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final progress = data.progress;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _levelCard(context, progress),
              const SizedBox(height: 18),
              _sectionTitle(context, 'Задания на сегодня'),
              ...data.dailyQuests.map((quest) => _questCard(context, quest)),
              const SizedBox(height: 12),
              _sectionTitle(context, 'Цель недели'),
              ...data.weeklyQuests.map((quest) => _questCard(context, quest)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: data.weeklyReviewed ? null : _reviewWeek,
                icon: const Icon(Icons.event_available_rounded),
                label: Text(
                  data.weeklyReviewed
                      ? 'Обзор недели отмечен'
                      : 'Отметить обзор недели',
                ),
              ),
              const SizedBox(height: 18),
              _accountabilityCard(data),
              const SizedBox(height: 18),
              _sectionTitle(context, 'Достижения'),
              if (data.achievements.isEmpty)
                const Card(
                  child: ListTile(title: Text('Первые награды начнутся с дел')),
                )
              else
                ...data.achievements.map(
                  (item) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.emoji_events_rounded),
                      ),
                      title: Text(item.title),
                      subtitle: Text(item.description),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              _sectionTitle(context, 'Мои награды'),
              if (data.rewards.isEmpty)
                const Card(
                  child: ListTile(title: Text('Добавь награду для себя')),
                )
              else
                ...data.rewards.map(
                  (reward) => Card(
                    child: ListTile(
                      leading: Icon(
                        reward.redeemedAt == null
                            ? Icons.card_giftcard_rounded
                            : Icons.check_circle_rounded,
                      ),
                      title: Text(reward.title),
                      trailing: reward.redeemedAt == null
                          ? TextButton(
                              onPressed: () => _redeem(reward),
                              child: const Text('Получить'),
                            )
                          : const Text('Получено'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _accountabilityCard(_GameDashboard data) {
    final reliability = data.reliability;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.shield_moon_rounded,
                  color: Colors.lightBlueAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Надёжность недели',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${reliability.score}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: reliability.score >= 90
                        ? Colors.lightGreenAccent
                        : Colors.orangeAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: reliability.score / 100),
            const SizedBox(height: 8),
            Text('${reliability.penaltyCount} из 3 штрафов на этой неделе'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Система ответственности'),
              subtitle: Text(
                reliability.enabled
                    ? 'Штраф только после подтверждения причины'
                    : 'Штрафы выключены',
              ),
              value: reliability.enabled,
              onChanged: _setAccountabilityEnabled,
            ),
            const Divider(),
            Text(
              'История',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (data.accountabilityHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Подтверждённых штрафов пока нет'),
              )
            else
              ...data.accountabilityHistory.map(_accountabilityEventTile),
          ],
        ),
      ),
    );
  }

  Widget _accountabilityEventTile(AccountabilityEvent event) {
    final resolved = event.status == 'resolved';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        resolved
            ? Icons.auto_awesome_rounded
            : Icons.remove_circle_outline_rounded,
        color: resolved ? Colors.lightGreenAccent : Colors.orangeAccent,
      ),
      title: Text(
        resolved
            ? 'Штраф снят восстановительным шагом'
            : 'Штраф подтверждён · −${event.points}',
      ),
      subtitle: Text(
        '${event.taskTitle}\nПричина: ${_causeLabel(event.cause)} · ${_formatDate(event.createdAt)}',
      ),
      isThreeLine: false,
      trailing: !resolved && event.status == 'confirmed'
          ? TextButton(
              onPressed: () => _resolvePenalty(event),
              child: const Text('Снять штраф'),
            )
          : null,
    );
  }

  String _causeLabel(String cause) => switch (cause) {
    'avoidableDelay' => 'избегаемая задержка',
    'externalObstacle' => 'внешнее препятствие',
    'estimateWrong' => 'ошибка оценки',
    'priorityChanged' => 'смена приоритета',
    _ => 'причина не указана',
  };

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  Widget _levelCard(BuildContext context, PlayerProgress progress) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.stars_rounded,
                  size: 34,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Уровень ${progress.level}',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${progress.totalXp} XP',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: progress.xpInLevel / progress.xpToNextLevel,
            ),
            const SizedBox(height: 8),
            Text(
              '${progress.xpInLevel} / ${progress.xpToNextLevel} XP до следующего уровня',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _questCard(BuildContext context, GameQuest quest) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quest.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('+${quest.rewardXp} XP'),
              if (quest.completed) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded),
              ],
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: quest.progress / quest.target),
          const SizedBox(height: 4),
          Text('${quest.progress} / ${quest.target}'),
        ],
      ),
    ),
  );
}

class _GameDashboard {
  const _GameDashboard({
    required this.progress,
    required this.dailyQuests,
    required this.weeklyQuests,
    required this.achievements,
    required this.rewards,
    required this.weeklyReviewed,
    required this.reliability,
    required this.accountabilityHistory,
  });

  final PlayerProgress progress;
  final List<GameQuest> dailyQuests;
  final List<GameQuest> weeklyQuests;
  final List<GameAchievement> achievements;
  final List<CustomReward> rewards;
  final bool weeklyReviewed;
  final WeeklyReliability reliability;
  final List<AccountabilityEvent> accountabilityHistory;
}

class _RecoveryTaskDialog extends StatefulWidget {
  const _RecoveryTaskDialog({required this.tasks});

  final List<RecoveryTask> tasks;

  @override
  State<_RecoveryTaskDialog> createState() => _RecoveryTaskDialogState();
}

class _RecoveryTaskDialogState extends State<_RecoveryTaskDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Восстановительный шаг'),
    content: SizedBox(
      width: double.maxFinite,
      child: RadioGroup<String>(
        groupValue: _selectedId,
        onChanged: (value) => setState(() => _selectedId = value),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Выбери завершённое дело, которое помогло вернуться в ритм.',
            ),
            const SizedBox(height: 8),
            ...widget.tasks.map(
              (task) => RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(task.title),
                value: task.id,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _selectedId == null
            ? null
            : () => Navigator.pop(
                context,
                widget.tasks.firstWhere((task) => task.id == _selectedId),
              ),
        child: const Text('Подтвердить восстановление'),
      ),
    ],
  );
}
