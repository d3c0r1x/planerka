import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/widgets/pressable_panel.dart';
import '../../core/models.dart';
import '../ai/model/model_downloader.dart';
import '../ai/model/model_manifest.dart';
import '../ai/model/model_store.dart';
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
    this.modelStore,
    this.modelDownloader,
    required this.onModel,
    this.isActive = true,
    required this.onChooseGoal,
  });

  final PlanningRepository planning;
  final WellbeingRepository wellbeing;
  final VoidCallback onInbox;
  final VoidCallback onFocus;
  final VoidCallback onHabits;
  final VoidCallback onJournal;
  final Future<void> Function(String text) onQuickCapture;
  final ModelStore? modelStore;
  final ModelDownloader? modelDownloader;
  final VoidCallback onModel;
  final bool isActive;
  final VoidCallback onChooseGoal;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  bool _saving = false;

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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Сохранено во Inbox')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context)
        .formatFullDate(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 3, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 1),
              Text(
                'Твой день, твой ритм',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 7),
              _DayProgressStrip(planning: widget.planning),
              const SizedBox(height: 10),
              _PrimaryGoalCard(
                planning: widget.planning,
                onTap: widget.onChooseGoal,
              ),
              const SizedBox(height: 9),
              _ModelStatusCard(
                store: widget.modelStore,
                downloader: widget.modelDownloader,
                onOpen: widget.onModel,
              ),
              const SizedBox(height: 9),
              _QuickInboxInput(
                controller: _input,
                onSubmit: _capture,
                saving: _saving,
              ),
              const SizedBox(height: 9),
              _DayCard(onFocus: widget.onFocus, wellbeing: widget.wellbeing),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.inbox_rounded,
                      label: 'Inbox',
                      color: AppTheme.mint,
                      onTap: widget.onInbox,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.timer_rounded,
                      label: 'Таймер',
                      color: colors.primary,
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
                  const SizedBox(width: 8),
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
        Expanded(
          child: TodayScreen(
            key: ValueKey('today-screen-${widget.isActive}'),
            repository: widget.planning,
          ),
        ),
      ],
    );
  }
}

class _PrimaryGoalCard extends StatelessWidget {
  const _PrimaryGoalCard({required this.planning, required this.onTap});
  final PlanningRepository planning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<Goal>>(
      future: planning.primaryGoals(),
      builder: (context, snapshot) {
        final goals = snapshot.data ?? const <Goal>[];
        final goal = goals.isEmpty ? null : goals.first;
        return PressablePanel(
          key: const Key('primary-goal-card'),
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.primaryContainer,
                Color.lerp(colors.primaryContainer, colors.tertiary, 0.18)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.flag_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ГЛАВНАЯ ЦЕЛЬ',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal?.title ?? 'Выбрать цель',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (goal != null)
                      FutureBuilder<({int completed, int total})>(
                        future: planning.goalTaskProgress(goal.id),
                        builder: (context, counts) {
                          final value = counts.data;
                          return Text(
                            '${value?.completed ?? 0} из ${value?.total ?? 0} шагов выполнено',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onPrimaryContainer.withValues(
                                    alpha: 0.76,
                                  ),
                                ),
                          );
                        },
                      ),
                    if (goal != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: FutureBuilder<({int completed, int total})>(
                          future: planning.goalTaskProgress(goal.id),
                          builder: (context, counts) {
                            final value = counts.data;
                            final progress = value == null || value.total == 0
                                ? 0.0
                                : value.completed / value.total;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                key: const Key('home-primary-goal-progress'),
                                value: progress,
                                minHeight: 6,
                                backgroundColor: colors.onPrimaryContainer
                                    .withValues(alpha: .16),
                                valueColor: AlwaysStoppedAnimation(
                                  colors.tertiary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (goals.length > 1)
                      Text(
                        '+ ещё ${goals.length - 1} цели',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer.withValues(
                            alpha: .78,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (goal != null)
                FutureBuilder<({int completed, int total})>(
                  future: planning.goalTaskProgress(goal.id),
                  builder: (context, counts) {
                    final value = counts.data;
                    final total = value?.total ?? 0;
                    return ProgressPill(
                      icon: Icons.auto_awesome_rounded,
                      label: '${value?.completed ?? 0}/$total',
                      color: colors.tertiary,
                    );
                  },
                )
              else
                ProgressPill(
                  icon: Icons.auto_awesome_rounded,
                  label: 'с ИИ',
                  color: colors.tertiary,
                ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onPrimaryContainer,
              ),
            ],
          ),
        );
      },
    );
  }
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

  @override
  void initState() {
    super.initState();
    _check();
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
        });
      }
    });
  }

  Future<void> _check() async {
    final ready = await widget.store?.verifiedModel(
      Qwen3ModelManifest.manifest,
    );
    if (mounted) setState(() => _ready = ready != null);
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
                  downloading
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
            tooltip: 'Сохранить во Inbox',
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

class _DayProgressStrip extends StatelessWidget {
  const _DayProgressStrip({required this.planning});
  final PlanningRepository planning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        planning.listForDay(DateTime.now()),
        planning.listOverdue(DateTime.now()),
        planning.listUnscheduled(),
      ]),
      builder: (context, snapshot) {
        final today = snapshot.data?.first ?? const [];
        final overdue = snapshot.data?[1] ?? const [];
        final backlog = snapshot.data?.last ?? const [];
        final planned = today.length + backlog.length;
        final progress = planned == 0 ? 0.0 : today.length / planned;
        return Row(
          key: const Key('home-day-progress'),
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: progress,
                  backgroundColor: colors.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colors.tertiary),
                ),
              ),
            ),
            const SizedBox(width: 9),
            ProgressPill(
              icon: Icons.check_circle_rounded,
              label: '${today.length} сегодня',
              color: colors.tertiary,
            ),
            if (overdue.isNotEmpty) ...[
              const SizedBox(width: 6),
              ProgressPill(
                icon: Icons.alarm_rounded,
                label: '${overdue.length} срок',
                color: AppTheme.coral,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DayCard extends StatefulWidget {
  const _DayCard({required this.onFocus, required this.wellbeing});
  final VoidCallback onFocus;
  final WellbeingRepository wellbeing;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  late final Future<int> _streak;

  @override
  void initState() {
    super.initState();
    _streak = _longestStreak();
  }

  Future<int> _longestStreak() async {
    final habits = await widget.wellbeing.listHabits();
    var longest = 0;
    for (final habit in habits) {
      final summary = await widget.wellbeing.summary(habit.id, DateTime.now());
      if (summary.streak > longest) longest = summary.streak;
    }
    return longest;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHigh,
            colors.surfaceContainer.withValues(alpha: 0.82),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.tertiary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: colors.tertiary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Твой ритм',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                FutureBuilder<int>(
                  future: _streak,
                  builder: (context, snapshot) => Text(
                    '${snapshot.data ?? 0} дней подряд',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: colors.primary.withValues(alpha: 0.16),
              foregroundColor: colors.primary,
            ),
            onPressed: widget.onFocus,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Фокус'),
          ),
        ],
      ),
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
    borderRadius: 20,
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.07)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 23),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
