import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/data/repositories/user_repository.dart';
import 'package:taskflow/data/repositories/project_repository.dart';
import 'package:taskflow/data/repositories/task_repository.dart';
import 'package:taskflow/data/repositories/comment_repository.dart';
import 'package:taskflow/data/repositories/stats_repository.dart';
import 'package:taskflow/domain/models.dart';

void main() {
  late AppDatabase db;
  late UserRepository users;
  late ProjectRepository projects;
  late TaskRepository tasks;
  late CommentRepository comments;
  late StatsRepository stats;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    users = UserRepository(db); projects = ProjectRepository(db);
    tasks = TaskRepository(db); comments = CommentRepository(db);
    stats = StatsRepository(db);
  });
  tearDown(() => db.close());

  /// Владелец + проект + участник
  Future<({int owner, int member, int project})> setup() async {
    final owner = await users.create('Owner', 'owner@mail.kz');
    final member = await users.create('Member', 'member@mail.kz');
    final project = await projects.create('P1', '', owner);
    await projects.addMember(project, member, MemberRole.member);
    return (owner: owner, member: member, project: project);
  }

  test('1. создание пользователя', () async {
    final id = await users.create('Аян', 'a@mail.kz');
    expect((await db.select(db.users).get()).single.id, id);
  });

  test('2. email уникален (без учёта регистра)', () async {
    await users.create('A', 'a@mail.kz');
    expect(() => users.create('B', 'A@mail.kz'), throwsA(isA<DomainException>()));
  });

  test('3. удаление пользователя без задач', () async {
    final id = await users.create('A', 'a@mail.kz');
    await users.delete(id);
    expect(await db.select(db.users).get(), isEmpty);
  });

  test('4. нельзя удалить пользователя с незавершёнными задачами', () async {
    final s = await setup();
    await tasks.create(projectId: s.project, actorId: s.owner,
        title: 'T', assigneeId: s.member);
    expect(() => users.delete(s.member), throwsA(isA<DomainException>()));
  });

  test('5. создание проекта делает создателя Owner', () async {
    final s = await setup();
    final m = await (db.select(db.projectMembers)
      ..where((x) => x.userId.equals(s.owner))).getSingle();
    expect(m.role, MemberRole.owner);
  });

  test('6. повторное добавление участника запрещено', () async {
    final s = await setup();
    expect(() => projects.addMember(s.project, s.member, MemberRole.admin),
        throwsA(isA<DomainException>()));
  });

  test('7. создание задачи + первая запись истории', () async {
    final s = await setup();
    final id = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    final h = await db.select(db.taskHistory).get();
    expect(h.single.taskId, id);
    expect(h.single.oldStatus, isNull);
    expect(h.single.newStatus, TaskStatus.todo);
  });

  test('8. задача без проекта не создаётся', () async {
    final s = await setup();
    expect(() => tasks.create(projectId: 9999, actorId: s.owner, title: 'T'),
        throwsA(isA<DomainException>()));
  });

  test('9. исполнитель не из проекта отклоняется', () async {
    final s = await setup();
    final stranger = await users.create('X', 'x@mail.kz');
    expect(() => tasks.create(projectId: s.project, actorId: s.owner,
        title: 'T', assigneeId: stranger), throwsA(isA<DomainException>()));
  });

  test('10. смена статуса пишет историю', () async {
    final s = await setup();
    final id = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    await tasks.changeStatus(id, TaskStatus.inProgress, s.member);
    final h = await (db.select(db.taskHistory)
      ..orderBy([(x) => OrderingTerm.desc(x.id)])).get();
    expect(h.first.oldStatus, TaskStatus.todo);
    expect(h.first.newStatus, TaskStatus.inProgress);
    expect(h.first.changedBy, s.member);
  });

  test('11. транзакция: ошибка истории откатывает задачу', () async {
    final s = await setup();
    // actorId=9999 нарушает FK в task_history => вся транзакция откатывается
    await expectLater(
        tasks.create(projectId: s.project, actorId: 9999, title: 'T'),
        throwsA(anything));
    expect(await db.select(db.tasks).get(), isEmpty);
  });

  test('12. переназначение атомарно: при ошибке ничего не меняется', () async {
    final s = await setup();
    final stranger = await users.create('X', 'x@mail.kz');
    final id = await tasks.create(projectId: s.project, actorId: s.owner,
        title: 'T', assigneeId: s.member);
    final before = (await db.select(db.taskHistory).get()).length;
    await expectLater(tasks.reassign(id, stranger, s.owner), throwsA(isA<DomainException>()));
    final t = await (db.select(db.tasks)..where((x) => x.id.equals(id))).getSingle();
    expect(t.assigneeId, s.member);
    expect((await db.select(db.taskHistory).get()).length, before);
  });

  test('13. комментарии: добавление, чужой не удалить', () async {
    final s = await setup();
    final t = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    final c = await comments.add(t, s.owner, 'привет');
    expect(() => comments.delete(c, s.member), throwsA(isA<DomainException>()));
    await comments.delete(c, s.owner);
    expect(await db.select(db.comments).get(), isEmpty);
  });

  test('14. комментарий к несуществующей задаче запрещён', () async {
    final s = await setup();
    expect(() => comments.add(9999, s.owner, 'x'), throwsA(isA<DomainException>()));
  });

  test('15. soft delete скрывает задачу из списка, но не из БД', () async {
    final s = await setup();
    final id = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    await tasks.softDelete(id);
    expect(await tasks.fetch(const TaskFilter()), isEmpty);
    expect((await tasks.fetch(const TaskFilter(trashed: true))).single.id, id);
    expect(await db.select(db.tasks).get(), hasLength(1));
  });

  test('16. восстановление и полное удаление', () async {
    final s = await setup();
    final id = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    await tasks.softDelete(id);
    await tasks.restore(id);
    expect(await tasks.fetch(const TaskFilter()), hasLength(1));
    await tasks.softDelete(id);
    await tasks.purge(id);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.taskHistory).get(), isEmpty); // каскад
  });

  test('17. Undo возвращает прошлый статус', () async {
    final s = await setup();
    final id = await tasks.create(projectId: s.project, actorId: s.owner, title: 'T');
    await tasks.changeStatus(id, TaskStatus.inProgress, s.owner);
    await tasks.undoLastStatusChange(id, s.owner);
    final t = await (db.select(db.tasks)..where((x) => x.id.equals(id))).getSingle();
    expect(t.status, TaskStatus.todo);
  });

  test('18. лимит 3 незавершённые задачи на дату', () async {
    final s = await setup();
    final d = DateTime(2030, 1, 1, 12);
    for (var i = 0; i < 3; i++) {
      await tasks.create(projectId: s.project, actorId: s.owner, title: 'T$i',
          assigneeId: s.member, deadline: d);
    }
    expect(() => tasks.create(projectId: s.project, actorId: s.owner, title: 'T4',
        assigneeId: s.member, deadline: d), throwsA(isA<DomainException>()));
  });

  test('19. статистика считается верно', () async {
    final s = await setup();
    final a = await tasks.create(projectId: s.project, actorId: s.owner,
        title: 'A', priority: TaskPriority.high,
        deadline: DateTime.now().subtract(const Duration(days: 1)));
    final b = await tasks.create(projectId: s.project, actorId: s.owner, title: 'B');
    await tasks.changeStatus(b, TaskStatus.done, s.owner);
    final st = await stats.load();
    expect(st.projects, 1);
    expect(st.total, 2);
    expect(st.done, 1);
    expect(st.open, 1);
    expect(st.overdue, 1);
    expect(st.byPriority[TaskPriority.high], 1);
    expect(st.projectProgress.single.percent, 50.0);
  });

  test('20. фильтрация, поиск (кириллица) и сортировка', () async {
    final s = await setup();
    await tasks.create(projectId: s.project, actorId: s.owner,
        title: 'Написать ОТЧЁТ', priority: TaskPriority.high);
    await tasks.create(projectId: s.project, actorId: s.owner, title: 'Дизайн');
    expect(await tasks.fetch(const TaskFilter(query: 'отчёт')), hasLength(1));
    expect(await tasks.fetch(const TaskFilter(priority: TaskPriority.high)), hasLength(1));
    final sorted = await tasks.fetch(const TaskFilter(sort: TaskSort.createdAsc));
    expect(sorted.first.title, 'Написать ОТЧЁТ');
  });
}