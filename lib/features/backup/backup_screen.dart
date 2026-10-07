import 'package:flutter/material.dart';

import 'backup_file_port.dart';
import 'backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.service, BackupFilePort? files})
    : files = files ?? const NativeBackupFilePort();

  final BackupService service;
  final BackupFilePort files;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = await widget.service.exportJson();
      final saved = await widget.files.save(json);
      if (saved) _message('Резервная копия сохранена');
    } catch (error) {
      _message('Не удалось сохранить копию: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    try {
      final json = await widget.files.pick();
      if (json == null || !mounted) return;
      final mode = await showDialog<ImportMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Импортировать копию'),
          content: const Text(
            'Объединение добавит записи из файла. Замена удалит текущие данные и восстановит содержимое файла.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ImportMode.merge),
              child: const Text('Объединить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ImportMode.replace),
              child: const Text('Заменить'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      setState(() => _busy = true);
      await widget.service.importJson(json, mode: mode);
      _message('Данные восстановлены');
    } catch (error) {
      _message('Не удалось импортировать копию: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Резервная копия')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Копия содержит ваши задачи, цели, привычки, записи дневника и статистику. Выберите место хранения сами.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('Сохранить резервную копию'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.file_open_rounded),
          label: const Text('Восстановить из файла'),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
