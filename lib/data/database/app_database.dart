import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';
export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Users, Projects, ProjectMembers, Tasks, Comments, Attachments, TaskHistory
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 -> v2: поле priority; DEFAULT = medium заполняет старые строки
        await m.addColumn(tasks, tasks.priority);
        await m.createIndex(idxTasksPriority);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON'); // без этого FK не работают
    },
  );
}

QueryExecutor openConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase.createInBackground(
      File(p.join(dir.path, 'taskflow.sqlite')));
});