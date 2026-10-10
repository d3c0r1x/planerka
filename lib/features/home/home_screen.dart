import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/widgets/pressable_panel.dart';
import '../../core/models.dart';
import '../ai/model/model_downloader.dart';
import '../ai/model/model_manifest.dart';
import '../ai/model/model_store.dart';
import '../gamification/game_models.dart';
import '../gamification/gamification_service.dart';
import '../planning/planning_repository.dart';
import '../planning/today_screen.dart';
import '../wellbeing/wellbeing_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.planning,
    required this.wellbeing,
    required this.onInbox,
    required this.onFocus,
    required this.onHabits,
    required this.onJournal,
    required this.onQuickCapture,
    required this.onAiPlanning,
    required this.gamification,
    required this.onGamification,
    this.modelStore,
    this.modelDownloader,
    required this.onModel,
    this.isActive = true,
    required this.onChooseGoal,
    this.onReviewMissed,
  });

  final PlanningRepository planning;
  final WellbeingRepository wellbeing;
  final VoidCallback onInbox;
  final VoidCallback onFocus;
  final VoidCallback onHabits;
  final VoidCallback onJournal;
  final Future<void> Function(String text) onQuickCapture;
  final VoidCallback onAiPlanning;
  final GamificationDataSource gamification;
  final VoidCallback onGamification;
  final ModelStore? modelStore;
  final ModelDownloader? modelDownloader;
  final VoidCallback onModel;
  final bool isActive;
  final VoidCallback onChooseGoal;
  final Future<void> Function(String taskId)? onReviewMissed;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  bool _saving = false;
  int _revision = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final text = _input.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onQuickCapture(text);
      _input.clear();
      HapticFeedback.selectionClick();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Сохранено во входящие')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('home-scroll'),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: _PrimaryGoalCard(
            planning: widget.planning,
            onTap: widget.onChooseGoal,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _ModelStatusCard(
            store: widget.modelStore,
            downloader: widget.modelDownloader,
            onOpen: widget.onModel,
          ),
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _QuickInboxInput(
            controller: _input,
            onSubmit: _capture,
            saving: _saving,
          ),
        ),
        const SizedBox(height: 10),
        TodayScreen(
          key: ValueKey('today-screen-${widget.isActive}'),
          repository: widget.planning,
          onReviewMissed: widget.onReviewMissed,
          embedded: true,
          onChanged: () => setState(() => _revision++),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_sunny_rounded, size: 16, color: AppTheme.coral),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      MaterialLocalizations.of(context)
                          .formatFullDate(DateTime.now()),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const ProgressPill(
                    icon: Icons.auto_awesome_rounded,
                    label: 'мой ритм',
                    color: AppTheme.mint,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                'Твой день, твой ритм',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              _DayProgressStrip(
                key: ValueKey('day-counts-$_revision-${widget.isActive}'),
                planning: widget.planning,
              ),
              const SizedBox(height: 16),
              _AiPlanningShortcut(onTap: widget.onAiPlanning),
              const SizedBox(height: 9),
              _HomeGamificationCard(
                gamification: widget.gamification,
                wellbeing: widget.wellbeing,
                onTap: widget.onGamification,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.timer_rounded,
                      label: 'Таймер',
                      color: Theme.of(context).colorScheme.primary,
                      onTap: widget.onFocus,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Привычки',
                      color: AppTheme.coral,
                      onTap: widget.onHabits,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.mood_rounded,
                      label: 'Дневник',
                      color: AppTheme.pink,
                      onTap: widget.onJournal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiPlanningShortcut extends StatelessWidget {
  const _AiPlanningShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PressablePanel(
      key: const Key('home-ai-plan-shortcut'),
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF302352), Color(0xFF20233B), Color(0xFF182C36)],
        ),
        border: Border.all(
          color: const Color(0xFF9D83FF).withValues(alpha: .34),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9370FF).withValues(alpha: .10),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB394FF), Color(0xFF64D9CF)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF11121A),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Попросить ИИ составить план',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Проверишь предложения перед применением',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFD0C9E6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _HomeGamificationCard extends StatefulWidget {
  const _HomeGamificationCard({
    required this.gamification,
    required this.wellbeing,
    required this.onTap,
  });

  final GamificationDataSource gamification;
  final WellbeingRepository wellbeing;
  final VoidCallback onTap;

  @override
  State<_HomeGamificationCard> createState() => _HomeGamificationCardState();
}

