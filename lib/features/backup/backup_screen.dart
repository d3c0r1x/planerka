import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

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
  String? _backgroundPath;

  @override
  void initState() {
    super.initState();
    widget.service.database.database
        .query(
          'app_metadata',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: ['custom_background_path'],
          limit: 1,
        )
        .then((rows) {
          if (mounted && rows.isNotEmpty) {
            setState(() => _backgroundPath = rows.single['value'] as String);
          }
        });
  }

  Future<void> _chooseBackground() async {
    final path = await widget.files.pickImage();
    if (path == null || !mounted) return;
    final savedPath = await widget.files.saveBackground(path);
    if (savedPath == null || !mounted) return;
    await widget.service.database.database.insert('app_metadata', {
      'key': 'custom_background_path',
      'value': savedPath,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    setState(() => _backgroundPath = savedPath);
    _message('Фон сохранён на устройстве');
  }

  Future<void> _resetBackground() async {
    await widget.service.database.database.delete(
      'app_metadata',
      where: 'key = ?',
      whereArgs: ['custom_background_path'],
    );
    if (mounted) setState(() => _backgroundPath = null);
  }

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
    appBar: AppBar(title: const Text('Настройки и резервная копия')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Резервная копия содержит задачи, цели, привычки, дневник и статистику. Фон хранится только на устройстве.',
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
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: const Text('Фон приложения'),
                subtitle: Text(
                  _backgroundPath == null
                      ? 'Чёрная тема'
                      : 'Пользовательское изображение сохранено',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_rounded),
                title: const Text('Выбрать изображение'),
                onTap: _chooseBackground,
              ),
              if (_backgroundPath != null)
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Вернуть чёрный фон'),
                  onTap: _resetBackground,
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
