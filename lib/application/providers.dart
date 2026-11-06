final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openConnection());
  ref.onDispose(db.close);
  return db;
});
final userRepoProvider    = Provider((r) => UserRepository(r.watch(dbProvider)));
final projectRepoProvider = Provider((r) => ProjectRepository(r.watch(dbProvider)));
final taskRepoProvider    = Provider((r) => TaskRepository(r.watch(dbProvider)));
final commentRepoProvider = Provider((r) => CommentRepository(r.watch(dbProvider)));
final attachRepoProvider  = Provider((r) => AttachmentRepository(r.watch(dbProvider)));
final statsRepoProvider   = Provider((r) => StatsRepository(r.watch(dbProvider)));

/// «Кто сейчас работает» — нужен для истории и проверки автора комментария.
final currentUserIdProvider = StateProvider<int?>((ref) => null);

final taskFilterProvider = StateProvider<TaskFilter>((ref) => const TaskFilter());
final pageSizeProvider = StateProvider<int>((ref) => 50);   // растёт по «Загрузить ещё»

final tasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final f = ref.watch(taskFilterProvider);
  final limit = ref.watch(pageSizeProvider);
  return ref.watch(taskRepoProvider).watch(f, limit: limit);
});

final usersProvider = StreamProvider.autoDispose(
        (ref) => ref.watch(userRepoProvider).watchAll());
final projectsProvider = StreamProvider.autoDispose(
        (ref) => ref.watch(projectRepoProvider).watchAll());
final statsProvider = StreamProvider.autoDispose(
        (ref) => ref.watch(statsRepoProvider).watch());