class _HomeGamificationCardState extends State<_HomeGamificationCard> {
  late Future<_HomeGamificationSummary> _summary;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _HomeGamificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamification != widget.gamification ||
        oldWidget.wellbeing != widget.wellbeing) {
      _refresh();
    }
  }

  void _refresh() => _summary = _load();

  Future<_HomeGamificationSummary> _load() async {
    final progressFuture = widget.gamification.progress();
    final habits = await widget.wellbeing.listHabits();
    final today = DateTime.now();
    var bestStreak = 0;
    for (final habit in habits) {
      final summary = await widget.wellbeing.summary(habit.id, today);
      if (summary.streak > bestStreak) bestStreak = summary.streak;
    }
    return _HomeGamificationSummary(
      progress: await progressFuture,
      bestStreak: bestStreak,
      habitCount: habits.length,
    );
  }

  String _streakText(_HomeGamificationSummary summary) {
    if (summary.habitCount == 0) return 'Добавь первую привычку';
    if (summary.bestStreak == 0) return 'Начни серию сегодня';
    final lastDigit = summary.bestStreak % 10;
    final lastTwoDigits = summary.bestStreak % 100;
    final unit = lastTwoDigits >= 11 && lastTwoDigits <= 14
        ? 'дней'
        : switch (lastDigit) {
            1 => 'день',
            2 || 3 || 4 => 'дня',
            _ => 'дней',
          };
    return '${summary.bestStreak} $unit';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeGamificationSummary>(
      future: _summary,
      builder: (context, snapshot) {
        final colors = Theme.of(context).colorScheme;
        return PressablePanel(
          key: const Key('home-gamification-card'),
          onTap: widget.onTap,
          borderRadius: 21,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF252238), Color(0xFF18252D)],
            ),
            border: Border.all(
              color: const Color(0xFFFFC66D).withValues(alpha: .26),
            ),
          ),
          child: snapshot.hasError
              ? Row(
                  children: [
                    const Icon(Icons.refresh_rounded, color: Color(0xFFFFC66D)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Не удалось обновить игровой прогресс',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                )
              : snapshot.data == null
              ? const SizedBox(
                  height: 39,
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Обновляем игровой прогресс',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : _content(context, snapshot.data!),
        );
      },
    );
  }

  Widget _content(BuildContext context, _HomeGamificationSummary summary) {
    final progress = summary.progress;
    final colors = Theme.of(context).colorScheme;
    final xpProgress = progress.xpToNextLevel <= 0
        ? 0.0
        : progress.xpInLevel / progress.xpToNextLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD774), Color(0xFFFF9F69)],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFF322218),
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Твой прогресс',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Уровень ${progress.level}',
                key: const Key('home-gamification-level'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${progress.totalXp} XP',
              key: const Key('home-gamification-xp'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFFFFD774),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: xpProgress,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: .12),
            valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC66D)),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 17,
              color: Color(0xFFFF9875),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                summary.bestStreak == 0
                    ? _streakText(summary)
                    : 'Лучшая серия · ${_streakText(summary)}',
                key: const Key('home-gamification-streak'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFE3DDF1),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeGamificationSummary {
  const _HomeGamificationSummary({
    required this.progress,
    required this.bestStreak,
    required this.habitCount,
  });

  final PlayerProgress progress;
  final int bestStreak;
  final int habitCount;
}

class _PrimaryGoalCard extends StatefulWidget {
  const _PrimaryGoalCard({required this.planning, required this.onTap});
  final PlanningRepository planning;
  final VoidCallback onTap;

  @override
  State<_PrimaryGoalCard> createState() => _PrimaryGoalCardState();
}

