import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../planning/planning_repository.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.repository});

  final PlanningRepository repository;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<Goal>> _goals;

  @override
  void initState() {
    super.initState();
    _goals = widget.repository.listGoals();
  }

  void _refresh() {
    setState(() {
      _goals = widget.repository.listGoals();
    });
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
            children: snapshot.data!
                .map(
                  (goal) => Card(
                    child: ListTile(
                      title: Text(goal.title),
                      subtitle: Text(_progressLabel(goal)),
                      trailing: IconButton(
                        tooltip: 'Обновить прогресс',
                        onPressed: () => _updateProgress(goal),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ),
                )
                .toList(),
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
