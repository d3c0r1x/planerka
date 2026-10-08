import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../ai/planning/ai_recommendation_service.dart';
import 'inbox_repository.dart';
import 'triage.dart';

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
    await widget.repository.triage(entry.id, disposition);
    if (mounted) _refresh();
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
                  subtitle: const Text('ИИ предложит категории и причины'),
                  trailing: _aiLoading
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _aiLoading ? null : _suggestTriage,
                ),
              );
            }
            final entry = entries[index - (widget.ai == null ? 0 : 1)];
            return Card(
              child: ListTile(
                title: Text(entry.title),
                subtitle: const Text('Разобрать позже'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Изменить',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () => _edit(entry),
                    ),
                    PopupMenuButton<TaskDisposition>(
                      tooltip: 'Разобрать',
                      icon: const Icon(Icons.more_horiz_rounded),
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
