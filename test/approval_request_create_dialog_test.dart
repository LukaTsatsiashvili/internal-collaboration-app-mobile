import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/core/theme/app_theme_extensions.dart';
import 'package:gtex_collab_app/features/approvals/data/approval_service.dart';
import 'package:gtex_collab_app/screens/approval_request_create_dialog.dart';

class FakeApprovalRequestService extends ApprovalService {
  final saved = <Map<String, dynamic>>[];
  int uploads = 0;
  String? uploadedName;
  int typeFetches = 0;

  @override
  Future<String> uploadApprovalAttachment(
      List<int> bytes, String fileName) async {
    uploads++;
    uploadedName = fileName;
    expect(bytes, [65, 66, 67]);
    return 'uploaded-file-1';
  }

  @override
  Future<List<dynamic>> getApprovalTypes() async {
    typeFetches++;
    return [{
      'id': 'type-1',
      'name': 'Budget request',
      'status': 'ACTIVE',
      'formSchema': {
        'reason': {'label':'Reason', 'type':'textarea','required':true},
        'amount': {'label':'Amount','type':'number','required':false},
      },
    }, {
      'id': 'type-2',
      'name': 'Leave request',
      'status': 'ACTIVE',
      'formSchema': {
        'from': {'label':'From','type':'date','required':true},
      },
    }];
  }

  @override
  Future<Map<String, dynamic>> createApprovalRequest({
    required String approvalTypeId,
    required String title,
    required Map<String, dynamic> data,
    required bool submit,
    List<String> attachmentIds = const [],
  }) async {
    saved.add({
      'approvalTypeId':approvalTypeId,
      'title':title,
      'data':data,
      'submit':submit,
      'attachmentIds': attachmentIds,
    });
    return {'id':'new-request-1','status':submit?'PENDING':'DRAFT'};
  }
}

Future<void> openNewRequest(
    WidgetTester tester, FakeApprovalRequestService service, {
    Future<XFile?> Function()? filePicker,
  }) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(body: Builder(
      builder: (context) => Center(child: ElevatedButton(
        child: const Text('Open New Request'),
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => ApprovalRequestCreateDialog(
            service: service,
            filePicker: filePicker,
          ),
        ),
      )),
    )),
  ));
  await tester.tap(find.text('Open New Request'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save Draft accepts empty required dynamic fields', (tester) async {
    final service = FakeApprovalRequestService();
    await openNewRequest(tester, service);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Choose request type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budget request').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('new-approval-request-title')), 'Office budget');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(service.saved, hasLength(1));
    expect(service.saved.first['submit'], false);
    expect(service.saved.first['approvalTypeId'], 'type-1');
    expect(service.saved.first['attachmentIds'], isEmpty);
    expect(service.saved.first['data'], isEmpty);
  });

  testWidgets('Submit rejects missing required fields and submits numbers',
      (tester) async {
    final service = FakeApprovalRequestService();
    await openNewRequest(tester, service);
    await tester.tap(find.byTooltip('Choose request type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budget request').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-approval-request-title')), 'Office budget');
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(service.saved, isEmpty);
    expect(find.textContaining('Reason is required'), findsOneWidget);

    final reason = find.byKey(
      const ValueKey('approval-request-type-1-reason'));
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Workstation purchase');
    final amount = find.byKey(
      const ValueKey('approval-request-type-1-amount'));
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '1599.25');
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(service.saved, hasLength(1));
    expect(service.saved.first['submit'], true);
    expect(service.saved.first['data']['reason'], 'Workstation purchase');
    expect(service.saved.first['data']['amount'], 1599.25);
  });
  testWidgets('attachment bytes upload before creating the approval request',
      (tester) async {
    final service = FakeApprovalRequestService();
    await openNewRequest(tester, service, filePicker: () async =>
        XFile.fromData(
          Uint8List.fromList([65, 66, 67]),
          name: 'approval.txt',
          mimeType: 'text/plain',
        ));
    await tester.tap(find.byTooltip('Choose request type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budget request').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('new-approval-request-title')), 'Budget draft');

    final chooseFile = find.text('Choose file');
    await tester.ensureVisible(chooseFile);
    await tester.tap(chooseFile);
    await tester.pumpAndSettle();
    expect(find.text('approval.txt'), findsOneWidget);
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(service.uploads, 1);
    expect(service.uploadedName, 'approval.txt');
    expect(service.saved, hasLength(1));
    expect(service.saved.single['attachmentIds'], ['uploaded-file-1']);
  });

  testWidgets('request type menu never exceeds its parent dropdown width',
      (tester) async {
    final service = FakeApprovalRequestService();
    await openNewRequest(tester, service);

    final menu = find.byType(PopupMenuButton<String>).first;
    final popup = tester.widget<PopupMenuButton<String>>(menu);
    final parentWidth = tester.getSize(menu).width;
    expect(popup.constraints, isNotNull);
    expect(popup.constraints!.maxWidth,
        lessThanOrEqualTo(parentWidth + 0.1));
    expect(tester.takeException(), isNull);
  });

}
