import 'dart:math';
import 'dart:math';
import 'package:drift/drift.dart' show Value;
import 'package:taskflow/data/database/app_database.dart';

Future<void> seedDatabase(AppDatabase db) async {
  final rnd = Random(42);
  await db.batch((b) {
    b.insertAll(db.users, [for (var i = 0; i < 1000; i++)
      UsersCompanion.insert(name: 'Пользователь $i', email: 'user$i@mail.kz')]);
    b.insertAll(db.projects, [for (var i = 0; i < 100; i++)
      ProjectsCompanion.insert(name: 'Проект $i')]);
  });

  // по 30 уникальных участников в каждом проекте
  final members = <int, List<int>>{};
  final rows = <ProjectMembersCompanion>[];
  for (var pid = 1; pid <= 100; pid++) {
    final set = <int>{};
    while (set.length < 30) { set.add(rnd.nextInt(1000) + 1); }
    members[pid] = set.toList();
    for (final u in set) {
      rows.add(ProjectMembersCompanion.insert(
          projectId: pid, userId: u, role: MemberRole.member));
    }
  }
  await db.batch((b) => b.insertAll(db.projectMembers, rows));

  final now = DateTime.now();
  final tasks = <TasksCompanion>[];
  for (var i = 0; i < 10000; i++) {
    final pid = rnd.nextInt(100) + 1;
    final title = 'Задача $i ${["отчёт", "дизайн", "тест", "релиз"][rnd.nextInt(4)]}';
    tasks.add(TasksCompanion.insert(
      title: title, projectId: pid,
      searchText: Value(title.toLowerCase()),
      assigneeId: Value(members[pid]![rnd.nextInt(30)]),
      priority: Value(TaskPriority.values[rnd.nextInt(4)]),
      status: Value(TaskStatus.values[rnd.nextInt(4)]),
      deadline: Value(now.add(Duration(days: rnd.nextInt(120) - 30))),
      createdAt: Value(now.subtract(Duration(days: rnd.nextInt(365)))),
    ));
  }
  await db.batch((b) => b.insertAll(db.tasks, tasks));
}