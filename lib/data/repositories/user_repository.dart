import '../../domain/models.dart';
import '../database/app_database.dart';
import 'package:drift/drift.dart';

class UserRepository {
  UserRepository(this.db);
  final AppDatabase db;

  Stream<List<User>> watchAll() =>
      (db.select(db.users)..orderBy([(u) => OrderingTerm.asc(u.name)])).watch();

  Future<int> create(String name, String email) async {
    final mail = email.trim().toLowerCase();
    if (name.trim().isEmpty) throw DomainException('Введите имя');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      throw DomainException('Некорректный email');
    }
    await _ensureEmailFree(mail);
    try {
      return await db.into(db.users).insert(
          UsersCompanion.insert(name: name.trim(), email: mail));
    } catch (e) {
      if (e.toString().contains('UNIQUE')) throw DomainException('Email уже занят');
      rethrow;
    }
  }

  Future<void> update(int id, String name, String email) async {
    final mail = email.trim().toLowerCase();
    await _ensureEmailFree(mail, exceptId: id);
    await (db.update(db.users)..where((u) => u.id.equals(id)))
        .write(UsersCompanion(name: Value(name.trim()), email: Value(mail)));
  }

  Future<void> _ensureEmailFree(String mail, {int? exceptId}) async {
    final q = db.select(db.users)..where((u) => u.email.equals(mail));
    if (exceptId != null) q.where((u) => u.id.equals(exceptId).not());
    if (await q.getSingleOrNull() != null) throw DomainException('Email уже занят');
  }

  Future<void> delete(int id) async {
    final open = await _unfinishedCount(id);
    if (open > 0) {
      throw DomainException('Нельзя удалить: за пользователем $open незавершённых задач');
    }
    await (db.delete(db.users)..where((u) => u.id.equals(id))).go();
  }

  Future<int> _unfinishedCount(int userId) async {
    final c = db.tasks.id.count();
    final q = db.selectOnly(db.tasks)
      ..addColumns([c])
      ..where(db.tasks.assigneeId.equals(userId) &
      db.tasks.deletedAt.isNull() &
      db.tasks.status.isInValues([TaskStatus.todo, TaskStatus.inProgress]));
    return (await q.map((r) => r.read(c)!).getSingle());
  }
}