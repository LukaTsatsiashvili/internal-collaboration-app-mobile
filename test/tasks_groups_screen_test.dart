import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/tasks/data/task_service.dart';
import 'package:gtex_collab_app/screens/task_create_sheet.dart';
import 'package:gtex_collab_app/screens/tasks_screen.dart';

class FakeTaskGroupsService extends TaskService {
  String groupName = 'Marketing';
  bool deleted = false;
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, String>> renamed = [];
  final List<String> deletedIds = [];

  @override
  Future<String> getCurrentUserId() async => 'user-1';

  @override
  Future<List<dynamic>> getUsers() async => [];

  @override
  Future<List<dynamic>> getTaskGroups() async => deleted
      ? []
      : [{'id': 'marketing', 'name': groupName, 'position': 1000}];

  @override
  Future<List<dynamic>> getTasks({String? status}) async => [
    {
      'id': 'existing-1',
      'title': 'Campaign plan',
      'description': '',
      'priority': 'NORMAL',
      'status': 'OPEN',
      'creatorId': 'user-1',
      'assigneeId': null,
      'personalLayout': {'groupId': deleted ? null : 'marketing',
        'position': 1000},
      'participants': [],
    },
    ...created.map((item) => {
      'id': 'created-${created.indexOf(item) + 1}',
      'title': item['title'],
      'description': '',
      'priority': 'NORMAL',
      'status': 'OPEN',
      'creatorId': 'user-1',
      'assigneeId': null,
      'personalLayout': {
        'groupId': deleted ? null : item['groupId'],
        'position': 2000,
      },
      'participants': [],
    }),
  ];

  @override
  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    String? groupId,
    String? priority,
    String? dueDate,
    List<String>? participantIds,
    List<String>? attachmentIds,
  }) async {
    created.add({'title': title, 'groupId': groupId});
  }

  @override
  Future<Map<String, dynamic>> renameTaskGroup({
    required String id,
    required String name,
  }) async {
    renamed.add({'id': id, 'name': name});
    groupName = name;
    return {'id': id, 'name': name, 'position': 1000};
  }

  @override
  Future<void> deleteTaskGroup(String id) async {
    deletedIds.add(id);
    deleted = true;
  }
}

Future<void> pumpTasks(
    WidgetTester tester, FakeTaskGroupsService service) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: TasksScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('task added from group preselects group and saves its ID',
      (tester) async {
    final service = FakeTaskGroupsService();
    await pumpTasks(tester, service);

    final group = find.byKey(const PageStorageKey<String>(
        'task-group-marketing-populated'));
    final add = find.descendant(
      of: group, matching: find.text('+ Add task'),
    );
    await tester.tap(add);
    await tester.pumpAndSettle();

    // Only one Marketing label exists inside the modal, on its selected
    // Group control, before the popup is opened.
    expect(find.descendant(of: find.byType(TaskCreateSheet),
        matching: find.text('Marketing')), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Enter task title...'),
      'New marketing task',
    );
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    expect(service.created, hasLength(1));
    expect(service.created.single['groupId'], 'marketing');
    expect(service.created.single['title'], 'New marketing task');
    expect(find.text('New marketing task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global New Task keeps Ungrouped as initial choice',
      (tester) async {
    final service = FakeTaskGroupsService();
    await pumpTasks(tester, service);
    await tester.tap(find.text('New task').first);
    await tester.pumpAndSettle();

    final modal = find.byType(TaskCreateSheet);
    expect(find.descendant(of: modal, matching: find.text('Ungrouped')),
      findsOneWidget);
    expect(find.descendant(of: modal, matching: find.text('Marketing')),
      findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming changes group name without deleting its tasks',
      (tester) async {
    final service = FakeTaskGroupsService();
    await pumpTasks(tester, service);
    await tester.tap(find.byKey(
        const ValueKey('edit-task-group-marketing')));
    await tester.pumpAndSettle();
    expect(find.text('Rename task group'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Sales');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.renamed, [{'id': 'marketing', 'name': 'Sales'}]);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Campaign plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletion needs confirmation; tasks move to Ungrouped',
      (tester) async {
    final service = FakeTaskGroupsService();
    await pumpTasks(tester, service);
    await tester.tap(find.byKey(
        const ValueKey('delete-task-group-marketing')));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Marketing”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.deletedIds, isEmpty);

    await tester.tap(find.byKey(
        const ValueKey('delete-task-group-marketing')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(service.deletedIds, ['marketing']);
    expect(find.text('Marketing'), findsNothing);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Campaign plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global press feedback is disabled but tabs remain selected',
      (tester) async {
    final service = FakeTaskGroupsService();
    await pumpTasks(tester, service);
    final theme = Theme.of(tester.element(find.byType(TasksScreen)));
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.splashColor, Colors.transparent);
    expect(theme.highlightColor, Colors.transparent);
    await tester.tap(find.text('Active').first);
    await tester.pumpAndSettle();
    expect(find.text('Campaign plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
