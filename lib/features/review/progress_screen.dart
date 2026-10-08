import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'review_service.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.service});
  final ReviewService service;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  bool _weekly = false;
  DateTime _selected = DateTime.now();
  late Future<PeriodReview> _review;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _review = _weekly
        ? widget.service.week(_selected)
        : widget.service.day(_selected);
  }

  void _changePeriod(bool weekly) {
    setState(() {
      _weekly = weekly;
      _load();
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      _selected = date;
      _load();
    });
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color accent,
    String keyName,
  ) => Card(
    child: Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: .18), const Color(0xFF171820)],
        ),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFB7B6C4)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('День'),
              icon: Icon(Icons.today_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text('Неделя'),
              icon: Icon(Icons.date_range_rounded),
            ),
          ],
          selected: {_weekly},
          onSelectionChanged: (selection) => _changePeriod(selection.single),
        ),
      ),
      TextButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.calendar_month_rounded),
        label: Text(_rangeForCurrent()),
      ),
      FutureBuilder<PeriodReview>(
        future: _review,
        builder: (context, snapshot) {
          final review = snapshot.data;
          if (review == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.work_history_rounded, size: 18),
                  label: Text(
                    'Смены: ${review.attendedShifts} ходил · ${review.missedShifts} пропустил',
                  ),
                ),
                if (_weekly && review.reliabilityScore != null)
                  Chip(
                    avatar: const Icon(Icons.shield_rounded, size: 18),
                    label: Text('Надёжность: ${review.reliabilityScore}%'),
                  ),
              ],
            ),
          );
        },
      ),
      Expanded(
        child: FutureBuilder<PeriodReview>(
          future: _review,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Не удалось загрузить обзор: ${snapshot.error}'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final review = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.35,
                  children: [
                    _metric(
                      context,
                      Icons.task_alt_rounded,
                      'Выполнено задач',
                      '${review.completedTasks}',
                      AppTheme.mint,
                      'progress-metric-completed',
                    ),
                    _metric(
                      context,
                      Icons.timer_rounded,
                      'Фокус-сессии',
                      '${review.focusSessions}',
                      AppTheme.seed,
                      'progress-metric-focus',
                    ),
                    _metric(
                      context,
                      Icons.hourglass_bottom_rounded,
                      'Минуты фокуса',
                      '${review.focusMinutes}',
                      AppTheme.coral,
                      'progress-metric-minutes',
                    ),
                    _metric(
                      context,
                      Icons.favorite_rounded,
                      'Отметки привычек',
                      '${review.habitCheckins}',
                      AppTheme.pink,
                      'progress-metric-habits',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Цели', style: Theme.of(context).textTheme.titleLarge),
                if (review.goals.isEmpty)
                  const Card(child: ListTile(title: Text('Пока нет целей')))
                else
                  ...review.goals.map(
                    (goal) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goal.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (goal.progressPercent != null) ...[
                              LinearProgressIndicator(
                                value: goal.progressPercent! / 100,
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              goal.target == null
                                  ? '${goal.progress} ${goal.unit}'.trim()
                                  : '${goal.progress} / ${goal.target} ${goal.unit}'
                                        .trim(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );

  String _rangeForCurrent() {
    final start = _weekly
        ? _selected.subtract(Duration(days: _selected.weekday - 1))
        : DateTime(_selected.year, _selected.month, _selected.day);
    final first = MaterialLocalizations.of(context).formatMediumDate(start);
    if (!_weekly) return first;
    final last = MaterialLocalizations.of(context)
        .formatMediumDate(start.add(const Duration(days: 6)));
    return '$first — $last';
  }
}
