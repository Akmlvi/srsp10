import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/data/database/seed.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/domain/models.dart';

Future<int> _time(Future<void> Function() f, {int runs = 20}) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    await f();
  }
  return sw.elapsedMicroseconds ~/ runs;
}

void main() {
  test('индексы vs без индексов', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedDatabase(db);
    final repo = TaskRepository(db);

    final queries = <String, Future<void> Function()>{
      'filter assignee+status, sort deadline': () => repo.fetch(TaskFilter(
          assigneeId: 500,
          status: TaskStatus.todo,
          sort: TaskSort.deadlineAsc)),
      'filter priority, sort created': () =>
          repo.fetch(const TaskFilter(priority: TaskPriority.high)),
      'search "отчёт"': () => repo.fetch(const TaskFilter(query: 'отчёт')),
      'page 100 (offset 5000)': () =>
          repo.fetch(const TaskFilter(), offset: 5000),
    };

    Future<Map<String, int>> run() async => {
      for (final e in queries.entries) e.key: await _time(e.value),
    };

    Future<void> printPlan(String label) async {
      final plan = await db
          .customSelect('EXPLAIN QUERY PLAN SELECT * FROM tasks '
          'WHERE assignee_id = 500 AND deleted_at IS NULL')
          .get();
      // ignore: avoid_print
      print('$label: ${plan.map((r) => r.data['detail']).toList()}');
    }

    // ---- с индексами ----
    await printPlan('План С индексами');
    final withIdx = await run();

    // ---- удаляем индексы ----
    for (final idx in [
      'idx_tasks_project',
      'idx_tasks_assignee',
      'idx_tasks_status',
      'idx_tasks_priority',
      'idx_tasks_deadline',
      'idx_tasks_created',
      'idx_tasks_deleted',
      'idx_tasks_assignee_deadline',
    ]) {
      await db.customStatement('DROP INDEX IF EXISTS $idx');
    }

    // ---- без индексов ----
    await printPlan('План БЕЗ индексов');
    final noIdx = await run();

    // ---- итог ----
    // ignore: avoid_print
    print('\n=== Результаты (среднее за 20 запусков, 10 000 задач) ===');
    for (final k in queries.keys) {
      // ignore: avoid_print
      print('${k.padRight(40)} с индексами: ${withIdx[k]} мкс | без: ${noIdx[k]} мкс');
    }

    await db.close();
  });
}