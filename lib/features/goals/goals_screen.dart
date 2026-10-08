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

  @override
  void initState() {
    super.initState();
    _goals = widget.repository.listGoals();
    unawaited(_loadPrimary());
  }

  void _refresh() {
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
            return const Center(
              child: Text('Добавьте цель, которую хотите видеть в прогрессе.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                key: const Key('goal-progress-summary'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF282044), Color(0xFF151820)],
                  ),
                  border: Border.all(
                    color: AppTheme.seed.withValues(alpha: .4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.seed.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.track_changes_rounded,
                        color: Color(0xFFC6B4FF),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Твои ориентиры',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_primaryGoalIds.length} главных · путь складывается из шагов',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFFB7B6C4)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('manage-primary-goals'),
                      tooltip: 'Настроить главные цели',
                      onPressed: _selectPrimaryGoals,
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: AppTheme.mint,
                      ),
                    ),
                  ],
                ),
              ),
              if (_primaryGoalIds.isEmpty)
                Card(
                  child: ListTile(
                    key: const ValueKey('select-primary-goal'),
                    leading: const Icon(Icons.flag_rounded),
                    title: const Text('Выбрать главную цель'),
                    onTap: _selectPrimaryGoal,
                  ),
                ),
              for (final primary in snapshot.data!.where(
                (goal) => _primaryGoalIds.contains(goal.id),
              ))
                FutureBuilder<({int completed, int total})>(
                  key: ValueKey('goal-progress-${primary.id}'),
                  future: widget.repository.goalTaskProgress(primary.id),
                  builder: (context, counts) {
                    final value = counts.data;
                    final total = value?.total ?? 0;
                    final progress = total == 0
                        ? 0.0
                        : (value!.completed / total);
                    return Container(
                      key: const Key('primary-goal-progress'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: const Color(0xFF171820),
                        border: Border.all(
                          color: AppTheme.mint.withValues(alpha: .3),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Главная цель',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: AppTheme.mint,
                                    letterSpacing: .5,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              primary.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                key: const Key('goal-task-progress'),
                                value: progress,
                                minHeight: 9,
                                backgroundColor: const Color(0xFF30313B),
                                color: AppTheme.mint,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${value?.completed ?? 0} из $total шагов выполнено',
                            ),
                            if (total == 0) ...[
                              const SizedBox(height: 4),
                              const Text('Добавьте шаг, чтобы видеть прогресс'),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ...snapshot.data!.map((goal) {
                final isPrimary = _primaryGoalIds.contains(goal.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: const Color(0xFF14151B),
                    border: Border.all(
                      color: isPrimary
                          ? AppTheme.seed.withValues(alpha: .55)
                          : const Color(0xFF292A34),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(goal.title),
                        subtitle: Text(
                          isPrimary
                              ? 'Главная · шаги: ${_progressLabel(goal)}'
                              : _progressLabel(goal),
                        ),
                        trailing: FutureBuilder<({int completed, int total})>(
                          future: widget.repository.goalTaskProgress(goal.id),
                          builder: (context, counts) {
                            final value = counts.data;
                            final total = value?.total ?? 0;
                            final taskProgress = total == 0
                                ? 0.0
                                : value!.completed / total;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPrimary)
                                  SizedBox(
                                    width: 38,
                                    height: 38,
                                    child: CircularProgressIndicator(
                                      value: taskProgress,
                                      strokeWidth: 4,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Сделать главной целью',
                                  onPressed: () => _setPrimary(goal),
                                  icon: Icon(
                                    isPrimary
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            key: ValueKey('goal-ai-steps-${goal.id}'),
                            onPressed: _aiLoading
                                ? null
                                : () => _generateSteps(goal),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('Шаги от ИИ'),
                          ),
                          TextButton.icon(
                            key: ValueKey('primary-goal-select-${goal.id}'),
                            onPressed: () => _setPrimary(goal),
                            icon: Icon(
                              isPrimary
                                  ? Icons.star_rounded
                                  : Icons.flag_rounded,
                            ),
                            label: Text(
                              isPrimary ? 'Главная' : 'Сделать главной',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Обновить прогресс',
                            onPressed: () => _updateProgress(goal),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
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
