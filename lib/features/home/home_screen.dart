import 'package:flutter/material.dart';

import '../planning/planning_repository.dart';
import '../planning/today_screen.dart';
import '../wellbeing/wellbeing_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.planning,
    required this.wellbeing,
    required this.onInbox,
    required this.onFocus,
    required this.onHabits,
    required this.onJournal,
  });

  final PlanningRepository planning;
  final WellbeingRepository wellbeing;
  final VoidCallback onInbox;
  final VoidCallback onFocus;
  final VoidCallback onHabits;
  final VoidCallback onJournal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context)
        .formatFullDate(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                'План на сегодня',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _DayCard(onFocus: onFocus, wellbeing: wellbeing),
              const SizedBox(height: 10),
              Text(
                'Быстрые действия',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 68,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _QuickAction(
                      icon: Icons.inbox_rounded,
                      label: 'Inbox',
                      color: colors.primaryContainer,
                      onTap: onInbox,
                    ),
                    _QuickAction(
                      icon: Icons.timer_rounded,
                      label: 'Таймер',
                      color: colors.secondaryContainer,
                      onTap: onFocus,
                    ),
                    _QuickAction(
                      icon: Icons.checklist_rounded,
                      label: 'Привычки',
                      color: colors.tertiaryContainer,
                      onTap: onHabits,
                    ),
                    _QuickAction(
                      icon: Icons.mood_rounded,
                      label: 'Дневник',
                      color: colors.surfaceContainerHighest,
                      onTap: onJournal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: TodayScreen(repository: planning)),
      ],
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
    return Card(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Один шаг за раз',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      FutureBuilder<int>(
                        future: _streak,
                        builder: (context, snapshot) => Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.local_fire_department_rounded,
                            size: 18,
                          ),
                          label: Text('${snapshot.data ?? 0}'),
                        ),
                      ),
                    ],
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: widget.onFocus,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Начать фокус'),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.auto_awesome_rounded,
              size: 44,
              color: colors.onPrimaryContainer,
            ),
          ],
        ),
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
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 82,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 25),
                const SizedBox(height: 6),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
