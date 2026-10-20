import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtex_collab_app/features/drive/data/drive_service.dart';

void main() {
  test('Shared lists use spaceId, not shared-with-me view', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'success': true,
          'data': [{'id': 'file-id', 'name': 'Reports', 'kind': 'FOLDER'}],
          'meta': {'breadcrumbs': [
            {'id': 'parent-id', 'name': 'Finance'},
          ]},
        },
      ));
    }));
    final service = DriveService(dio: dio);
    final listing = await service.getSharedListing(
      spaceId: 'global-id', parentId: 'parent-id');
    expect(requests.single.path, '/drive');
    expect(requests.single.queryParameters, {
      'spaceId': 'global-id', 'parentId': 'parent-id',
    });
    expect(listing.items.single['name'], 'Reports');
    expect(listing.breadcrumbs.single['name'], 'Finance');
  });

  test('Shared space discovery preserves access and group-creation permission',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/drive/spaces');
      handler.resolve(Response(requestOptions: options, data: {
        'success': true,
        'data': [
          {'id': 'global-id', 'type': 'GLOBAL',
            'name': 'Global', 'access': 'MANAGER'},
          {'id': 'group-id', 'type': 'GROUP',
            'name': 'Shops', 'access': 'VIEWER'},
        ],
        'meta': {'canCreateGroups': true, 'canManageGlobal': true},
      }));
    }));
    final result = await DriveService(dio: dio).getSpaces();
    expect(result.spaces.length, 2);
    expect(result.spaces.first['access'], 'MANAGER');
    expect(result.canCreateGroups, isTrue);
    expect(result.canManageGlobal, isTrue);
  });

  test('Create group uses Web POST and returns new group', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.method, 'POST');
      expect(options.path, '/drive/spaces');
      expect(options.data, {'name': 'Shops'});
      handler.resolve(Response(requestOptions: options, statusCode: 201,
          data: {'success': true, 'data': {
            'id': 'new-id', 'name': 'Shops', 'type': 'GROUP',
          }}));
    }));
    final group = await DriveService(dio: dio).createSharedGroup(' Shops ');
    expect(group['id'], 'new-id');
  });

  test('Shared Members GET/PUT use roles and exact member payload', () async {
    final calls = <Map<String, Object?>>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls.add({'method': options.method, 'path': options.path,
        'body': options.data});
      handler.resolve(Response(
        requestOptions: options, statusCode: 200,
        data: options.method == 'GET'
            ? {
                'success': true,
                'data': [
                  {'userId': 'person-1', 'role': 'MANAGER'},
                ],
                'meta': {'type': 'GROUP', 'name': 'Shops'},
              }
            : {'success': true, 'data': null},
      ));
    }));
    final service = DriveService(dio: dio);
    final members = await service.getSpaceMembers('group-id');
    expect(members.members.single['role'], 'MANAGER');
    expect(members.type, 'GROUP');
    await service.saveSpaceMembers('group-id', [
      {'userId': 'person-1', 'role': 'MANAGER'},
      {'userId': 'person-2', 'role': 'EDITOR'},
    ]);
    expect(calls[0]['method'], 'GET');
    expect(calls[0]['path'], '/drive/spaces/group-id/members');
    expect(calls[1], {
      'method': 'PUT',
      'path': '/drive/spaces/group-id/members',
      'body': {'members': [
        {'userId': 'person-1', 'role': 'MANAGER'},
        {'userId': 'person-2', 'role': 'EDITOR'},
      ]},
    });
  });

  test('Shared files, folders and Excel use selected spaceId', () async {
    final seen = <Map<String, Object?>>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      seen.add({'path': options.path, 'data': options.data});
      handler.resolve(Response(
        requestOptions: options, statusCode: 201,
        data: {'success': true, 'data': {
          'id': 'item-id', 'kind': 'FOLDER',
        }},
      ));
    }));
    final service = DriveService(dio: dio);
    await service.createFolder('Invoices', spaceId: 'group-id',
        parentId: 'folder-id');
    expect(seen.single['path'], '/drive');
    expect(seen.single['data'], {
      'name': 'Invoices',
      'parentId': 'folder-id',
      'spaceId': 'group-id',
    });
  });
}
