import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class DriveDownload {
  DriveDownload._();

  /// Save bytes to Downloads when writable, falling back to app Documents.
  /// Existing files are never overwritten.
  static Future<File> save(Uint8List bytes, String proposedName) async {
    final clean = proposedName.replaceAll(
        RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    final name = clean.isEmpty ? 'download' : clean;
    Directory directory;
    try {
      directory = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      if (!await directory.exists()) await directory.create(recursive: true);
    } catch (_) {
      directory = await getApplicationDocumentsDirectory();
    }

    Future<File> writeTo(Directory folder) async {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var target = File('${folder.path}${Platform.pathSeparator}$name');
      var index = 2;
      while (await target.exists()) {
        target = File('${folder.path}${Platform.pathSeparator}$stem ($index)$ext');
        index++;
      }
      await target.writeAsBytes(bytes, flush: true);
      return target;
    }

    try {
      return await writeTo(directory);
    } on FileSystemException {
      final documents = await getApplicationDocumentsDirectory();
      if (directory.path == documents.path) rethrow;
      return writeTo(documents);
    }
  }
}
