import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/create_private_seed.dart <plan.md> <output.json>',
    );
    exitCode = 64;
    return;
  }
  final markdown = await File(arguments[0]).readAsString();
  final lines = const LineSplitter().convert(markdown);
  final tasks = <String>[];
  var inInbox = false;
  for (final line in lines) {
    if (line.trim() == '## Стартовый Inbox') {
      inInbox = true;
      continue;
    }
    if (inInbox && line.startsWith('## ')) break;
    if (!inInbox) continue;
    final match = RegExp(r'^-\s+(.+?)\s*$').firstMatch(line);
    if (match != null) tasks.add(match.group(1)!);
  }
  if (tasks.isEmpty) {
    stderr.writeln('Стартовый Inbox не найден или пуст.');
    exitCode = 65;
    return;
  }
  final seed = jsonEncode({'version': 1, 'tasks': tasks});
  final output = File(arguments[1]);
  await output.parent.create(recursive: true);
  await output.writeAsString(jsonEncode({'PLANERKA_PRIVATE_SEED': seed}));
  stdout.writeln('Создан локальный seed: ${tasks.length} записей.');
}
