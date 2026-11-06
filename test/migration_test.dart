import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:taskflow/data/database/app_database.dart';

void main() {
  test('миграция v1 -> v2: priority = medium, данные сохранены', () async {
    final dir = Directory.systemTemp.createTempSync('taskflow_mig');
    final file = File(p.join(dir.path, 'v1.sqlite'));

    final raw = sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        search_text TEXT NOT NULL DEFAULT '',
        project_id INTEGER NOT NULL,
        assignee_id INTEGER,
        status INTEGER NOT NULL DEFAULT 0,
        deadline INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        deleted_at INTEGER
      )''');
    raw.execute("INSERT INTO tasks (title, project_id, status) VALUES ('Старая задача', 1, 1)");
    raw.execute("INSERT INTO tasks (title, project_id) VALUES ('Ещё одна', 1)");
    raw.execute('PRAGMA user_version = 1');
    raw.dispose();

    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.tasks).get();

    expect(rows, hasLength(2));                                  // ничего не потеряно
    expect(rows.every((t) => t.priority == TaskPriority.medium), isTrue);
    expect(rows.first.title, 'Старая задача');
    expect(rows.first.status, TaskStatus.inProgress);
    await db.close();
    dir.deleteSync(recursive: true);
  });
}