import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'shift_cycle.dart';
import 'shift_models.dart';
import 'shift_repository.dart';

class ShiftSetupScreen extends StatefulWidget {
  const ShiftSetupScreen({super.key, required this.repository});

  final ShiftRepository repository;

  @override
  State<ShiftSetupScreen> createState() => _ShiftSetupScreenState();
}

class _ShiftSetupScreenState extends State<ShiftSetupScreen> {
  static const _palette = [
    AppTheme.mint,
    Color(0xFFFFC857),
    Color(0xFFA991FF),
    AppTheme.pink,
    Color(0xFF62C9FF),
    AppTheme.coral,
  ];

  late final List<_TeamDraft> _drafts = List.generate(
    4,
    (index) => _TeamDraft(
      id: 'team-${index + 1}',
      name: 'Смена ${index + 1}',
      colorValue: _palette[index].toARGB32(),
    ),
  );
  late final Future<void> _loadFuture = _load();
  DateTime _anchorDate = DateTime.now();
  int _anchorIndex = 0;
  String? _loadError;
  final _commuteBefore = TextEditingController(text: '60');
  final _commuteAfter = TextEditingController(text: '90');
  final _reminderLead = TextEditingController(text: '30');
  bool _saving = false;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _commuteBefore.dispose();
    _commuteAfter.dispose();
    _reminderLead.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.loadSettings();
      final teams = await widget.repository.listTeams();
      if (settings == null || teams.length != 4) return;
      _anchorDate = DateTime(
        settings.anchorDate.year,
        settings.anchorDate.month,
        settings.anchorDate.day,
      );
      _commuteBefore.text = settings.commuteBeforeMinutes.toString();
      _commuteAfter.text = settings.commuteAfterMinutes.toString();
      _reminderLead.text = settings.reminderLeadMinutes.toString();
      for (var index = 0; index < teams.length; index++) {
        final team = teams[index];
        _drafts[index]
          ..id = team.id
          ..name.text = team.name
          ..leader.text = team.leaderName
          ..colorValue = team.colorValue
          ..attends = team.attends;
        if (team.phaseOffsetDays == 0) _anchorIndex = index;
      }
    } catch (_) {
      _loadError = 'Не удалось загрузить сохранённый график';
    }
  }

  Future<void> _pickAnchorDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Дата, когда опорная смена начинает дневной цикл',
    );
    if (selected != null) setState(() => _anchorDate = selected);
  }

  Future<void> _editColor(int index) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Цвет · ${_drafts[index].name.text}'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _palette
              .map(
                (color) => IconButton(
                  key: ValueKey(
                    'color-choice-${color.toARGB32().toRadixString(16)}',
                  ),
                  tooltip: 'Выбрать цвет',
                  onPressed: () => Navigator.pop(context, color.toARGB32()),
                  icon: Icon(Icons.circle, color: color, size: 32),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected != null) setState(() => _drafts[index].colorValue = selected);
  }

  Future<void> _save() async {
    final before = int.tryParse(_commuteBefore.text.trim());
    final after = int.tryParse(_commuteAfter.text.trim());
    final lead = int.tryParse(_reminderLead.text.trim());
    if (before == null || after == null || lead == null) {
      _showMessage('Введите интервалы времени в минутах');
      return;
    }
    if (_drafts.any((draft) => draft.name.text.trim().isEmpty)) {
      _showMessage('Укажите название каждой смены');
      return;
    }
    if (_drafts.any((draft) => draft.leader.text.trim().isEmpty)) {
      _showMessage('Назначьте руководителя каждой смене');
      return;
    }

    setState(() => _saving = true);
    try {
      final teams = [
        for (var index = 0; index < _drafts.length; index++)
          ShiftTeam(
            id: _drafts[index].id,
            name: _drafts[index].name.text.trim(),
            leaderName: _drafts[index].leader.text.trim(),
            colorValue: _drafts[index].colorValue,
            phaseOffsetDays: ((index - _anchorIndex + 4) % 4) * 2,
            attends: _drafts[index].attends,
          ),
      ];
      await widget.repository.saveSchedule(
        ShiftSettings(
          anchorDate: _anchorDate,
          commuteBeforeMinutes: before,
          commuteAfterMinutes: after,
          reminderLeadMinutes: lead,
        ),
        teams,
      );
      if (mounted) await Navigator.maybePop(context, true);
    } catch (_) {
      _showMessage('Не удалось сохранить график смен');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<int> _offsets() => [
    for (var index = 0; index < _drafts.length; index++)
      ((index - _anchorIndex + 4) % 4) * 2,
  ];

  String _phaseLabel(ShiftPhase phase) => switch (phase) {
    ShiftPhase.day => 'Дневная',
    ShiftPhase.preNightRest => 'Отдых перед ночью',
    ShiftPhase.night => 'Ночная',
    ShiftPhase.recovery => 'Отсыпной',
    ShiftPhase.rest => 'Выходной',
  };

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройка смен')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError || _loadError != null) {
            return Center(
              child: Text(_loadError ?? 'Не удалось открыть настройки'),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Один график для всех четырёх смен',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Укажи дату, когда опорная команда начинает дневные смены.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('anchor-date-picker'),
                      leading: const Icon(Icons.event_rounded),
                      title: const Text('Дата начала цикла'),
                      subtitle: Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(_anchorDate),
                      ),
                      onTap: _pickAnchorDate,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DropdownButtonFormField<int>(
                        key: const Key('anchor-team-select'),
                        initialValue: _anchorIndex,
                        decoration: const InputDecoration(
                          labelText: 'Опорная смена',
                        ),
                        items: [
                          for (var index = 0; index < 4; index++)
                            DropdownMenuItem(
                              value: index,
                              child: Text(_drafts[index].name.text),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _anchorIndex = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              for (var index = 0; index < _drafts.length; index++)
                _teamCard(index),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Дорога и напоминание',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _minutesField('До смены', _commuteBefore),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _minutesField('После', _commuteAfter),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _minutesField('Напомнить', _reminderLead),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ExpansionTile(
                key: const Key('shift-preview'),
                initiallyExpanded: true,
                leading: const Icon(Icons.calendar_view_week_rounded),
                title: const Text('Предпросмотр восьми дней'),
                children: [
                  for (var dayIndex = 0; dayIndex < 8; dayIndex++)
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            dense: true,
                            title: Text(
                              _shortDate(
                                _anchorDate.add(Duration(days: dayIndex)),
                              ),
                            ),
                          ),
                          for (var index = 0; index < _drafts.length; index++)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                              child: Text(
                                '${_drafts[index].name.text} · ${_phaseLabel(ShiftCycleCalculator.phaseAt(
                                  date: _anchorDate.add(Duration(days: dayIndex)),
                                  anchorDate: _anchorDate,
                                  phaseOffsetDays: _offsets()[index],
                                ))}',
                                style: TextStyle(
                                  color: Color(_drafts[index].colorValue),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('save-shift-schedule'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Сохранить график'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _teamCard(int index) {
    final draft = _drafts[index];
    return Card(
      key: ValueKey('shift-team-card-$index'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Смена ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: ValueKey('team-color-$index'),
                  tooltip: 'Изменить цвет смены ${index + 1}',
                  onPressed: () => _editColor(index),
                  icon: Icon(Icons.circle, color: Color(draft.colorValue)),
                ),
              ],
            ),
            TextField(
              key: ValueKey('team-name-$index'),
              controller: draft.name,
              decoration: const InputDecoration(labelText: 'Название смены'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('team-leader-$index'),
              controller: draft.leader,
              decoration: const InputDecoration(labelText: 'Руководитель'),
            ),
            SwitchListTile(
              key: ValueKey('team-attends-$index'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Я хожу в эту смену'),
              value: draft.attends,
              onChanged: (value) => setState(() => draft.attends = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _minutesField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: 'мин'),
      );
}

class _TeamDraft {
  _TeamDraft({required this.id, required String name, required this.colorValue})
    : name = TextEditingController(text: name),
      leader = TextEditingController();

  String id;
  final TextEditingController name;
  final TextEditingController leader;
  int colorValue;
  bool attends = true;

  void dispose() {
    name.dispose();
    leader.dispose();
  }
}
