import 'inbox_repository.dart';

String dispositionLabel(TaskDisposition disposition) => switch (disposition) {
  TaskDisposition.quick => 'Сделать быстро',
  TaskDisposition.planned => 'Запланировать',
  TaskDisposition.project => 'Большой проект',
  TaskDisposition.deleted => 'Удалить',
};