class _PrimaryGoalCardState extends State<_PrimaryGoalCard> {
  late Future<_PrimaryGoalSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _PrimaryGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.planning != widget.planning) _reload();
  }

  void _reload() {
    _snapshot = _load();
  }

  Future<_PrimaryGoalSnapshot> _load() async {
    late final List<Goal> goals;
    try {
      goals = await widget.planning.primaryGoals();
    } catch (_) {
      return const _PrimaryGoalSnapshot.unavailable();
    }
    if (goals.isEmpty) return const _PrimaryGoalSnapshot.empty();

    final goal = goals.first;
    try {
      final progress = await widget.planning.goalTaskProgress(goal.id);
      return _PrimaryGoalSnapshot.ready(
        goal: goal,
        goalCount: goals.length,
        completed: progress.completed,
        total: progress.total,
      );
    } catch (_) {
      return _PrimaryGoalSnapshot.progressUnavailable(
        goal,
        goalCount: goals.length,
      );
    }
  }

  void _retry() => setState(_reload);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<_PrimaryGoalSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final goal = data?.goal;
        final progress = data?.progress;
        return PressablePanel(
          key: const Key('home-goal-hero'),
          onTap: widget.onTap,
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(14, 11, 13, 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF211934),
                const Color(0xFF29213F),
                const Color(0xFF252034),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: colors.primary.withValues(alpha: 0.34)),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: .12),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            key: const Key('primary-goal-card'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.primary.withValues(alpha: .32),
                      ),
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: colors.primary,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ГЛАВНАЯ ЦЕЛЬ${(data?.goalCount ?? 0) > 1 ? '  ·  ${data!.goalCount}' : ''}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFD0C6F6),
                        letterSpacing: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (goal != null)
                    Icon(Icons.chevron_right_rounded, color: colors.onSurface),
                ],
              ),
              const SizedBox(height: 6),
              if (snapshot.connectionState != ConnectionState.done)
                const _GoalReadStatus(
                  key: Key('home-primary-goal-loading'),
                  text: 'Загружаем цель и её прогресс',
                )
              else if (data?.primaryUnavailable == true)
                _GoalRetryStatus(
                  key: const Key('home-primary-goal-unavailable'),
                  text: 'Не удалось загрузить главную цель',
                  onRetry: _retry,
                  retryKey: const Key('home-primary-goal-retry'),
                )
              else if (goal == null)
                Text(
                  'Выбрать главную цель',
                  key: const Key('primary-goal-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else ...[
                Text(
                  goal.title,
                  key: const Key('primary-goal-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                if (progress == null)
                  _GoalRetryStatus(
                    key: const Key('home-goal-progress-unavailable'),
                    text: 'Прогресс цели сейчас недоступен',
                    onRetry: _retry,
                    retryKey: const Key('home-goal-progress-retry'),
                  )
                else
                  _GoalProgress(
                    completed: progress.completed,
                    total: progress.total,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PrimaryGoalSnapshot {
  const _PrimaryGoalSnapshot._({
    this.goal,
    this.progress,
    this.goalCount = 0,
    this.primaryUnavailable = false,
  });

  const _PrimaryGoalSnapshot.unavailable() : this._(primaryUnavailable: true);
  const _PrimaryGoalSnapshot.empty() : this._();
  const _PrimaryGoalSnapshot.ready({
    required Goal goal,
    required int goalCount,
    required int completed,
    required int total,
  }) : this._(
         goal: goal,
         goalCount: goalCount,
         progress: (completed: completed, total: total),
       );
  const _PrimaryGoalSnapshot.progressUnavailable(
    Goal goal, {
    required int goalCount,
  }) : this._(goal: goal, goalCount: goalCount);

  final Goal? goal;
  final ({int completed, int total})? progress;
  final int goalCount;
  final bool primaryUnavailable;
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'Добавь первый шаг к цели'
              : '$completed из $total шагов · ${(progress * 100).round()}%',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: const Color(0xFFD0C6F6)),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              key: const Key('home-primary-goal-progress'),
              value: value,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: .12),
              valueColor: const AlwaysStoppedAnimation(AppTheme.mint),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalReadStatus extends StatelessWidget {
  const _GoalReadStatus({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox.square(
        dimension: 15,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.mint),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      ),
    ],
  );
}

class _GoalRetryStatus extends StatelessWidget {
  const _GoalRetryStatus({
    super.key,
    required this.text,
    required this.onRetry,
    required this.retryKey,
  });

  final String text;
  final VoidCallback onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: const Color(0xFFFFB6A8)),
        ),
      ),
      TextButton(
        key: retryKey,
        onPressed: onRetry,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 34),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Повторить'),
      ),
    ],
  );
}

class _ModelStatusCard extends StatefulWidget {
  const _ModelStatusCard({
    required this.store,
    required this.downloader,
    required this.onOpen,
  });
  final ModelStore? store;
  final ModelDownloader? downloader;
  final VoidCallback onOpen;

