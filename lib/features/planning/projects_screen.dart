import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'planning_repository.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.repository});

  final PlanningRepository repository;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> _projects;
  bool _showOnlyGoals = false;

  @override
  void initState() {
    super.initState();
    _projects = widget.repository.listProjects();
  }

  void _refresh() {
    setState(() {
      _projects = widget.repository.listProjects();
    });
  }

  Future<void> _addAction(Project project) async {
    var draft = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый шаг'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(hintText: 'Конкретное действие'),
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
    await widget.repository.addAction(project.id, title);
    if (mounted) _refresh();
  }

  Future<void> _linkGoal(Project project) async {
    final goals = await widget.repository.listGoals();
    if (!mounted) return;
    if (goals.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Сначала добавьте цель')));
      return;
    }
    final goalId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Связать с целью'),
        children: goals
            .map(
              (goal) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, goal.id),
                child: Text(goal.title),
              ),
            )
            .toList(),
      ),
    );
    if (goalId == null) return;
    await widget.repository.linkProjectToGoal(project.id, goalId);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Проекты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showOnlyGoals = !_showOnlyGoals),
        icon: Icon(
          _showOnlyGoals ? Icons.view_agenda_rounded : Icons.flag_rounded,
        ),
        label: Text(_showOnlyGoals ? 'Все проекты' : 'Цели'),
      ),
      body: FutureBuilder<List<Project>>(
        future: _projects,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Не удалось открыть проекты'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Большие задачи появятся здесь после разбора Inbox.'),
            );
          }
          final projects = snapshot.data!
              .where((project) => !_showOnlyGoals || project.goalId != null)
              .toList();
          if (projects.isEmpty) {
            return const Center(
              child: Text('Пока нет проектов, связанных с целями.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: projects
                .map(
                  (project) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  project.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Связать с целью',
                                onPressed: () => _linkGoal(project),
                                icon: const Icon(Icons.flag_outlined),
                              ),
                              IconButton(
                                tooltip: 'Добавить шаг',
                                onPressed: () => _addAction(project),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          if (project.goalId != null)
                            const Text('Связано с целью'),
                          FutureBuilder<List<TaskEntry>>(
                            future: widget.repository.listProjectActions(
                              project.id,
                            ),
                            builder: (context, actions) {
                              if (!actions.hasData) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: actions.data!
                                    .map(
                                      (task) => Card(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        child: ListTile(
                                          leading: const Icon(
                                            Icons
                                                .subdirectory_arrow_right_rounded,
                                          ),
                                          title: Text(task.title),
                                          subtitle: FutureBuilder<List<TaskEntry>>(
                                            future: widget.repository
                                                .listTaskChildren(task.id),
                                            builder: (context, children) =>
                                                children.hasData &&
                                                    children.data!.isNotEmpty
                                                ? Text(
                                                    'Подзадач: ${children.data!.length}',
                                                  )
                                                : const Text('Без подзадач'),
                                          ),
                                          trailing: IconButton(
                                            tooltip: 'Добавить подзадачу',
                                            icon: const Icon(
                                              Icons.add_task_rounded,
                                            ),
                                            onPressed: () => _addSubtask(task),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Future<void> _addSubtask(TaskEntry task) async {
    var draft = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая подзадача'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await widget.repository.addTaskChild(task.id, title);
    if (mounted) _refresh();
  }
}
