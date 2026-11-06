import 'package:drift/drift.dart';
import 'package:taskflow/data/database/app_database.dart';
import 'package:taskflow/domain/models.dart';

class StatsRepository {
  StatsRepository(this.db);
  final AppDatabase db;
  static final _tasksTables = {};

  Stream<DashboardStats> watch() async* {
    yield await load();
    yield* db.tableUpdates(TableUpdateQuery.onAllTables(
        [db.tasks, db.projects, db.users])).asyncMap((_) => load());
  }

  Future<DashboardStats> load() async {
    final now = Variable.withDateTime(DateTime.now());

    final proj = await db.customSelect('SELECT COUNT(*) AS c FROM projects',
        readsFrom: {db.projects}).getSingle();

    final totals = await db.customSelect('''
      SELECT COUNT(*) AS total,
             COALESCE(SUM(status = 2), 0)            AS done,
             COALESCE(SUM(status IN (0,1)), 0)       AS open,
             COALESCE(SUM(status IN (0,1) AND deadline IS NOT NULL AND deadline < ?), 0) AS overdue
      FROM tasks WHERE deleted_at IS NULL
    ''', variables: [now], readsFrom: {db.tasks}).getSingle();

    final prio = await db.customSelect('''
      SELECT priority, COUNT(*) AS c FROM tasks
      WHERE deleted_at IS NULL GROUP BY priority
    ''', readsFrom: {db.tasks}).get();

    final byUser = await db.customSelect('''
      SELECT u.id, u.name, COUNT(t.id) AS c
      FROM users u LEFT JOIN tasks t ON t.assignee_id = u.id AND t.deleted_at IS NULL
      GROUP BY u.id ORDER BY c DESC, u.name
    ''', readsFrom: {db.users, db.tasks}).get();

    final progress = await db.customSelect('''
      SELECT p.id, p.name, COUNT(t.id) AS total,
             COALESCE(SUM(t.status = 2), 0) AS done,
             CASE WHEN COUNT(t.id) = 0 THEN 0.0
                  ELSE ROUND(100.0 * SUM(t.status = 2) / COUNT(t.id), 1) END AS percent
      FROM projects p LEFT JOIN tasks t ON t.project_id = p.id AND t.deleted_at IS NULL
      GROUP BY p.id ORDER BY p.name
    ''', readsFrom: {db.projects, db.tasks}).get();

    return DashboardStats(
      projects: proj.read<int>('c'),
      total: totals.read<int>('total'), done: totals.read<int>('done'),
      open: totals.read<int>('open'), overdue: totals.read<int>('overdue'),
      byPriority: {for (final r in prio)
        TaskPriority.values[r.read<int>('priority')]: r.read<int>('c')},
      byAssignee: [for (final r in byUser)
        (id: r.read<int>('id'), name: r.read<String>('name'), count: r.read<int>('c'))],
      projectProgress: [for (final r in progress)
        (id: r.read<int>('id'), name: r.read<String>('name'),
        total: r.read<int>('total'), done: r.read<int>('done'),
        percent: r.read<double>('percent'))],
    );
  }
}