import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/app_theme.dart';
import '../ai/planning/ai_recommendation_service.dart';
import '../ai/ai_provider_router.dart';
import 'inbox_repository.dart';
import 'triage.dart';
import '../../features/ai/planning/ai_suggestion.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.repository,
    this.onQuickCapture,
    this.ai,
    this.onModelRequired,
    this.onAiSettingsRequired,
  });

  final InboxRepository repository;
  final VoidCallback? onQuickCapture;
  final AiRecommendationService? ai;
  final VoidCallback? onModelRequired;
  final VoidCallback? onAiSettingsRequired;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late Future<List<TaskEntry>> _entries;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.repository.listUnsorted();
  }

  void _refresh() {
    setState(() {
      _entries = widget.repository.listUnsorted();
    });
  }

  Future<void> _triage(TaskEntry entry, TaskDisposition disposition) async {
    DateTime? dueAt;
    DateTime? remindAt;
    if (disposition == TaskDisposition.quick) {
      final now = DateTime.now();
      final first = DateTime(
        now.year,
        now.month,
        now.day,
        9,
      ).subtract(const Duration(hours: 1));
      remindAt = first.isAfter(now)
          ? first
          : now.add(Duration(hours: 2 - (now.difference(first).inHours % 2)));
    }
    if (disposition == TaskDisposition.planned) {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year + 10),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 18, minute: 0),
      );
      if (time == null) return;
      dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    await widget.repository.triage(
      entry.id,
      disposition,
      dueAt: dueAt,
      remindAt: remindAt,
    );
    if (mounted) _refresh();
  }

  Future<void> _setGoals(TaskEntry entry, {bool fromAi = false}) async {
    final ai = widget.ai;
    Set<String> initial = {};
    List<AiGoalLink> suggestions = [];
    try {
      if (ai == null) return;
      final goals = await ai.listGoals();
      if (fromAi) {
        suggestions = await ai.suggestGoalLinks([entry.id]);
        initial = suggestions.map((link) => link.goalId).toSet();
      } else {
        initial = await ai.linkedGoals(entry.id);
      }
      if (!mounted || goals.isEmpty) return;
      final selected = <String>{...initial};
      final accepted = await showDialog<Set<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              fromAi
                  ? 'Предложение ИИ: связь с целью'
                  : 'Цели, которым помогает задача',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: goals.map((goal) {
                String? reason;
                for (final link in suggestions) {
                  if (link.goalId == goal.id) reason = link.reason;
                }
                return CheckboxListTile(
                  value: selected.contains(goal.id),
                  title: Text(goal.title),
                  subtitle: fromAi
                      ? Text(reason ?? 'ИИ не предложил эту цель')
                      : null,
                  onChanged: (value) => update(() {
                    if (value == true) {
                      selected.add(goal.id);
                    } else {
                      selected.remove(goal.id);
                    }
                  }),
                );
              }).toList(),
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
      await ai.updateTaskGoalLinks(
        entry.id,
        accepted,
        source: fromAi ? 'ai' : 'manual',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Связей с целями: ${accepted.length}')),
        );
      }
    } catch (error) {
      _showAiError(error, 'Не удалось связать задачу с целью');
    }
  }

  Future<void> _edit(TaskEntry entry) async {
    var draft = entry.title;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить запись'),
        content: TextFormField(
          autofocus: true,
          initialValue: entry.title,
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await widget.repository.update(entry.id, title);
    if (mounted) _refresh();
  }

  Future<void> _suggestTriage() async {
    final ai = widget.ai;
    if (ai == null || _aiLoading) return;
    setState(() => _aiLoading = true);
    try {
      final suggestion = await ai.classifyInbox();
      if (!mounted || suggestion.items.isEmpty) return;
      final selected = <String>{...suggestion.items.map((item) => item.taskId)};
      final accepted = await showDialog<Set<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Разбор входящих от ИИ'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: suggestion.items
                    .map(
                      (item) => CheckboxListTile(
                        key: ValueKey('ai-inbox-${item.taskId}'),
                        value: selected.contains(item.taskId),
                        title: Text(suggestion.titles[item.taskId] ?? 'Задача'),
                        subtitle: Text(
                          '${_dispositionTitle(item.disposition)} · ${item.reason}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add(item.taskId);
                          } else {
                            selected.remove(item.taskId);
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
                    : () => Navigator.pop(context, selected),
                child: const Text('Применить выбранное'),
              ),
            ],
          ),
        ),
      );
      if (accepted == null || accepted.isEmpty) return;
      await ai.applyInboxSelected(suggestion, accepted);
      if (mounted) _refresh();
    } catch (error) {
      _showAiError(error, 'ИИ не смог разобрать входящие');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _showAiError(Object error, String fallback) {
    if (!mounted) return;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$fallback: $error')));
  }

  String _dispositionTitle(String value) => switch (value) {
    'quick' => 'Сделать быстро',
    'planned' => 'Запланировать',
    'project' => 'Большой проект',
    'deleted' => 'Удалить',
    _ => 'Проверить',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Не удалось открыть входящие: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          itemCount:
              entries.length +
              1 +
              (widget.ai == null ? 0 : 1) +
              (entries.isEmpty ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) return _inboxHero(entries.length);
            final aiIndex = widget.ai == null ? -1 : 1;
            if (index == aiIndex) {
              return _aiTriageCard();
            }
            final emptyGuideIndex = widget.ai == null ? 1 : 2;
            if (entries.isEmpty && index == emptyGuideIndex) {
              return _emptyTriageGuide();
            }
            final entryIndex = index - (widget.ai == null ? 1 : 2);
            if (entryIndex < 0 || entryIndex >= entries.length) {
              return const SizedBox.shrink();
            }
            return _inboxEntryCard(entries[entryIndex]);
          },
        );
      },
    );
  }

  Widget _inboxHero(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('inbox-hero'),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211B38), Color(0xFF12151D), Color(0xFF101A20)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTheme.seed.withValues(alpha: .30)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.seed.withValues(alpha: .10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB79CFF), Color(0xFF7D62E8)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.inbox_rounded,
                  color: Color(0xFF171027),
                ),
              ),
              const Spacer(),
              Container(
                key: const Key('inbox-count'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.seed.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.seed.withValues(alpha: .3),
                  ),
                ),
                child: Text(
                  '$count ${_thoughtWord(count)}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Поймай мысль',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            count == 0
                ? 'Запиши всё, что крутится в голове. Разберёшь позже.'
                : 'Сначала выгрузи мысли. Потом выбери следующий шаг.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('inbox-capture'),
              onPressed: widget.onQuickCapture,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Записать задачу'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppTheme.seed,
                foregroundColor: const Color(0xFF15111F),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTriageGuide() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('inbox-empty-triage-guide'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLow,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберешь маршрут',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 3),
          Text(
            'После записи решишь, что делать с задачей.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InboxRouteHint(
                  title: 'Быстро',
                  subtitle: 'Сегодня',
                  icon: Icons.bolt_rounded,
                  color: AppTheme.coral,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InboxRouteHint(
                  title: 'Срок',
                  subtitle: 'Выбери дату',
                  icon: Icons.event_available_rounded,
                  color: AppTheme.mint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InboxRouteHint(
                  title: 'Проект',
                  subtitle: 'Разбей на шаги',
                  icon: Icons.account_tree_rounded,
                  color: AppTheme.seed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _thoughtWord(int count) {
    final lastTwo = count % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'мыслей';
    return switch (count % 10) {
      1 => 'мысль',
      2 || 3 || 4 => 'мысли',
      _ => 'мыслей',
    };
  }

  Widget _aiTriageCard() => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const ValueKey('ai-inbox-triage'),
      onTap: _aiLoading ? null : _suggestTriage,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.seed.withValues(alpha: .19),
              AppTheme.mint.withValues(alpha: .08),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.seed.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.seed,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Умный разбор',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text('ИИ предложит категории и сроки'),
                  ],
                ),
              ),
              _aiLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.mint,
                    ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _inboxEntryCard(TaskEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('inbox-entry-${entry.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: AppTheme.mint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _inboxBadge(
                  key: const Key('inbox-entry-type'),
                  label: 'На разборе',
                  color: AppTheme.mint,
                ),
                _inboxBadge(
                  key: const Key('inbox-entry-priority'),
                  label: 'Без приоритета',
                  tooltip: 'Приоритет не задан',
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                _triageChip(
                  key: const Key('inbox-triage-quick'),
                  label: 'Сделать быстро',
                  displayLabel: 'Быстро',
                  icon: Icons.bolt_rounded,
                  color: AppTheme.mint,
                  onPressed: () => _triage(entry, TaskDisposition.quick),
                ),
                const SizedBox(width: 6),
                _triageChip(
                  key: const Key('inbox-triage-planned'),
                  label: 'Запланировать',
                  displayLabel: 'Срок',
                  icon: Icons.calendar_month_rounded,
                  color: AppTheme.seed,
                  onPressed: () => _triage(entry, TaskDisposition.planned),
                ),
                const SizedBox(width: 6),
                _triageChip(
                  key: const Key('inbox-triage-project'),
                  label: 'Большой проект',
                  displayLabel: 'Проект',
                  icon: Icons.rocket_launch_rounded,
                  color: AppTheme.coral,
                  onPressed: () => _triage(entry, TaskDisposition.project),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _entryAction(
                  tooltip: 'Связать с целью',
                  icon: Icons.flag_circle_rounded,
                  color: AppTheme.coral,
                  onPressed: () => _setGoals(entry),
                ),
                if (widget.ai != null)
                  _entryAction(
                    tooltip: 'Предложить цели с помощью ИИ',
                    icon: Icons.auto_awesome_rounded,
                    color: AppTheme.seed,
                    onPressed: () => _setGoals(entry, fromAi: true),
                  ),
                _entryAction(
                  tooltip: 'Изменить',
                  icon: Icons.edit_rounded,
                  color: AppTheme.mint,
                  onPressed: () => _edit(entry),
                ),
                const Spacer(),
                PopupMenuButton<TaskDisposition>(
                  key: ValueKey('inbox-more-${entry.id}'),
                  tooltip: 'Другие действия',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (disposition) => _triage(entry, disposition),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: TaskDisposition.deleted,
                      child: Text(dispositionLabel(TaskDisposition.deleted)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryAction({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon),
    color: color,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: color.withValues(alpha: .10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    onPressed: onPressed,
  );

  Widget _inboxBadge({
    required Key key,
    required String label,
    String? tooltip,
    required Color color,
  }) => Tooltip(
    message: tooltip ?? label,
    child: Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _triageChip({
    required Key key,
    required String label,
    required String displayLabel,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) => Expanded(
    child: Tooltip(
      message: label,
      child: Semantics(
        key: key,
        label: label,
        button: true,
        onTap: onPressed,
        child: Material(
          color: color.withValues(alpha: .10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: color.withValues(alpha: .24)),
          ),
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              height: 42,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _InboxRouteHint extends StatelessWidget {
  const _InboxRouteHint({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 9,
            height: 1.15,
          ),
        ),
      ],
    ),
  );
}
