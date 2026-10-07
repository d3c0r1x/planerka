import 'package:flutter/material.dart';

import 'core/app_database.dart';
import 'features/inbox/inbox_repository.dart';
import 'features/inbox/inbox_screen.dart';

class PlanerkaApp extends StatefulWidget {
  const PlanerkaApp({super.key, this.database});

  final AppDatabase? database;

  @override
  State<PlanerkaApp> createState() => _PlanerkaAppState();
}

class _PlanerkaAppState extends State<PlanerkaApp> {
  int _tab = 0;
  int _inboxVersion = 0;

  Future<void> _add(BuildContext dialogContext) async {
    final database = widget.database;
    if (database == null) return;
    var draft = '';
    var showError = false;
    final text = await showDialog<String>(
      context: dialogContext,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Новая запись'),
          content: TextField(
            onChanged: (value) => draft = value,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Что сейчас в голове?',
              errorText: showError ? 'Введите задачу' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (draft.trim().isEmpty) {
                  updateDialog(() => showError = true);
                  return;
                }
                Navigator.pop(context, draft);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (text == null) return;
    await InboxRepository(database).add(text);
    if (mounted) {
      setState(() {
        _tab = 1;
        _inboxVersion++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Планерка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5263D8)),
      ),
      home: Scaffold(
        appBar: AppBar(title: Text(_tab == 0 ? 'Планерка' : 'Inbox')),
        body: _tab == 0
            ? const Center(child: Text('Ваш день начинается здесь'))
            : widget.database == null
            ? const Center(child: Text('Данные недоступны'))
            : InboxScreen(
                key: ValueKey(_inboxVersion),
                repository: InboxRepository(widget.database!),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_rounded),
              label: 'Сегодня',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_rounded),
              label: 'Inbox',
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            onPressed: () => _add(context),
            tooltip: 'Добавить',
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ),
    );
  }
}
