import 'dart:async';

import 'package:flutter/material.dart';

import 'local_ai_engine.dart';
import '../planning/ai_recommendation_service.dart';
import '../planning/ai_suggestion_preview_screen.dart';

class LocalAiScreen extends StatefulWidget {
  const LocalAiScreen({super.key, required this.engine, this.recommendations});
  final LocalAiEngine engine;
  final AiRecommendationService? recommendations;

  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final _prompt = TextEditingController();
  String? _answer;
  String? _error;
  bool _working = false;
  bool? _diaryEnabled;

  @override
  void initState() {
    super.initState();
    final service = widget.recommendations;
    if (service != null) {
      unawaited(
        service.diaryEnabled().then((enabled) {
          if (mounted) setState(() => _diaryEnabled = enabled);
        }),
      );
    }
  }

  Future<void> _toggleDiary(bool value) async {
    await widget.recommendations?.setDiaryEnabled(value);
    if (mounted) setState(() => _diaryEnabled = value);
  }

  Future<void> _plan() async {
    final service = widget.recommendations;
    if (service == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.engine.load();
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AiSuggestionPreviewScreen(service: service),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось составить план. $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _working) return;
    setState(() {
      _working = true;
      _error = null;
      _answer = null;
    });
    try {
      final answer = await widget.engine.generate(prompt);
      if (mounted) {
        setState(() => _answer = answer);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Локальный помощник не запустился. $error');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _cancel() => widget.engine.cancel();

  @override
  void dispose() {
    _prompt.dispose();
    unawaited(widget.engine.unload());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Локальный помощник')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Ответ создаётся на телефоне. Задачи и дневник не отправляются в интернет.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.recommendations != null) ...[
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _diaryEnabled ?? true,
                  onChanged: _diaryEnabled == null ? null : _toggleDiary,
                  title: const Text('Учитывать дневник настроения'),
                  subtitle: const Text('Можно выключить в любой момент'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _working ? null : _plan,
                      icon: const Icon(Icons.event_available_rounded),
                      label: const Text('Предложить план'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _prompt,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'О чём подумать?',
            hintText: 'Например: помоги выбрать один следующий шаг',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_working)
          OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Остановить'),
          )
        else
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Получить совет'),
          ),
        if (_working) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Модель отвечает локально…'),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_answer case final answer?) ...[
          const SizedBox(height: 18),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(answer, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ],
      ],
    ),
  );
}
