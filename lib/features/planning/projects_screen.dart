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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!
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
                                      (task) => ListTile(
                                        leading: const Icon(
                                          Icons
                                              .subdirectory_arrow_right_rounded,
                                        ),
                                        title: Text(task.title),
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
}
