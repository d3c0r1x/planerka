import 'package:flutter/material.dart';

import 'wellbeing_repository.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.repository});
  final WellbeingRepository repository;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late Future<List<JournalEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() {
    _entries = widget.repository.listJournal();
  });

  Future<void> _edit([JournalEntry? entry]) async {
    var text = entry?.text ?? '';
    int? mood = entry?.mood;
    final result = await showDialog<(String, int?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(entry == null ? 'Новая запись' : 'Изменить запись'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: text,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Что чувствуете?'),
                onChanged: (value) => text = value,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return ChoiceChip(
                    label: Text('$value'),
                    selected: mood == value,
                    onSelected: (selected) =>
                        update(() => mood = selected ? value : null),
                  );
                }),
              ),
              const Text('Настроение 1–5 (необязательно)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (text.trim().isNotEmpty) {
                  Navigator.pop(context, (text, mood));
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (entry == null) {
      await widget.repository.addJournal(result.$1, mood: result.$2);
    } else {
      await widget.repository.updateJournal(
        entry.id,
        result.$1,
        mood: result.$2,
      );
    }
    if (mounted) _refresh();
  }

  Future<void> _delete(JournalEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteJournal(entry.id);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Дневник')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _edit,
      icon: const Icon(Icons.edit_note_rounded),
      label: const Text('Запись'),
    ),
    body: FutureBuilder<List<JournalEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Не удалось открыть дневник: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return const Center(
            child: Text('Здесь можно коротко записать своё состояние.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Card(
              child: ListTile(
                title: Text(entry.text),
                subtitle: Text(
                  '${MaterialLocalizations.of(context).formatMediumDate(entry.createdAt.toLocal())}${entry.mood == null ? '' : ' · настроение ${entry.mood}/5'}',
                ),
                onTap: () => _edit(entry),
                trailing: IconButton(
                  tooltip: 'Удалить запись',
                  onPressed: () => _delete(entry),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
