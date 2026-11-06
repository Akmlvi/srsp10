import 'package:drift/drift.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/domain/models.dart';

class CommentRepository {
  CommentRepository(this.db);
  final AppDatabase db;

  Stream<List<Comment>> watch(int taskId) => (db.select(db.comments)
    ..where((c) => c.taskId.equals(taskId))
    ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
      .watch();

  Future<int> add(int taskId, int authorId, String text) async {
    if (text.trim().isEmpty) {
      throw DomainException('Комментарий не может быть пустым');
    }
    final task = await (db.select(db.tasks)
      ..where((t) => t.id.equals(taskId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (task == null) throw DomainException('Задача не существует');
    return db.into(db.comments).insert(CommentsCompanion.insert(
        taskId: taskId, authorId: authorId, body: text.trim()));
  }

  Future<void> delete(int commentId, int requesterId) async {
    final c = await (db.select(db.comments)
      ..where((x) => x.id.equals(commentId)))
        .getSingleOrNull();
    if (c == null) throw DomainException('Комментарий не найден');
    if (c.authorId != requesterId) {
      throw DomainException('Удалить комментарий может только автор');
    }
    await (db.delete(db.comments)..where((x) => x.id.equals(commentId))).go();
  }
}