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
  late Future<PeriodReview> _previousReview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _review = _weekly
        ? widget.service.week(_selected)
        : widget.service.day(_selected);
    _previousReview = _weekly
        ? widget.service.week(_selected.subtract(const Duration(days: 7)))
        : widget.service.day(_selected.subtract(const Duration(days: 1)));
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

  Widget _periodHero(PeriodReview review) => Card(
    key: const Key('progress-period-hero'),
    margin: EdgeInsets.zero,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF382A62), Color(0xFF191926), Color(0xFF141923)],
        ),
        border: Border.all(color: AppTheme.seed.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.mint.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.mint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _weekly
                      ? 'ТВОЯ НЕДЕЛЯ'
                      : DateUtils.isSameDay(_selected, DateTime.now())
                      ? 'СЕГОДНЯ'
                      : 'ВЫБРАННЫЙ ДЕНЬ',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.mint,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${review.completedTasks} ${_taskWord(review.completedTasks)} ${_taskVerb(review.completedTasks)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${review.focusMinutes} мин фокуса · ${review.habitCheckins} отметок привычек',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _taskWord(int count) {
    final remainder10 = count % 10;
    final remainder100 = count % 100;
    if (remainder10 == 1 && remainder100 != 11) return 'задача';
    if (remainder10 >= 2 &&
        remainder10 <= 4 &&
        (remainder100 < 12 || remainder100 > 14)) {
      return 'задачи';
    }
    return 'задач';
  }

  String _taskVerb(int count) {
    final remainder10 = count % 10;
    final remainder100 = count % 100;
    if (remainder10 == 1 && remainder100 != 11) return 'выполнена';
    if (remainder10 >= 2 &&
        remainder10 <= 4 &&
        (remainder100 < 12 || remainder100 > 14)) {
      return 'выполнены';
    }
    return 'выполнено';
  }

  String _delta(String label, int value, int previous) {
    final difference = value - previous;
    final amount = difference > 0
        ? '+$difference'
        : difference < 0
        ? '−${difference.abs()}'
        : '±0';
    return '$label $amount';
  }

  String _formatMood(double value) =>
      value.toStringAsFixed(1).replaceFirst('.', ',');

  String _moodDelta(double current, double previous) {
    final difference = current - previous;
    final amount = difference > 0
        ? '+${_formatMood(difference)}'
        : difference < 0
        ? '−${_formatMood(difference.abs())}'
        : '±0,0';
    return 'Настроение $amount';
  }

  String _moodCountLabel(int count) {
    final remainder10 = count % 10;
    final remainder100 = count % 100;
    if (remainder10 == 1 && remainder100 != 11) return '$count отметка';
    if (remainder10 >= 2 &&
        remainder10 <= 4 &&
        (remainder100 < 12 || remainder100 > 14)) {
      return '$count отметки';
    }
    return '$count отметок';
  }

  Widget _moodCard(PeriodReview review) {
    final average = review.averageMood;
    final accent = average == null || average < 2.5
        ? AppTheme.coral
        : average < 3.5
        ? AppTheme.seed
        : AppTheme.mint;
    final icon = average == null
        ? Icons.mood_rounded
        : average < 1.5
        ? Icons.sentiment_very_dissatisfied_rounded
        : average < 2.5
        ? Icons.sentiment_dissatisfied_rounded
        : average < 3.5
        ? Icons.sentiment_neutral_rounded
        : average < 4.5
        ? Icons.sentiment_satisfied_rounded
        : Icons.sentiment_very_satisfied_rounded;
    return Card(
      key: const Key('progress-mood-card'),
      margin: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .19),
              AppTheme.surfaceLow,
              AppTheme.surface,
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: .24)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accent, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Настроение',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  if (average == null)
                    Text(
                      'Нет отметок за этот период',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    Text(
                      '${_formatMood(average)} из 5',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _moodCountLabel(review.moodRatingsCount),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (average / 5).clamp(0, 1),
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: .1),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonCard(PeriodReview current) => FutureBuilder<PeriodReview>(
    future: _previousReview,
    builder: (context, snapshot) {
      final previous = snapshot.data;
      if (snapshot.hasError) {
        return const Card(
          key: Key('progress-period-comparison-unavailable'),
          child: ListTile(
            leading: Icon(Icons.cloud_off_rounded),
            title: Text('Сравнение периода недоступно'),
          ),
        );
      }
      if (previous == null) return const SizedBox.shrink();
      final isToday = DateUtils.isSameDay(_selected, DateTime.now());
      final title = _weekly
          ? 'Сравнение с прошлой неделей'
          : isToday
          ? 'Сравнение со вчера'
          : 'Сравнение с предыдущим днём';
      return Card(
        key: const Key('progress-period-comparison'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.compare_arrows_rounded,
                    color: AppTheme.seed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _comparisonPill(
                    _delta(
                      'Задачи',
                      current.completedTasks,
                      previous.completedTasks,
                    ),
                    AppTheme.mint,
                  ),
                  _comparisonPill(
                    _delta(
                      'Сессии',
                      current.focusSessions,
                      previous.focusSessions,
                    ),
                    AppTheme.seed,
                  ),
                  _comparisonPill(
                    _delta(
                      'Привычки',
                      current.habitCheckins,
                      previous.habitCheckins,
                    ),
                    AppTheme.coral,
                  ),
                  if (current.averageMood != null &&
                      previous.averageMood != null)
                    _comparisonPill(
                      _moodDelta(current.averageMood!, previous.averageMood!),
                      AppTheme.pink,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _comparisonPill(String label, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withValues(alpha: .22)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: accent, fontWeight: FontWeight.w800),
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
                _periodHero(review),
                const SizedBox(height: 10),
                _comparisonCard(review),
                const SizedBox(height: 10),
                _moodCard(review),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount:
                      MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 1 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio:
                      MediaQuery.textScalerOf(context).scale(1) > 1.15
                      ? 2
                      : 1.35,
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
