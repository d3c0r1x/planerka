import 'package:flutter/material.dart';

import '../ai_provider_router.dart';
import 'missed_task_review_service.dart';

class MissedTaskReviewScreen extends StatefulWidget {
  const MissedTaskReviewScreen({
    super.key,
    required this.service,
    required this.taskId,
    this.onModelRequired,
    this.onAiSettingsRequired,
    this.onConfirmPenalty,
  });

  final MissedTaskReviewFlow service;
  final String taskId;
  final VoidCallback? onModelRequired;
  final VoidCallback? onAiSettingsRequired;
  final Future<void> Function(String taskId, MissedTaskCause cause)?
  onConfirmPenalty;

  @override
  State<MissedTaskReviewScreen> createState() => _MissedTaskReviewScreenState();
}

class _MissedTaskReviewScreenState extends State<MissedTaskReviewScreen> {
  final _answer = TextEditingController();
  final _answers = <MissedTaskAnswer>[];
  MissedTaskInterview? _interview;
  MissedTaskProposal? _proposal;
  int _questionIndex = 0;
  int? _selectedAction;
  MissedTaskCause? _selectedCause;
  String? _error;
  bool _busy = false;
  bool _modelMissing = false;
  bool _cloudNeedsSetup = false;

  @override
  void initState() {
    super.initState();
    _loadInterview();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _loadInterview() async {
    _interview = null;
    _proposal = null;
    _questionIndex = 0;
    _answers.clear();
    _answer.clear();
    setState(() {
      _busy = true;
      _error = null;
      _modelMissing = false;
      _cloudNeedsSetup = false;
    });
    try {
      final value = await widget.service.startInterview(widget.taskId);
      if (!mounted) return;
      setState(() {
        _interview = value;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _modelMissing =
            error.toString().contains('Verified local model') ||
            error.toString().contains('local model could not be loaded');
        _cloudNeedsSetup =
            error is CloudConsentRequiredException ||
            error is CloudProviderConfigurationException;
        _error = _modelMissing || _cloudNeedsSetup
            ? null
            : 'Не удалось начать интервью. Проверь задачу и попробуй ещё раз.';
      });
    }
  }

  Future<void> _answerQuestion() async {
    final interview = _interview;
    final value = _answer.text.trim();
    if (interview == null || value.isEmpty || _busy) return;
    _answers.add(
      MissedTaskAnswer(
        question: interview.questions[_questionIndex],
        answer: value,
      ),
    );
    _answer.clear();
    if (_questionIndex + 1 < interview.questions.length) {
      setState(() => _questionIndex++);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final proposal = await widget.service.analyzeAnswers(
        widget.taskId,
        List.unmodifiable(_answers),
      );
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _selectedAction = 0;
        _selectedCause = proposal.cause;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _modelMissing =
            error.toString().contains('Verified local model') ||
            error.toString().contains('local model could not be loaded');
        _cloudNeedsSetup =
            error is CloudConsentRequiredException ||
            error is CloudProviderConfigurationException;
        _error = _modelMissing || _cloudNeedsSetup ? null : 'Не удалось подготовить рекомендацию. Ответы остались только на экране.';
      });
    }
  }

  Future<void> _apply() async {
    final proposal = _proposal;
    final index = _selectedAction;
    if (proposal == null || index == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cause = _selectedCause;
      final confirmPenalty = widget.onConfirmPenalty;
      if (cause == MissedTaskCause.avoidableDelay && confirmPenalty != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Подтвердить ответственность?'),
            content: const Text(
              'Ты подтверждаешь, что задачу можно было выполнить, '
              'но ты её отложил. Это снизит недельную надёжность на 10 '
              'баллов. Опыт, уровень и достижения не изменятся.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Без штрафа'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Подтвердить штраф'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (confirmed == null) {
          setState(() => _busy = false);
          return;
        }
        if (confirmed) await confirmPenalty(widget.taskId, cause!);
      }
      await widget.service.applyAction(proposal, index);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            error is StateError &&
                error.message == 'Система ответственности выключена'
            ? 'Система ответственности выключена. Измени выбор или примени действие без штрафа.'
            : 'Не удалось применить рекомендацию. Проверь задачу и попробуй ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final interview = _interview;
    final proposal = _proposal;
    return Scaffold(
      appBar: AppBar(title: const Text('Разбор пропуска')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error case final error?) ...[
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loadInterview,
                    child: const Text('Повторить'),
                  ),
                ],
                if (_modelMissing) ...[
                  const Text('Для интервью нужен установленный локальный ИИ.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.onModelRequired,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Установить модель'),
                  ),
                  TextButton(
                    onPressed: _loadInterview,
                    child: const Text('Повторить'),
                  ),
                ] else if (_cloudNeedsSetup) ...[
                  const Text(
                    'Проверь настройки и разрешение для облачного ИИ.',
                  ),
                  FilledButton(
                    onPressed: widget.onAiSettingsRequired,
                    child: const Text('Настройки ИИ'),
                  ),
                  TextButton(
                    onPressed: _loadInterview,
                    child: const Text('Повторить'),
                  ),
                ] else if (proposal != null) ...[
                  Text(
                    interview?.taskTitle ?? 'Задача',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Проверь причину пропуска'),
                  Card(
                    child: RadioGroup<MissedTaskCause>(
                      groupValue: _selectedCause,
                      onChanged: (value) => setState(() {
                        _selectedCause = value;
                      }),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final cause in MissedTaskCause.values)
                            RadioListTile<MissedTaskCause>(
                              key: Key('missed-cause-${cause.name}'),
                              value: cause,
                              title: Text(_causeLabel(cause)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(proposal.explanation),
                  const SizedBox(height: 16),
                  Text(
                    'Выбери действие',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Card(
                    child: RadioGroup<int>(
                      groupValue: _selectedAction,
                      onChanged: (value) =>
                          setState(() => _selectedAction = value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < proposal.actions.length; i++)
                            RadioListTile<int>(
                              value: i,
                              title: Text(proposal.actions[i].label),
                              subtitle: Text(
                                _actionDetails(proposal.actions[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('missed-review-apply'),
                    onPressed: _selectedAction == null || _selectedCause == null
                        ? null
                        : _apply,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Подтвердить действие'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Оставить без изменений'),
                  ),
                ] else if (interview != null) ...[
                  Text(
                    interview.taskTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Вопрос ${_questionIndex + 1} из ${interview.questions.length}',
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(interview.questions[_questionIndex]),
                    ),
                  ),
                  TextField(
                    key: const Key('missed-review-answer'),
                    controller: _answer,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Твой ответ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('missed-review-next'),
                    onPressed: _answer.text.trim().isEmpty
                        ? null
                        : _answerQuestion,
                    child: Text(
                      _questionIndex + 1 == interview.questions.length
                          ? 'Получить рекомендации'
                          : 'Следующий вопрос',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Отмена'),
                  ),
                ],
              ],
            ),
    );
  }

  String _causeLabel(MissedTaskCause cause) => switch (cause) {
    MissedTaskCause.externalObstacle => 'Внешнее препятствие',
    MissedTaskCause.estimateWrong => 'Неверная оценка времени',
    MissedTaskCause.priorityChanged => 'Изменился приоритет',
    MissedTaskCause.avoidableDelay => 'Откладывание',
  };

  String _actionDetails(MissedTaskAction action) => switch (action.type) {
    MissedTaskActionType.reschedule =>
      '${MaterialLocalizations.of(context).formatMediumDate(action.scheduledAt!.toLocal())}, ${TimeOfDay.fromDateTime(action.scheduledAt!.toLocal()).format(context)} · ${action.durationMinutes} мин',
    MissedTaskActionType.changeDeadline =>
      'Новый срок: ${MaterialLocalizations.of(context).formatMediumDate(action.dueAt!.toLocal())}',
    MissedTaskActionType.split => action.followUpTitle!,
    MissedTaskActionType.discard => 'Задача будет убрана из активного списка',
  };
}