  @override
  State<_ModelStatusCard> createState() => _ModelStatusCardState();
}

class _ModelStatusCardState extends State<_ModelStatusCard> {
  StreamSubscription<ModelDownloadState>? _subscription;
  ModelDownloadState? _state;
  bool _ready = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ModelStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) unawaited(_check());
    if (oldWidget.downloader != widget.downloader) _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    final current = widget.downloader?.currentState;
    if (current != null) {
      _state = current;
      _ready = current.status == ModelDownloadStatus.ready;
    }
    _subscription = widget.downloader?.backgroundStates.listen((state) {
      if (mounted) {
        setState(() {
          _state = state;
          _ready = state.status == ModelDownloadStatus.ready;
          _checking = false;
        });
      }
    });
  }

  Future<void> _check() async {
    final store = widget.store;
    if (store == null) return;
    if (mounted) setState(() => _checking = true);
    try {
      final ready = await store.verifiedModel(Qwen3ModelManifest.manifest);
      if (mounted) {
        setState(() {
          _ready = ready != null;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
          _checking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_ready) return const SizedBox.shrink();
    final downloading = _state?.status == ModelDownloadStatus.downloading;
    return PressablePanel(
      key: const ValueKey('home-model-status'),
      onTap: widget.onOpen,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.58),
        border: Border.all(color: colors.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                downloading
                    ? Icons.downloading_rounded
                    : Icons.smart_toy_rounded,
                color: colors.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _checking
                      ? 'Проверяем локальную модель'
                      : downloading
                      ? 'Скачиваем локальный ИИ'
                      : _state?.status == ModelDownloadStatus.paused
                      ? 'Загрузка ИИ приостановлена'
                      : _state?.status == ModelDownloadStatus.failed
                      ? 'Загрузка ИИ не завершена'
                      : 'ИИ на устройстве не установлен',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _state?.progress),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${((_state?.receivedBytes ?? 0) / 1000000).round()} / ${((_state?.totalBytes ?? 0) / 1000000).round()} МБ',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
          if (_state?.status == ModelDownloadStatus.failed &&
              _state?.message != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _state!.message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickInboxInput extends StatelessWidget {
  const _QuickInboxInput({
    required this.controller,
    required this.onSubmit,
    required this.saving,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.only(left: 15, right: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, color: AppTheme.coral),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('home-inbox-input'),
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                hintText: 'Записать мысль…',
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('home-inbox-submit'),
            tooltip: 'Сохранить во входящие',
            onPressed: saving ? null : onSubmit,
            icon: saving
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _DayProgressStrip extends StatefulWidget {
  const _DayProgressStrip({super.key, required this.planning});
  final PlanningRepository planning;

  @override
  State<_DayProgressStrip> createState() => _DayProgressStripState();
}

class _DayProgressStripState extends State<_DayProgressStrip> {
  late final Future<({int completed, int total, int overdue})> _counts =
      _load();

  Future<({int completed, int total, int overdue})> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = DateTime(now.year, now.month, now.day + 1).toUtc();
    final completedRows = await widget.planning.database.database.rawQuery(
      "SELECT COUNT(*) AS count FROM tasks WHERE status = 'completed' "
      'AND completed_at >= ? AND completed_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    final completed = (completedRows.single['count'] as num).toInt();
    final today = await widget.planning.listForDay(now);
    final overdue = await widget.planning.listOverdue(now);
    return (
      completed: completed,
      total: completed + today.length,
      overdue: overdue.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<({int completed, int total, int overdue})>(
      future: _counts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Не удалось обновить итоги дня');
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 30,
            child: Text('Загружаем итоги дня…'),
          );
        }
        final completed = snapshot.data?.completed ?? 0;
        final total = snapshot.data?.total ?? 0;
        final overdue = snapshot.data?.overdue ?? 0;
        final progress = total == 0 ? 0.0 : completed / total;
        return Column(
          key: const Key('home-day-progress'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$completed из $total выполнено',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (overdue > 0)
                  Text(
                    '$overdue просрочено',
                    style: const TextStyle(color: AppTheme.coral, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: colors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(colors.tertiary),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressablePanel(
    onTap: onTap,
    borderRadius: 16,
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 7),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.07)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
