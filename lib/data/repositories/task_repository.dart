import 'package:drift/drift.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/domain/models.dart';

class TaskRepository {
  TaskRepository(this.db);
  final AppDatabase db;

  // ---------- чтение: фильтр + поиск + сортировка + пагинация ----------
  SimpleSelectStatement<$TasksTable, Task> _build(TaskFilter f, int limit, int offset) {
    final q = db.select(db.tasks)
      ..where((t) {
        Expression<bool> e =
        f.trashed ? t.deletedAt.isNotNull() : t.deletedAt.isNull();
        if (f.projectId != null) e = e & t.projectId.equals(f.projectId!);
        if (f.status != null) e = e & t.status.equalsValue(f.status!);
        if (f.priority != null) e = e & t.priority.equalsValue(f.priority!);
        if (f.assigneeId != null) e = e & t.assigneeId.equals(f.assigneeId!);
        if (f.query.trim().isNotEmpty) {
          // LIKE в SQLite нечувствителен к регистру только для ASCII,
          // поэтому ищем по заранее приведённому к нижнему регистру search_text
          e = e & t.searchText.like('%${f.query.trim().toLowerCase()}%');
        }
        return e;
      });
    switch (f.sort) {
      case TaskSort.createdDesc:
        q.orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)]);
      case TaskSort.createdAsc:
        q.orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]);
      case TaskSort.deadlineAsc:   // задачи без дедлайна — в конец
        q.orderBy([(t) => OrderingTerm.asc(t.deadline.isNull()),
              (t) => OrderingTerm.asc(t.deadline), (t) => OrderingTerm.asc(t.id)]);
      case TaskSort.deadlineDesc:
        q.orderBy([(t) => OrderingTerm.asc(t.deadline.isNull()),
              (t) => OrderingTerm.desc(t.deadline), (t) => OrderingTerm.asc(t.id)]);
    }
    q.limit(limit, offset: offset);
    return q;
  }

  Stream<List<Task>> watch(TaskFilter f, {int limit = 50, int offset = 0}) =>
      _build(f, limit, offset).watch();
  Future<List<Task>> fetch(TaskFilter f, {int limit = 50, int offset = 0}) =>
      _build(f, limit, offset).get();

  Stream<List<TaskHistoryEntry>> watchHistory(int taskId) => (db.select(db.taskHistory)
    ..where((h) => h.taskId.equals(taskId))
    ..orderBy([(h) => OrderingTerm.desc(h.id)])).watch();

  // ---------- создание: задача + первая запись истории АТОМАРНО ----------
  Future<int> create({
    required int projectId, required int actorId, required String title,
    String description = '', int? assigneeId,
    TaskPriority priority = TaskPriority.medium, DateTime? deadline,
  }) {
    if (title.trim().isEmpty) throw DomainException('Введите название');
    return db.transaction(() async {
      final project = await (db.select(db.projects)
        ..where((p) => p.id.equals(projectId))).getSingleOrNull();
      if (project == null) throw DomainException('Проект не найден');
      if (assigneeId != null) {
        await _ensureMember(projectId, assigneeId);
        await _ensureCapacity(assigneeId, deadline);
      }
      final id = await db.into(db.tasks).insert(TasksCompanion.insert(
        title: title.trim(), projectId: projectId,
        description: Value(description),
        searchText: Value('$title $description'.toLowerCase()),
        assigneeId: Value(assigneeId), priority: Value(priority),
        deadline: Value(deadline),
      ));
      await db.into(db.taskHistory).insert(TaskHistoryCompanion.insert(
          taskId: id, newStatus: TaskStatus.todo, changedBy: Value(actorId),
          isUndoable: const Value(false)));
      return id;   // любое исключение выше => откат всей транзакции
    });
  }

  Future<void> update(int id, {String? title, String? description,
    TaskPriority? priority, DateTime? deadline, bool clearDeadline = false}) =>
      db.transaction(() async {
        final t = await _getActive(id);
        final newDeadline = clearDeadline ? null : (deadline ?? t.deadline);
        if (t.assigneeId != null && newDeadline != t.deadline) {
          await _ensureCapacity(t.assigneeId!, newDeadline, excludeTaskId: id);
        }
        final newTitle = title ?? t.title;
        final newDesc = description ?? t.description;
        await (db.update(db.tasks)..where((x) => x.id.equals(id))).write(TasksCompanion(
          title: Value(newTitle), description: Value(newDesc),
          searchText: Value('$newTitle $newDesc'.toLowerCase()),
          priority: Value(priority ?? t.priority),
          deadline: Value(newDeadline), updatedAt: Value(DateTime.now()),
        ));
      });

  // ---------- смена статуса + история ----------
  Future<void> changeStatus(int taskId, TaskStatus newStatus, int actorId) =>
      db.transaction(() async {
        final t = await _getActive(taskId);
        if (t.status == newStatus) return;
        await (db.update(db.tasks)..where((x) => x.id.equals(taskId))).write(
            TasksCompanion(status: Value(newStatus), updatedAt: Value(DateTime.now())));
        await db.into(db.taskHistory).insert(TaskHistoryCompanion.insert(
            taskId: taskId, oldStatus: Value(t.status), newStatus: newStatus,
            changedBy: Value(actorId)));
      });

  // ---------- Undo (Задание 2) ----------
  Future<void> undoLastStatusChange(int taskId, int actorId) =>
      db.transaction(() async {
        final t = await _getActive(taskId);
        final last = await (db.select(db.taskHistory)
          ..where((h) => h.taskId.equals(taskId) &
          h.oldStatus.isNotNull() & h.isUndoable.equals(true))
          ..orderBy([(h) => OrderingTerm.desc(h.id)])
          ..limit(1)).getSingleOrNull();
        if (last == null) throw DomainException('Нечего отменять');
        await (db.update(db.taskHistory)..where((h) => h.id.equals(last.id)))
            .write(const TaskHistoryCompanion(isUndoable: Value(false)));
        await (db.update(db.tasks)..where((x) => x.id.equals(taskId))).write(
            TasksCompanion(status: Value(last.oldStatus!), updatedAt: Value(DateTime.now())));
        // сама отмена тоже попадает в историю, но откатить её нельзя
        await db.into(db.taskHistory).insert(TaskHistoryCompanion.insert(
            taskId: taskId, oldStatus: Value(t.status), newStatus: last.oldStatus!,
            changedBy: Value(actorId), note: const Value('Отмена изменения'),
            isUndoable: const Value(false)));
      });

  // ---------- переназначение исполнителя: всё атомарно ----------
  Future<void> reassign(int taskId, int? newAssigneeId, int actorId) =>
      db.transaction(() async {
        final t = await _getActive(taskId);
        if (newAssigneeId != null) {
          await _ensureMember(t.projectId, newAssigneeId);
          await _ensureCapacity(newAssigneeId, t.deadline, excludeTaskId: taskId);
        }
        await (db.update(db.tasks)..where((x) => x.id.equals(taskId))).write(
            TasksCompanion(assigneeId: Value(newAssigneeId),
                updatedAt: Value(DateTime.now())));
        await db.into(db.taskHistory).insert(TaskHistoryCompanion.insert(
            taskId: taskId, oldStatus: Value(t.status), newStatus: t.status,
            changedBy: Value(actorId), isUndoable: const Value(false),
            note: Value('Исполнитель: ${t.assigneeId ?? "—"} → ${newAssigneeId ?? "—"}')));
      });

  // ---------- корзина (Задание 1) ----------
  Future<void> softDelete(int id) => (db.update(db.tasks)..where((t) => t.id.equals(id)))
      .write(TasksCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(int id) => db.transaction(() async {
    final t = await (db.select(db.tasks)..where((x) => x.id.equals(id))).getSingle();
    if (t.assigneeId != null) {                    // исполнитель мог выйти из проекта
      final still = await _isMember(t.projectId, t.assigneeId!);
      if (!still) {
        await (db.update(db.tasks)..where((x) => x.id.equals(id)))
            .write(const TasksCompanion(assigneeId: Value(null)));
      }
    }
    await (db.update(db.tasks)..where((x) => x.id.equals(id)))
        .write(const TasksCompanion(deletedAt: Value(null)));
  });

  Future<void> purge(int id) async {                 // удаление навсегда
    final t = await (db.select(db.tasks)..where((x) => x.id.equals(id))).getSingle();
    if (t.deletedAt == null) throw DomainException('Сначала переместите в корзину');
    await (db.delete(db.tasks)..where((x) => x.id.equals(id))).go(); // каскад: история, комменты, вложения
  }

  // ---------- проверки целостности ----------
  Future<Task> _getActive(int id) async {
    final t = await (db.select(db.tasks)
      ..where((x) => x.id.equals(id) & x.deletedAt.isNull())).getSingleOrNull();
    if (t == null) throw DomainException('Задача не найдена');
    return t;
  }

  Future<bool> _isMember(int projectId, int userId) async =>
      (await (db.select(db.projectMembers)
        ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
          .getSingleOrNull()) != null;

  Future<void> _ensureMember(int projectId, int userId) async {
    if (!await _isMember(projectId, userId)) {
      throw DomainException('Исполнитель не состоит в проекте');
    }
  }

  /// Задание 3: не более 3 незавершённых задач на один день дедлайна (SQL-запрос).
  Future<void> _ensureCapacity(int assigneeId, DateTime? deadline,
      {int? excludeTaskId}) async {
    if (deadline == null) return;
    final start = DateTime(deadline.year, deadline.month, deadline.day);
    final end = DateTime(deadline.year, deadline.month, deadline.day + 1);
    final c = db.tasks.id.count();
    final q = db.selectOnly(db.tasks)
      ..addColumns([c])
      ..where(db.tasks.assigneeId.equals(assigneeId) &
      db.tasks.deletedAt.isNull() &
      db.tasks.status.isInValues([TaskStatus.todo, TaskStatus.inProgress]) &
      db.tasks.deadline.isBiggerOrEqualValue(start) &
      db.tasks.deadline.isSmallerThanValue(end) &
      (excludeTaskId == null
          ? const Constant(true)
          : db.tasks.id.equals(excludeTaskId).not()));
    final n = await q.map((r) => r.read(c)!).getSingle();
    if (n >= 3) {
      throw DomainException('У исполнителя уже 3 незавершённые задачи на эту дату');
    }
  }
}