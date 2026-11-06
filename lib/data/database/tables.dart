import 'package:drift/drift.dart';

enum ProjectStatus { active, completed, archived }
enum MemberRole { owner, admin, member }
enum TaskStatus { todo, inProgress, done, cancelled }
enum TaskPriority { low, medium, high, critical }

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().unique()();                       // UNIQUE
  DateTimeColumn get registeredAt =>
      dateTime().withDefault(currentDateAndTime)();
}

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get status => intEnum<ProjectStatus>()
      .withDefault(Constant(ProjectStatus.active.index))();
}

// Many-to-Many: users <-> projects
@TableIndex(name: 'idx_members_user', columns: {#userId})
class ProjectMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  IntColumn get role => intEnum<MemberRole>()();

  @override
  List<Set<Column>> get uniqueKeys => [{projectId, userId}];      // нет дублей
}

@TableIndex(name: 'idx_tasks_project', columns: {#projectId})
@TableIndex(name: 'idx_tasks_assignee', columns: {#assigneeId})
@TableIndex(name: 'idx_tasks_status', columns: {#status})
@TableIndex(name: 'idx_tasks_priority', columns: {#priority})
@TableIndex(name: 'idx_tasks_deadline', columns: {#deadline})
@TableIndex(name: 'idx_tasks_created', columns: {#createdAt})
@TableIndex(name: 'idx_tasks_deleted', columns: {#deletedAt})
@TableIndex(name: 'idx_tasks_assignee_deadline', columns: {#assigneeId, #deadline})
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get searchText => text().withDefault(const Constant(''))(); // lower-case для поиска
  IntColumn get projectId =>                                       // NOT NULL
  integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get assigneeId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  IntColumn get priority => intEnum<TaskPriority>()                // появилась в v2
      .withDefault(Constant(TaskPriority.medium.index))();
  IntColumn get status => intEnum<TaskStatus>()
      .withDefault(Constant(TaskStatus.todo.index))();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();         // Soft Delete
}

@TableIndex(name: 'idx_comments_task', columns: {#taskId})
class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get authorId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text().withLength(min: 1, max: 2000)();  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_attachments_task', columns: {#taskId})
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();                             // только путь
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TaskHistoryEntry')
@TableIndex(name: 'idx_history_task', columns: {#taskId})
class TaskHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get oldStatus => intEnum<TaskStatus>().nullable()();   // null = создание
  IntColumn get newStatus => intEnum<TaskStatus>()();
  IntColumn get changedBy => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();                      // «Исполнитель: A → B»
  BoolColumn get isUndoable => boolean().withDefault(const Constant(true))();
}