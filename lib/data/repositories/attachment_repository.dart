import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:taskflow/data/database/app_database.dart';

class AttachmentRepository {
  AttachmentRepository(this.db);
  final AppDatabase db;

  Stream<List<Attachment>> watch(int taskId) =>
      (db.select(db.attachments)..where((a) => a.taskId.equals(taskId))).watch();

  Future<int> add(int taskId, String path) =>
      db.into(db.attachments).insert(AttachmentsCompanion.insert(
          taskId: taskId, fileName: p.basename(path), filePath: path));

  Future<void> delete(int id) =>
      (db.delete(db.attachments)..where((a) => a.id.equals(id))).go();
}