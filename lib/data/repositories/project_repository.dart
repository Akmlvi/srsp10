import 'package:drift/drift.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/domain/models.dart';

class ProjectRepository {
  ProjectRepository(this.db);
  final AppDatabase db;

  Stream<List<Project>> watchAll() => (db.select(db.projects)
    ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).watch();

  /// Создатель сразу становится Owner (в одной транзакции).
  Future<int> create(String name, String description, int ownerId) =>
      db.transaction(() async {
        final id = await db.into(db.projects).insert(
            ProjectsCompanion.insert(name: name.trim(), description: Value(description)));
        await db.into(db.projectMembers).insert(ProjectMembersCompanion.insert(
            projectId: id, userId: ownerId, role: MemberRole.owner));
        return id;
      });

  Future<void> update(int id, {String? name, String? description,
    ProjectStatus? status}) async {
    await (db.update(db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          description: description == null ? const Value.absent() : Value(description),
          status: status == null ? const Value.absent() : Value(status),
          finishedAt: status == ProjectStatus.completed
              ? Value(DateTime.now()) : const Value.absent(),
        ));
  }

  Future<void> delete(int id) =>   // каскадом удалятся участники и задачи
  (db.delete(db.projects)..where((p) => p.id.equals(id))).go();

  Future<void> addMember(int projectId, int userId, MemberRole role) async {
    final exists = await (db.select(db.projectMembers)
      ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
        .getSingleOrNull();
    if (exists != null) throw DomainException('Пользователь уже в проекте');
    await db.into(db.projectMembers).insert(ProjectMembersCompanion.insert(
        projectId: projectId, userId: userId, role: role));
  }

  Future<void> setRole(int projectId, int userId, MemberRole role) =>
      (db.update(db.projectMembers)
        ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
          .write(ProjectMembersCompanion(role: Value(role)));

  /// При удалении участника его задачи в проекте снимаются с исполнителя.
  Future<void> removeMember(int projectId, int userId) => db.transaction(() async {
    await (db.update(db.tasks)
      ..where((t) => t.projectId.equals(projectId) & t.assigneeId.equals(userId)))
        .write(TasksCompanion(assigneeId: Value(null)));    await (db.delete(db.projectMembers)
      ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
        .go();
  });

  Stream<List<({ProjectMember member, User user})>> watchMembers(int projectId) {
    final q = db.select(db.projectMembers).join([
      innerJoin(db.users, db.users.id.equalsExp(db.projectMembers.userId))
    ])..where(db.projectMembers.projectId.equals(projectId));
    return q.watch().map((rows) => rows
        .map((r) => (member: r.readTable(db.projectMembers), user: r.readTable(db.users)))
        .toList());
  }
}