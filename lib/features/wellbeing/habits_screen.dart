import 'package:flutter/material.dart';

import 'wellbeing_repository.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key, required this.repository});
  final WellbeingRepository repository;

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late Future<List<Habit>> _habits;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() {
    _habits = widget.repository.listHabits();
  });

  Future<void> _add() async {
    var title = '';
    var target = 7;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Новая привычка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Название'),
                onChanged: (value) => title = value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Раз в неделю'),
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1}'),
                  ),
                ),
                onChanged: (value) => update(() => target = value ?? 7),
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
                if (title.trim().isNotEmpty) {
                  Navigator.pop(context, (title, target));
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await widget.repository.addHabit(result.$1, targetPerWeek: result.$2);
    if (mounted) _refresh();
  }

  Future<void> _toggle(Habit habit, bool checked) async {
    if (checked) {
      await widget.repository.checkIn(habit.id, DateTime.now());
    } else {
      await widget.repository.uncheck(habit.id, DateTime.now());
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Привычки')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Привычка'),
    ),
    body: FutureBuilder<List<Habit>>(
      future: _habits,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Не удалось открыть привычки: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final habits = snapshot.data!;
        if (habits.isEmpty) {
          return const Center(child: Text('Добавьте первую привычку.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: habits.length,
          itemBuilder: (context, index) {
            final habit = habits[index];
            return FutureBuilder<HabitSummary>(
              future: widget.repository.summary(habit.id, DateTime.now()),
              builder: (context, summary) {
                final value = summary.data;
                return Card(
                  child: ListTile(
                    title: Text(habit.title),
                    subtitle: Text(
                      value == null
                          ? 'Цель: ${habit.targetPerWeek} в неделю'
                          : '${value.weekCount}/${habit.targetPerWeek} за неделю · серия ${value.streak} дн.',
                    ),
                    leading: Checkbox(
                      value: value?.todayDone ?? false,
                      onChanged: value == null
                          ? null
                          : (checked) => _toggle(habit, checked ?? false),
                    ),
                    trailing: IconButton(
                      tooltip: 'Архивировать',
                      onPressed: () async {
                        await widget.repository.archiveHabit(habit.id);
                        if (mounted) _refresh();
                      },
                      icon: const Icon(Icons.archive_outlined),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}
