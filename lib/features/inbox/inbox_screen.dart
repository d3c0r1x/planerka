import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'inbox_repository.dart';
import 'triage.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.repository});

  final InboxRepository repository;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late Future<List<TaskEntry>> _entries;

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
        if (entries.isEmpty) {
          return const Center(child: Text('Inbox пуст. Добавьте любую мысль.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = entries[index];
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
