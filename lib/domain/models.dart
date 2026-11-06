import 'package:drift/drift.dart' show Value;
import '../data/database/tables.dart';

class DomainException implements Exception {
  DomainException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum TaskSort { createdDesc, createdAsc, deadlineAsc, deadlineDesc }

class TaskFilter {
  const TaskFilter({
    this.status, this.priority, this.assigneeId, this.projectId,
    this.query = '', this.sort = TaskSort.createdDesc, this.trashed = false,
  });
  final TaskStatus? status;
  final TaskPriority? priority;
  final int? assigneeId, projectId;
  final String query;
  final TaskSort sort;
  final bool trashed;

  TaskFilter copyWith({
    Value<TaskStatus?> status = const Value.absent(),
    Value<TaskPriority?> priority = const Value.absent(),
    Value<int?> assigneeId = const Value.absent(),
    String? query, TaskSort? sort,
  }) => TaskFilter(
    status: status.present ? status.value : this.status,
    priority: priority.present ? priority.value : this.priority,
    assigneeId: assigneeId.present ? assigneeId.value : this.assigneeId,
    projectId: projectId, trashed: trashed,
    query: query ?? this.query, sort: sort ?? this.sort,
  );
}

class DashboardStats {
  DashboardStats({required this.projects, required this.total, required this.done,
    required this.open, required this.overdue, required this.byPriority,
    required this.byAssignee, required this.projectProgress});
  final int projects, total, done, open, overdue;
  final Map<TaskPriority, int> byPriority;
  final List<({int id, String name, int count})> byAssignee;
  final List<({int id, String name, int total, int done, double percent})> projectProgress;
}