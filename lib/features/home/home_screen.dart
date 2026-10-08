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
    this.onReviewMissed,
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
    return ListView(
      key: const Key('home-scroll'),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_sunny_rounded, size: 16, color: AppTheme.coral),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      date,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
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
              const SizedBox(height: 11),
              _PrimaryGoalCard(
                planning: widget.planning,
                onTap: widget.onChooseGoal,
              ),
              const SizedBox(height: 10),
              _ModelStatusCard(
                store: widget.modelStore,
                downloader: widget.modelDownloader,
                onOpen: widget.onModel,
              ),
              const SizedBox(height: 10),
              _QuickInboxInput(
                controller: _input,
                onSubmit: _capture,
                saving: _saving,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
        TodayScreen(
          key: ValueKey('today-screen-${widget.isActive}'),
          repository: widget.planning,
          onReviewMissed: widget.onReviewMissed,
          embedded: true,
          onChanged: () => setState(() => _revision++),
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
          key: const Key('home-goal-hero'),
          onTap: onTap,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(17, 16, 15, 15),
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
                    width: 34,
                    height: 34,
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
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ГЛАВНАЯ ЦЕЛЬ${goals.length > 1 ? '  ·  ${goals.length}' : ''}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFD0C6F6),
                        letterSpacing: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (goal != null)
                    const ProgressPill(
                      icon: Icons.auto_awesome_rounded,
                      label: 'с ИИ',
                      color: AppTheme.mint,
                    ),
                  Icon(Icons.chevron_right_rounded, color: colors.onSurface),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                goal?.title ?? 'Выбрать главную цель',
                key: const Key('primary-goal-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: Colors.white, fontSize: 20),
              ),
              if (goal == null) ...[
                const SizedBox(height: 3),
                Text(
                  'Поставь ориентир — соберём к нему путь',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFC3BCD9)),
                ),
              ] else ...[
                const SizedBox(height: 4),
                FutureBuilder<({int completed, int total})>(
                  future: planning.goalTaskProgress(goal.id),
                  builder: (context, counts) {
                    final value = counts.data;
                    final total = value?.total ?? 0;
                    final completed = value?.completed ?? 0;
                    final progress = total == 0 ? 0.0 : completed / total;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          total == 0
                              ? 'Добавь первый шаг к цели'
                              : '$completed из $total шагов · ${(progress * 100).round()}%',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: const Color(0xFFD0C6F6)),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                                  key: const Key('home-primary-goal-progress'),
                                  value: value,
                                  minHeight: 8,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: .12,
                                  ),
                                  valueColor: const AlwaysStoppedAnimation(
                                    AppTheme.mint,
                                  ),
                                ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
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
