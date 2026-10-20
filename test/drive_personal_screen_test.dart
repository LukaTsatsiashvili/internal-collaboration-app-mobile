import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';
import 'package:gtex_collab_app/screens/drive_screen.dart';

class FakeDriveService extends DriveService {
  final List<Map<String, dynamic>> records;
  final int usage;
  int loads = 0;

  FakeDriveService(this.records, {this.usage = 2048});

  @override
  Future<PersonalDriveListing> getPersonalListing({String? parentId}) async {
    loads++;
    return PersonalDriveListing(items: records, usedBytes: usage);
  }
}

final personalItems = <Map<String, dynamic>>[
  {
    'id': 'sheet-1',
    'name': 'Budget plan',
    'kind': 'FILE',
    'owner': {'displayName': 'Nino'},
    'file': {
      'mimeType': 'application/vnd.gtex.univer-sheet+json',
      'sizeBytes': 2048,
    },
    'updatedAt': '2026-10-20T10:00:00Z',
  },
  {
    'id': 'folder-1',
    'name': 'Marketing',
    'kind': 'FOLDER',
    'owner': {'displayName': 'Luka'},
    'file': null,
    'updatedAt': '2026-10-19T10:00:00Z',
  },
];

Future<void> showDrive(WidgetTester tester, FakeDriveService service,
    {bool dark = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: DriveScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Personal Drive renders live API items, type, owner and usage',
      (tester) async {
    final service = FakeDriveService(personalItems);
    await showDrive(tester, service);

    expect(service.loads, 1);
    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Import Excel'), findsOneWidget);
    expect(find.text('New Spreadsheet'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.text('Shared with me'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Budget plan'), findsOneWidget);
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.text('Nino · owner'), findsOneWidget);
    expect(find.text('SHEET'), findsOneWidget);
    expect(find.text('FOLDER'), findsOneWidget);
    expect(find.text('2 items · 2.0 KB in Personal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search and sorting use personal records without writing',
      (tester) async {
    final service = FakeDriveService(personalItems);
    await showDrive(tester, service);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search files and folders'),
      'Budget',
    );
    await tester.pump();
    expect(find.text('Budget plan'), findsOneWidget);
    expect(find.text('Marketing'), findsNothing);
    expect(find.text('1 items · 2.0 KB in Personal'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search files and folders'),
      '',
    );
    await tester.pump();
    await tester.tap(find.text('Sort by date'));
    await tester.pump();
    expect(find.text('Marketing'), findsOneWidget);
    expect(service.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty Personal Drive shows honest empty state', (tester) async {
    await showDrive(tester, FakeDriveService([], usage: 0), dark: true);
    expect(find.text('No files or folders in Personal yet'), findsOneWidget);
    expect(find.text('0 items · 0 B in Personal'), findsOneWidget);
    expect(find.text('Untitled spreadsheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
