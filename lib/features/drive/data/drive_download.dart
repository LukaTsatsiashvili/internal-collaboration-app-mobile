import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class DriveDownloadResult {
  const DriveDownloadResult({required this.saved, required this.opened});

  final bool saved;
  final bool opened;

  factory DriveDownloadResult.fromNative(Map<dynamic, dynamic>? value) {
    if (value == null || value['saved'] is! bool) {
      throw const FormatException('Invalid download result');
    }
    return DriveDownloadResult(
      saved: value['saved'] == true,
      opened: value['opened'] == true,
    );
  }
}

class DriveDownload {
  DriveDownload._();

  static const MethodChannel _androidDownloads =
      MethodChannel('gtex_collab_app/drive_download');

  /// Android 10+: MediaStore creates a discoverable file under the *public*
  /// Downloads/GTEX Collaboration folder, then opens it with ACTION_VIEW.
  /// Older Android uses the native system save picker before opening.
  /// On iOS, the Files-visible Documents/GTEX Collaboration folder is used.
  static Future<DriveDownloadResult> saveAndOpen(
    Uint8List bytes,
    String proposedName,
  ) async {
    if (bytes.isEmpty) throw StateError('Cannot save an empty download');
    final name = safeFilename(proposedName);

    if (Platform.isAndroid) {
      final directory = await getTemporaryDirectory();
      final temporary = File(
        '${directory.path}${Platform.pathSeparator}'
        'drive-${DateTime.now().microsecondsSinceEpoch}',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        final result = await _androidDownloads.invokeMapMethod<dynamic, dynamic>(
          'saveAndOpen',
          {'path': temporary.path, 'name': name},
        );
        return DriveDownloadResult.fromNative(result);
      } on PlatformException catch (error) {
        throw Exception(error.message ?? 'Could not save the download');
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }

    // iOS Files app exposes the Documents directory once the app declares
    // UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace.
    final saved = await save(bytes, name);
    final open = await OpenFilex.open(saved.path);
    return DriveDownloadResult(
      saved: true,
      opened: open.type == ResultType.done,
    );
  }

  static String safeFilename(String filename) {
    final sanitized = filename
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    return sanitized.isEmpty ? 'download' : sanitized;
  }

  /// Non-Android fallback. Avoid overwriting previous downloads.
  static Future<File> save(Uint8List bytes, String proposedName) async {
    final filename = safeFilename(proposedName);
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}GTEX Collaboration',
    );
    if (!await directory.exists()) await directory.create(recursive: true);

    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final extension = dot > 0 ? filename.substring(dot) : '';
    var target = File(
      '${directory.path}${Platform.pathSeparator}$filename',
    );
    var index = 2;
    while (await target.exists()) {
      target = File(
        '${directory.path}${Platform.pathSeparator}'
        '$stem ($index)$extension',
      );
      index++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return target;
  }
}
