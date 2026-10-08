import 'package:flutter/material.dart';

import 'ai_recommendation_service.dart';
import 'ai_suggestion.dart';
import 'ai_context_builder.dart';

class AiSuggestionPreviewScreen extends StatefulWidget {
  const AiSuggestionPreviewScreen({super.key, required this.service});

  final AiRecommendationService service;

  @override
  State<AiSuggestionPreviewScreen> createState() =>
      _AiSuggestionPreviewScreenState();
}

class _AiSuggestionPreviewScreenState extends State<AiSuggestionPreviewScreen> {
  AiSuggestion? _suggestion;
  final Set<String> _selected = {};
  String? _error;
  bool _loading = true;
  bool _applying = false;
  late final Future<AiPlanningContext> _context = widget.service.buildContext();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final context = await _context;
      final value = await widget.service.generatePlan(contextOverride: context);
      if (!mounted) return;
      setState(() {
        _suggestion = value;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось составить план. $error';
        _loading = false;
      });
    }
  }

  Future<void> _apply() async {
    final suggestion = _suggestion;
    if (suggestion == null || _selected.isEmpty || _applying) return;
    setState(() => _applying = true);
    try {
      await widget.service.applySelected(suggestion, _selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Перенесено задач: ${_selected.length}')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось применить предложения. $error';
        _applying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('План от ИИ')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Это черновик. Проверь предложения и выбери, какие применить.',
                  ),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_suggestion case final suggestion?) ...[
                const SizedBox(height: 16),
                Text(
                  suggestion.summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (suggestion.recommendations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Подходящих переносов не найдено.'),
                  ),
                ...suggestion.recommendations.map((item) {
                  final checked = _selected.contains(item.taskId);
                  return Card(
                    child: CheckboxListTile(
                      value: checked,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(item.taskId);
                        } else {
                          _selected.remove(item.taskId);
                        }
                      }),
                      title: Text(item.taskTitle),
                      subtitle: Text(
                        '${item.dayLabel} · ${TimeOfDay.fromDateTime(item.scheduledAt!).format(context)} · ${item.durationMinutes} мин\n${item.reason}',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  );
                }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _selected.isEmpty || _error != null || _applying
                      ? null
                      : _apply,
                  icon: _applying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Применить выбранное'),
                ),
              ],
            ],
          ),
  );
}
