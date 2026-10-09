import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../ai/planning/ai_recommendation_service.dart';
import '../ai/ai_provider_router.dart';
import '../ai/model/local_ai_engine.dart';
import '../ai/model/model_manifest.dart';
import '../ai/model/model_store.dart';
import '../planning/planning_repository.dart';

typedef _GoalHeroDetails = ({int completed, int total, String? nextAction});

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.repository,
    this.ai,
    this.onModelRequired,
    this.onAiSettingsRequired,
  });

  final PlanningRepository repository;
  final AiRecommendationService? ai;
  final VoidCallback? onModelRequired;
  final VoidCallback? onAiSettingsRequired;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<Goal>> _goals;
  bool _aiLoading = false;
  Set<String> _primaryGoalIds = {};
  final Map<String, Future<_GoalHeroDetails>> _goalDetails = {};

  @override
  void initState() {
    super.initState();
    _goals = widget.repository.listGoals();
    unawaited(_loadPrimary());
  }

  void _refresh() {
    _goalDetails.clear();
    setState(() {
      _goals = widget.repository.listGoals();
    });
    unawaited(_loadPrimary());
  }

  Future<void> _loadPrimary() async {
    final goals = await widget.repository.primaryGoals();
    if (mounted) {
      setState(() => _primaryGoalIds = goals.map((goal) => goal.id).toSet());
    }
  }

  Future<void> _setPrimary(Goal goal) async {
    if (_primaryGoalIds.contains(goal.id)) {
      await _editPrimaryGoalLinks(goal);
      return;
    }
    final updated = {..._primaryGoalIds, goal.id};
    await widget.repository.setPrimaryGoals(updated);
    if (mounted) setState(() => _primaryGoalIds = updated);
  }

  Future<void> _editPrimaryGoalLinks(Goal goal) async {
    final updated = {..._primaryGoalIds}..remove(goal.id);
    await widget.repository.setPrimaryGoals(updated);
    if (mounted) setState(() => _primaryGoalIds = updated);
  }

  Future<void> _selectPrimaryGoal() async {
    final goals = await widget.repository.listGoals();
    if (!mounted || goals.isEmpty) return;
    final primary = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Главная цель'),
        children: goals
            .map(
              (goal) => SimpleDialogOption(
                key: ValueKey('choose-goal-${goal.id}'),
                onPressed: () => Navigator.pop(context, goal.id),
                child: Text(goal.title),
              ),
            )
            .toList(),
      ),
    );
    if (primary == null) return;
    await widget.repository.setPrimaryGoal(primary);
    if (mounted) _refresh();
  }

  Future<void> _selectPrimaryGoals() async {
    final goals = await widget.repository.listGoals();
    if (!mounted || goals.isEmpty) return;
    final selected = (await widget.repository.primaryGoals())
        .map((goal) => goal.id)
        .toSet();
    if (!mounted) return;
    final accepted = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Главные цели'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final goal in goals)
                CheckboxListTile(
                  value: selected.contains(goal.id),
                  title: Text(goal.title),
                  onChanged: (value) => update(() {
                    if (value == true) {
                      selected.add(goal.id);
                    } else {
                      selected.remove(goal.id);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (accepted == null) return;
    await widget.repository.setPrimaryGoals(accepted);
    if (mounted) _refresh();
  }

  Future<void> _generateSteps(Goal goal) async {
    setState(() => _aiLoading = true);
    try {
      final ai = widget.ai ?? await _localRecommendations();
      final steps = await ai.generateGoalSteps(goal.title);
      if (!mounted) return;
      final selected = <String>{...steps};
      final accepted = await showDialog<List<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Шаги от локального ИИ'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: steps
                    .map(
                      (step) => CheckboxListTile(
                        value: selected.contains(step),
                        title: Text(step),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add(step);
                          } else {
                            selected.remove(step);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected.toList()),
                child: const Text('Добавить выбранные'),
              ),
            ],
          ),
        ),
      );
      if (accepted == null || accepted.isEmpty) return;
      await widget.repository.addGoalActions(goal.id, accepted);
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено шагов: ${accepted.length}')),
        );
      }
    } catch (error) {
      if (error is StateError &&
          error.message.contains('Verified local model is not installed')) {
        widget.onModelRequired?.call();
        return;
      }
      if (error is CloudConsentRequiredException ||
          error is CloudProviderConfigurationException) {
        widget.onAiSettingsRequired?.call();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось составить шаги: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<AiRecommendationService> _localRecommendations() async {
    final root = await getApplicationSupportDirectory();
    final store = ModelStore(
      LocalModelFileStore(Directory('${root.path}/models')),
    );
    return AiRecommendationService(
      widget.repository.database,
      LocalAiEngine(store: store, manifest: Qwen3ModelManifest.manifest),
    );
  }

  Future<void> _addGoal() async {
    var title = '';
    var targetText = '';
    var unit = '';
    final result = await showDialog<(String, double?, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая цель'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (value) => title = value,
            ),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Целевое значение'),
              onChanged: (value) => targetText = value,
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Единица, необязательно',
              ),
              onChanged: (value) => unit = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (title.trim().isEmpty) return;
              final target = targetText.trim().isEmpty
                  ? null
                  : double.tryParse(targetText.replaceAll(',', '.'));
              if (targetText.trim().isNotEmpty && target == null) return;
              Navigator.pop(context, (title.trim(), target, unit.trim()));
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await widget.repository.addGoal(
      result.$1,
      target: result.$2,
      unit: result.$3,
    );
    if (mounted) _refresh();
  }

  Future<void> _updateProgress(Goal goal) async {
    var draft = goal.progress.toString();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Прогресс'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: goal.progress.toString()),
          onChanged: (text) => draft = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(draft.replaceAll(',', '.'));
              if (value == null || value < 0) return;
              Navigator.pop(context, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await widget.repository.updateGoalProgress(goal.id, value);
    if (mounted) _refresh();
  }

  String _progressLabel(Goal goal) {
    final value = goal.progress.toStringAsFixed(
      goal.progress.truncateToDouble() == goal.progress ? 0 : 1,
    );
    if (goal.target == null) return '$value ${goal.unit}'.trim();
    final target = goal.target!.toStringAsFixed(
      goal.target!.truncateToDouble() == goal.target ? 0 : 1,
    );
    return '$value / $target${goal.unit.isEmpty ? '' : ' ${goal.unit}'}';
  }

  Future<_GoalHeroDetails> _loadGoalHeroDetails(Goal goal) async {
    final counts = await widget.repository.goalTaskProgress(goal.id);
    final nextAction = await widget.repository.goalNextActionTitle(goal.id);
    return (
      completed: counts.completed,
      total: counts.total,
      nextAction: nextAction,
    );
  }

  Future<_GoalHeroDetails> _goalDetailsFor(Goal goal) {
    final cached = _goalDetails[goal.id];
    if (cached != null) return cached;
    late final Future<_GoalHeroDetails> future;
    future = _loadGoalHeroDetails(goal)
        .catchError((Object error, StackTrace stack) {
          if (identical(_goalDetails[goal.id], future)) {
            _goalDetails.remove(goal.id);
          }
          Error.throwWithStackTrace(error, stack);
        });
    _goalDetails[goal.id] = future;
    return future;
  }

  void _retryGoalDetails(String goalId) {
    setState(() => _goalDetails.remove(goalId));
  }

  Widget _goalsBanner(int total) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('goal-progress-summary'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.seed.withValues(alpha: .24), AppTheme.surfaceLow],
        ),
        border: Border.all(color: AppTheme.seed.withValues(alpha: .30)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.seed, AppTheme.pink],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(Icons.track_changes_rounded, color: Colors.black),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Твой большой курс',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_primaryGoalIds.length} главных · $total всего',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            key: const ValueKey('manage-primary-goals'),
            tooltip: 'Настроить главные цели',
            onPressed: _selectPrimaryGoals,
            icon: const Icon(Icons.tune_rounded, color: AppTheme.mint),
          ),
        ],
      ),
    );
  }

  Widget _primaryGoalHero(Goal goal) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<_GoalHeroDetails>(
      key: ValueKey('goal-progress-${goal.id}'),
      future: _goalDetailsFor(goal),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            key: const Key('primary-goal-progress'),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: .4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('Не удалось загрузить прогресс цели'),
                TextButton.icon(
                  onPressed: () => _retryGoalDetails(goal.id),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Container(
            key: const Key('primary-goal-progress'),
            margin: const EdgeInsets.only(bottom: 14),
            height: 208,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.seed.withValues(alpha: .24)),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final details = snapshot.data!;
        final progress = details.total == 0
            ? 0.0
            : details.completed / details.total;
        final percent = (progress * 100).round();
        final nextAction = details.nextAction;
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            key: const Key('primary-goal-progress'),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.seed.withValues(alpha: .27),
                  AppTheme.surfaceLow,
                  AppTheme.surfaceLow,
                ],
              ),
              border: Border.all(color: AppTheme.seed.withValues(alpha: .42)),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.seed.withValues(alpha: .12),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -50,
                  right: -40,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.mint.withValues(alpha: .17),
                          AppTheme.mint.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            color: AppTheme.mint,
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'ГЛАВНАЯ ЦЕЛЬ',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: AppTheme.mint,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            key: const ValueKey(
                              'manage-primary-goals-from-hero',
                            ),
                            tooltip: 'Настроить главные цели',
                            onPressed: _selectPrimaryGoals,
                            icon: const Icon(Icons.tune_rounded),
                            color: scheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      Text(
                        goal.title,
                        key: const Key('primary-goal-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 88,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  key: const Key('goal-task-progress'),
                                  value: progress,
                                  strokeWidth: 8,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor: scheme.surfaceContainerHigh,
                                  color: AppTheme.mint,
                                  semanticsLabel:
                                      '$percent процентов шагов цели выполнено',
                                ),
                                Text(
                                  '$percent%',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: AppTheme.mint,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${details.completed} из ${details.total} шагов выполнено',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                if (nextAction != null) ...[
                                  Text(
                                    'Следующий шаг',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: AppTheme.coral),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    nextAction,
                                    key: const Key('goal-next-action'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ] else
                                  Text(
                                    details.total == 0
                                        ? 'Добавьте шаг, чтобы видеть прогресс'
                                        : 'Все шаги выполнены',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            key: ValueKey('goal-ai-steps-${goal.id}'),
                            onPressed: _aiLoading
                                ? null
                                : () => _generateSteps(goal),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('Предложить шаги'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 46),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey('goal-metric-progress-${goal.id}'),
                            onPressed: () => _updateProgress(goal),
                            icon: const Icon(Icons.insights_rounded, size: 18),
                            label: Text('Показатель: ${_progressLabel(goal)}'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _secondaryPrimaryGoal(Goal goal) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<_GoalHeroDetails>(
      key: ValueKey('goal-progress-${goal.id}'),
      future: _goalDetailsFor(goal),
      builder: (context, snapshot) {
        final details = snapshot.data;
        final progress = details == null || details.total == 0
            ? 0.0
            : details.completed / details.total;
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.mint.withValues(alpha: .24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    color: AppTheme.mint,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    snapshot.hasError
                        ? '—'
                        : details == null
                        ? '…'
                        : '${details.completed}/${details.total}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: snapshot.hasError
                          ? scheme.onSurfaceVariant
                          : AppTheme.mint,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (snapshot.hasError)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Прогресс недоступен',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('retry-primary-goal-${goal.id}'),
                      tooltip: 'Повторить загрузку прогресса',
                      onPressed: () => _retryGoalDetails(goal.id),
                      icon: const Icon(Icons.refresh_rounded),
                      color: AppTheme.coral,
                    ),
                  ],
                )
              else
                LinearProgressIndicator(
                  key: const Key('goal-task-progress'),
                  value: details == null ? null : progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: scheme.surfaceContainerHigh,
                  color: AppTheme.mint,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _goalCard(Goal goal) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('goal-card-${goal.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        color: AppTheme.surfaceLow,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: AppTheme.coral.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flag_outlined, color: AppTheme.coral),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Личный показатель · ${_progressLabel(goal)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              TextButton.icon(
                key: ValueKey('goal-ai-steps-${goal.id}'),
                onPressed: _aiLoading ? null : () => _generateSteps(goal),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Шаги от ИИ'),
              ),
              TextButton.icon(
                key: ValueKey('primary-goal-select-${goal.id}'),
                onPressed: () => _setPrimary(goal),
                icon: const Icon(Icons.flag_rounded, size: 18),
                label: const Text('Сделать главной'),
              ),
              IconButton(
                tooltip: 'Изменить показатель',
                onPressed: () => _updateProgress(goal),
                icon: const Icon(Icons.insights_rounded),
                color: AppTheme.coral,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Цели')),
      body: FutureBuilder<List<Goal>>(
        future: _goals,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Не удалось открыть цели'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.seed, AppTheme.pink],
                        ),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: Colors.black,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Всё начинается с цели',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Добавь ориентир, разбей путь на шаги и следи за прогрессом.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 15),
                    FilledButton.icon(
                      key: const ValueKey('empty-goals-add'),
                      onPressed: _addGoal,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить цель'),
                    ),
                  ],
                ),
              ),
            );
          }
          final goals = snapshot.data!;
          final primaryGoals = goals
              .where((goal) => _primaryGoalIds.contains(goal.id))
              .toList();
          final otherGoals = goals
              .where((goal) => !_primaryGoalIds.contains(goal.id))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            children: [
              _goalsBanner(goals.length),
              if (primaryGoals.isEmpty)
                Card(
                  key: const ValueKey('select-primary-goal'),
                  color: AppTheme.surfaceLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.flag_rounded, color: AppTheme.mint),
                        const SizedBox(height: 7),
                        Text(
                          'Выбери цель, которая сейчас важнее всего',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _selectPrimaryGoal,
                          icon: const Icon(Icons.near_me_rounded),
                          label: const Text('Выбрать главную'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (primaryGoals.isNotEmpty) ...[
                _primaryGoalHero(primaryGoals.first),
                for (final goal in primaryGoals.skip(1))
                  _secondaryPrimaryGoal(goal),
              ],
              if (otherGoals.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 9),
                  child: Row(
                    children: [
                      Text(
                        'Ещё цели',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${otherGoals.length}',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: AppTheme.coral),
                      ),
                    ],
                  ),
                ),
                for (final goal in otherGoals) _goalCard(goal),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить цель',
        onPressed: _addGoal,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
