class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final filter = ref.watch(taskFilterProvider);
    final pageSize = ref.watch(pageSizeProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(hintText: 'Поиск…', border: InputBorder.none),
          onChanged: (v) => ref.read(taskFilterProvider.notifier).state =
              filter.copyWith(query: v),
        ),
        actions: [
          PopupMenuButton<TaskSort>(
            onSelected: (s) => ref.read(taskFilterProvider.notifier).state =
                filter.copyWith(sort: s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: TaskSort.createdDesc, child: Text('Новые сверху')),
              PopupMenuItem(value: TaskSort.deadlineAsc, child: Text('По дедлайну')),
            ],
          ),
        ],
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView.builder(
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == list.length) {
              return list.length < pageSize
                  ? const SizedBox()       // всё загружено
                  : TextButton(
                  onPressed: () => ref.read(pageSizeProvider.notifier).state += 50,
                  child: const Text('Загрузить ещё'));
            }
            final t = list[i];
            return ListTile(
              title: Text(t.title),
              subtitle: Text('${t.status.name} • ${t.priority.name}'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id))),
            );
          },
        ),
      ),
    );
  }
}