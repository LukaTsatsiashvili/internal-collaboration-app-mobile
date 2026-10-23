
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/people/data/people_service.dart';
import 'package:gtex_collab_app/screens/people_screen.dart';
import 'package:gtex_collab_app/screens/people_filter_dialog.dart';

class FakePeopleService extends PeopleService {
  final calls = <Map<String, String?>>[];
  bool fail = false;

  @override
  Future<List<Map<String, dynamic>>> getDepartments() async => [
    {'id': 'd1', 'name': 'Stores'},
    {'id': 'd2', 'name': 'Office'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getPeople({
    String query = '',
    String? departmentId,
    String? role,
    String? status = 'ACTIVE',
  }) async {
    calls.add({
      'q': query,
      'departmentId': departmentId,
      'role': role,
      'status': status,
    });
    if (fail) throw StateError('network disconnected');
    final people = [
      {
        'id': 'u1',
        'displayName': 'English Home East Point',
        'email': 'ehep@gtex.ge',
        'phone': '+995 577 259 543',
        'status': 'ACTIVE',
        'jobTitle': 'Employee',
        'departmentId': 'd1',
        'department': {'id': 'd1', 'name': 'Stores'},
        'roles': ['EMPLOYEE'],
      },
      {
        'id': 'u2',
        'displayName': 'Office Manager',
        'email': 'manager@gtex.ge',
        'phone': null,
        'status': 'INACTIVE',
        'jobTitle': 'Manager',
        'departmentId': 'd2',
        'department': {'id': 'd2', 'name': 'Office'},
        'roles': ['MANAGER'],
      },
    ];
    return people.where((person) {
      final textMatches = query.isEmpty ||
          person['displayName'].toString().toLowerCase()
              .contains(query.toLowerCase());
      final departmentMatches = departmentId == null ||
          person['departmentId'] == departmentId;
      final statusMatches = status == null || person['status'] == status;
      final roleMatches = role == null ||
          (person['roles'] as List).contains(role);
      return textMatches && departmentMatches &&
          statusMatches && roleMatches;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

Future<void> mountPeople(
  WidgetTester tester,
  FakePeopleService service,
  List<Uri> launched, {
  bool dark = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: PeopleScreen(service: service, launchLink: (uri) async {
      launched.add(uri);
      return true;
    }),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('default prod directory status and clear filters', () {
    const f = PeopleFilters();
    expect(f.status, 'ACTIVE');
    expect(f.activeCount, 1);
    expect(f.withDepartment('d1').departmentId, 'd1');
    expect(f.withRole('MANAGER').role, 'MANAGER');
    expect(f.withStatus(null).status, isNull);
    expect(PeopleFilters.clear.activeCount, 0);
  });

  for (final dark in [false, true]) {
    testWidgets('People cards and contact actions in ${dark ? 'dark' : 'light'}',
        (tester) async {
      final service = FakePeopleService();
      final links = <Uri>[];
      await mountPeople(tester, service, links, dark: dark);

      expect(find.text('People'), findsOneWidget);
      expect(find.text('Employee directory'), findsNothing);
      // Only the outer Messages-style rounded search surface is painted.
      final searchContainer = tester.widget<Container>(
        find.byKey(const ValueKey('people-search-surface')),
      );
      final searchDecoration = searchContainer.decoration! as BoxDecoration;
      expect(searchDecoration.border, isNull);
      expect(searchDecoration.borderRadius, BorderRadius.circular(16));
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('people-search')),
      );
      expect(search.decoration!.filled, isFalse);
      expect(search.decoration!.border, InputBorder.none);
      expect(search.decoration!.focusedBorder, InputBorder.none);
      expect(search.decoration!.enabledBorder, InputBorder.none);
      expect(find.byKey(const ValueKey('people-card-u1')), findsOneWidget);
      expect(find.byKey(const ValueKey('people-card-u2')), findsNothing);
      expect(find.text('Stores'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
      expect(service.calls.first['status'], 'ACTIVE');

      await tester.tap(find.byKey(const ValueKey('people-email-u1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('people-phone-u1')));
      await tester.pump();

      expect(links.length, 2);
      expect(links[0].scheme, 'mailto');
      expect(links[0].path, 'ehep@gtex.ge');
      expect(links[1].scheme, 'tel');
      expect(links[1].path, '+995577259543');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search and 3 prod filters can be applied and cleared',
      (tester) async {
    final service = FakePeopleService();
    await mountPeople(tester, service, []);

    await tester.enterText(find.byKey(const ValueKey('people-search')),
        'East Point');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(service.calls.last['q'], 'East Point');
    expect(find.byKey(const ValueKey('people-card-u1')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('people-search')), '');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('people-filter-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('people-filter-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-select-dropdown-All departments')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app-select-dropdown-All roles')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app-select-dropdown-All statuses')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-select-dropdown-All statuses')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(service.calls.last['status'], isNull);
    expect(find.byKey(const ValueKey('people-card-u2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline load failure is recoverable', (tester) async {
    final service = FakePeopleService()..fail = true;
    await mountPeople(tester, service, []);
    expect(find.byKey(const ValueKey('app-load-error-state')), findsOneWidget);
    service.fail = false;
    await tester.tap(find.byKey(const ValueKey('app-load-error-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('people-card-u1')), findsOneWidget);
  });

  testWidgets('compact device displays People search and filter', (tester) async {
    tester.view.physicalSize = const Size(340, 710);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mountPeople(tester, FakePeopleService(), []);
    expect(find.byKey(const ValueKey('people-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('people-filter-open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
