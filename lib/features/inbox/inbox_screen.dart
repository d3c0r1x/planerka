import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../ai/planning/ai_recommendation_service.dart';
import 'inbox_repository.dart';
import 'triage.dart';
import '../../features/ai/planning/ai_suggestion.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.repository, this.ai});

  final InboxRepository repository;
  final AiRecommendationService? ai;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось связать задачу с целью: $error')),
        );
      }
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
            title: const Text('Разбор Inbox от ИИ'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ИИ не смог разобрать Inbox: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
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
            child: Text('Не удалось открыть Inbox: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty && widget.ai == null) {
          return const Center(child: Text('Inbox пуст. Добавьте любую мысль.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length + (widget.ai == null ? 0 : 1),
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (widget.ai != null && index == 0) {
              return Card(
                child: ListTile(
                  key: const ValueKey('ai-inbox-triage'),
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Умный разбор'),
                  subtitle: const Text(
                    'ИИ предложит категории, сроки и причины',
                  ),
                  trailing: _aiLoading
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _aiLoading ? null : _suggestTriage,
                ),
              );
            }
            final entry = entries[index - (widget.ai == null ? 0 : 1)];
            return Card(
              key: ValueKey('inbox-entry-${entry.id}'),
              child: ListTile(
                title: Text(entry.title),
                subtitle: const Text('Новая запись · выбрать метку'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Связать с целью',
                      icon: const Icon(Icons.flag_circle_rounded),
                      onPressed: () => _setGoals(entry),
                    ),
                    if (widget.ai != null)
                      IconButton(
                        tooltip: 'Предложить цели с помощью ИИ',
                        icon: const Icon(Icons.auto_awesome_rounded),
                        onPressed: () => _setGoals(entry, fromAi: true),
                      ),
                    IconButton(
                      tooltip: 'Изменить',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () => _edit(entry),
                    ),
                    PopupMenuButton<TaskDisposition>(
                      tooltip: 'Разобрать',
                      icon: const Icon(Icons.sell_rounded),
                      onSelected: (disposition) => _triage(entry, disposition),
                      itemBuilder: (context) => TaskDisposition.values
                          .map(
                            (disposition) => PopupMenuItem(
                              value: disposition,
                              child: Text(dispositionLabel(disposition)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
