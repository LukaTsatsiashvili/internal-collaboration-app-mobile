import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/drive/data/drive_service.dart';
import '../features/drive/data/excel_to_univer.dart';
import '../features/drive/data/drive_download.dart';
import '../features/drive/data/univer_excel_export.dart';
import 'drive_move_dialog.dart';
import 'drive_permissions_dialog.dart';
import 'drive_members_dialog.dart';
import 'task_group_dialog.dart';

/// Visual-first Personal Drive, styled with the same semantic palette and
/// search field as Messages. All listed data comes from the real Drive API.
class DriveScreen extends StatefulWidget {
  const DriveScreen({
    super.key,
    this.service,
    this.downloadSaver,
    this.filePicker,
  });

  final DriveService? service;
  /// Optional injection for UI tests; production saves using Android MediaStore.
  final Future<DriveDownloadResult> Function(Uint8List, String)? downloadSaver;
  /// Test seam for native multi-file picker.
  final Future<List<XFile>> Function()? filePicker;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late final DriveService _driveService;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _contentScrollController = ScrollController();

  List<Map<String, dynamic>> _items = [];
  String _query = '';
  String _section = 'personal';
  List<Map<String, dynamic>> _spaces = [];
  String? _selectedSpaceId;
  String? _currentFolderAccess;
  Timer? _searchDebounce;
  bool _canCreateGroups = false;
  bool _loadingSpaces = false;
  String? _error;
  bool _loading = true;
  bool _newestFirst = true;
  bool _importingExcel = false;
  bool _creatingFolder = false;
  bool _uploadingFiles = false;
  int _uploadNumber = 0;
  int _uploadCount = 0;
  double _uploadProgress = 0;
  String _uploadName = '';
  int _usedBytes = 0;
  int _loadVersion = 0;
  int _spacesVersion = 0;
  String? _activeParent;
  List<Map<String, dynamic>> _breadcrumbs = [];
  String? _busyItemId;
  String? _downloadingItemId;
  String? _downloadedItemId;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  Map<String, dynamic>? get _selectedSpace {
    for (final space in _spaces) {
      if (space['id'] == _selectedSpaceId) return space;
    }
    return null;
  }

  // The last known access remains valid while files are refreshed;
  // a list-spinner must never cause the header to flash disabled.
  bool get _canWriteShared => _selectedSpace != null &&
      const {'OWNER', 'MANAGER', 'EDITOR', 'EDITOR_DELETE'}
          .contains(_activeParent != null
              ? _currentFolderAccess : _selectedSpace!['access']);
  bool get _canManageShared => _selectedSpace != null &&
      const {'OWNER', 'MANAGER'}.contains(_selectedSpace!['access']);

  // The action header always exists; only its enabled state changes.
  bool get _canWriteHere => _section == 'personal' ||
      (_section == 'shared' && _canWriteShared);


  @override
  void initState() {
    super.initState();
    _driveService = widget.service ?? DriveService();
    _loadPersonalDrive();
  }

  @override
  void dispose() {
    _loadVersion++;
    _spacesVersion++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonalDrive() async {
    final version = ++_loadVersion;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = _section == 'personal'
          ? await _driveService.getPersonalListing(parentId: _activeParent)
          : _section == 'shared' && _selectedSpaceId != null
              ? await _driveService.getSharedListing(
                  spaceId: _selectedSpaceId!,
                  parentId: _activeParent, search: _query)
              : _section == 'shared'
                  ? const PersonalDriveListing(items: [], usedBytes: 0)
                  : await _driveService.getDriveView(
                      view: _section,
                      parentId: _section == 'shared-with-me'
                          ? _activeParent : null,
                    );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _items = listing.items;
        _usedBytes = listing.usedBytes;
        _breadcrumbs = listing.breadcrumbs;
        _currentFolderAccess = listing.folderAccess;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadSharedSpaces({String? selectId}) async {
    if (!mounted) return;
    final version = ++_spacesVersion;
    setState(() { _loadingSpaces = true; _error = null; });
    try {
      final result = await _driveService.getSpaces();
      if (!mounted || _section != 'shared' || version != _spacesVersion) return;
      final spaces = result.spaces;
      final nextId = selectId ?? _selectedSpaceId;
      final selection = spaces.any((s) => s['id'] == nextId)
          ? nextId
          : spaces.where((s) => s['type'] == 'GLOBAL').isNotEmpty
              ? spaces.firstWhere((s) => s['type'] == 'GLOBAL')['id'].toString()
              : spaces.isNotEmpty ? spaces.first['id'].toString() : null;
      setState(() {
        _spaces = spaces;
        _canCreateGroups = result.canCreateGroups;
        _selectedSpaceId = selection;
        _loadingSpaces = false;
      });
      await _loadPersonalDrive();
    } catch (error) {
      if (!mounted || _section != 'shared' || version != _spacesVersion) return;
      setState(() {
        _loadingSpaces = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _refreshDrive() async {
    if (_section == 'shared') {
      await _loadSharedSpaces();
    } else {
      await _loadPersonalDrive();
    }
  }

  void _selectSpace(String id) {
    if (_selectedSpaceId == id) return;
    _resetContentScroll();
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _selectedSpaceId = id;
      _activeParent = null;
      _currentFolderAccess = null;
      _breadcrumbs = [];
      _query = '';
    });
    _loadPersonalDrive();
  }

  Future<void> _newSharedGroup() async {
    if (!_canCreateGroups || _creatingFolder) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const TaskGroupDialog(
        createTitle: 'New shared group',
        fieldLabel: 'Group name',
        fieldHint: 'Enter group name...',
        createButtonLabel: 'Create group',
        maxNameLength: 200,
      ),
    );
    if (!mounted || name == null) return;
    setState(() => _creatingFolder = true);
    try {
      final group = await _driveService.createSharedGroup(name);
      if (!mounted) return;
      setState(() => _activeParent = null);
      await _loadSharedSpaces(selectId: group['id'].toString());
      _feedback('Shared group created');
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _creatingFolder = false);
    }
  }

  Future<void> _members() async {
    final space = _selectedSpace;
    if (space == null || !_canManageShared) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => DriveMembersDialog(
        space: space, service: _driveService,
      ),
    );
    if (!mounted || saved != true) return;
    await _loadSharedSpaces();
    _feedback('Members saved');
  }

  DateTime? _updatedAt(Map<String, dynamic> item) {
    final value = _section == 'trash'
        ? (item['deletedAt'] ?? item['updatedAt'] ?? item['createdAt'])
        : (item['updatedAt'] ?? item['createdAt']);
    return value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  }

  List<Map<String, dynamic>> get _visibleItems {
    final query = _query.trim().toLowerCase();
    final filtered = _items
        .where((item) =>
            query.isEmpty ||
            (item['name'] ?? '').toString().toLowerCase().contains(query))
        .toList();
    filtered.sort((first, second) {
      final a = _updatedAt(first);
      final b = _updatedAt(second);
      if (a == null && b != null) return 1;
      if (b == null && a != null) return -1;
      final comparison = a == null ? 0 : a.compareTo(b!);
      if (comparison != 0) return _newestFirst ? -comparison : comparison;
      return (first['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((second['name'] ?? '').toString().toLowerCase());
    });
    return filtered;
  }

  Map<String, dynamic> _file(Map<String, dynamic> item) {
    final file = item['file'];
    return file is Map ? Map<String, dynamic>.from(file) : {};
  }

  bool _isFolder(Map<String, dynamic> item) => item['kind'] == 'FOLDER';

  bool _isSheet(Map<String, dynamic> item) =>
      _file(item)['mimeType'] == 'application/vnd.gtex.univer-sheet+json';

  String _typeLabel(Map<String, dynamic> item) {
    if (_isFolder(item)) return 'FOLDER';
    if (_isSheet(item)) return 'SHEET';
    final name = (item['name'] ?? '').toString();
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      final extension = name.substring(dot + 1).toUpperCase();
      if (extension.length <= 5) return extension;
    }
    return 'FILE';
  }

  String _ownerName(Map<String, dynamic> item) {
    final owner = item['owner'];
    if (owner is Map) return (owner['displayName'] ?? '').toString();
    return '';
  }

  String _dateLabel(Map<String, dynamic> item) {
    final date = _updatedAt(item);
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _later(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action — ფუნქციონალს შემდეგ ეტაპზე დავამატებთ')),
    );
  }

  void _feedback(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  String _errorMessage(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|FormatException|Bad state):\s*'), '');

  Future<void> _newFolder() async {
    if (_creatingFolder || _importingExcel || _uploadingFiles) return;
    if (_section == 'shared' && !_canWriteShared) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TaskGroupDialog(
        createTitle: 'New Folder',
        fieldLabel: 'Folder name',
        fieldHint: 'Enter folder name...',
        createButtonLabel: 'Create Folder',
        maxNameLength: 200,
        validateName: (text) {
          if (text == '.' || text == '..' ||
              RegExp(r'[\x00-\x1f/\\]').hasMatch(text)) {
            return 'Use a folder name without slashes or control characters';
          }
          return null;
        },
      ),
    );
    if (!mounted || name == null) return;
    setState(() => _creatingFolder = true);
    try {
      await _driveService.createFolder(name, parentId: _activeParent,
          spaceId: _section == 'shared' ? _selectedSpaceId : null);
      if (!mounted) return;
      await _loadPersonalDrive();
      _feedback('Folder created successfully');
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _creatingFolder = false);
    }
  }

  Future<void> _uploadFiles() async {
    if (_uploadingFiles || _importingExcel || _creatingFolder) return;
    if (_section == 'shared' && !_canWriteShared) return;
    try {
      final selected = await (widget.filePicker ?? openFiles)();
      if (!mounted || selected.isEmpty) return;

      // Capture the folder before picking multiple files: all selected files
      // must be linked into the same destination.
      final parentId = _activeParent;
      final spaceId = _section == 'shared' ? _selectedSpaceId : null;
      setState(() {
        _uploadingFiles = true;
        _uploadNumber = 1;
        _uploadCount = selected.length;
        _uploadProgress = 0;
        _uploadName = selected.first.name;
      });

      var completed = 0;
      String? problem;
      for (var index = 0; index < selected.length; index++) {
        final file = selected[index];
        if (mounted) {
          setState(() {
            _uploadNumber = index + 1;
            _uploadName = file.name;
            _uploadProgress = 0;
          });
        }
        try {
          await _driveService.uploadDriveFile(
            file,
            parentId: parentId,
            spaceId: spaceId,
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              final progress = (sent / total).clamp(0.0, 1.0);
              if ((progress * 100).floor() !=
                  (_uploadProgress * 100).floor()) {
                setState(() => _uploadProgress = progress);
              }
            },
          );
          completed++;
        } catch (error) {
          problem = _errorMessage(error);
          break; // Web also stops at the first failed selected file.
        }
      }

      if (!mounted) return;
      // Refresh after partial success too, so linked files never disappear.
      await _loadPersonalDrive();
      if (!mounted) return;
      if (problem != null) {
        _feedback(
          completed > 0
              ? '$completed of ${selected.length} files uploaded. '
                  'Could not upload $_uploadName: $problem'
              : 'Could not upload $_uploadName: $problem',
          error: true,
        );
      } else {
        _feedback(
          completed == 1
              ? 'File uploaded successfully'
              : '$completed files uploaded successfully',
        );
      }
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _uploadingFiles = false;
          _uploadNumber = 0;
          _uploadCount = 0;
          _uploadProgress = 0;
          _uploadName = '';
        });
      }
    }
  }

  Future<void> _importExcel() async {
    if (_importingExcel || _creatingFolder || _uploadingFiles) return;
    if (_section == 'shared' && !_canWriteShared) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Excel spreadsheets',
            extensions: ['xlsx', 'xlsm', 'xls'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      // Some Android file managers ignore extension filters; validate too.
      if (!ExcelToUniver.supportsFilename(file.name)) {
        _feedback('Choose an Excel file (.xlsx, .xlsm or .xls)', error: true);
        return;
      }

      setState(() => _importingExcel = true);
      final bytes = await file.readAsBytes();
      await _driveService.importExcel(bytes, filename: file.name,
          parentId: _activeParent,
          spaceId: _section == 'shared' ? _selectedSpaceId : null);
      if (!mounted) return;
      await _loadPersonalDrive();
      _feedback('Excel spreadsheet imported successfully');
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _importingExcel = false);
    }
  }


  void _openFolder(String? id) {
    if (_section == 'trash' || _activeParent == id) return;
    _resetContentScroll();
    setState(() {
      _activeParent = id;
      _currentFolderAccess = null;
    });
    _loadPersonalDrive();
  }

  void _resetContentScroll() {
    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(0);
    }
  }

  void _switchSection(String next) {
    if (_section == next) return;
    _resetContentScroll();
    _searchDebounce?.cancel();
    _spacesVersion++;
    _loadVersion++; // Invalidate any response from the previous tab.
    _searchController.clear();
    setState(() {
      _section = next;
      if (next == 'shared') _selectedSpaceId = null;
      _currentFolderAccess = null;
      _activeParent = null;
      _breadcrumbs = [];
      _query = '';
      _newestFirst = true;
      _items = [];
      _usedBytes = 0;
      _error = null;
    });
    if (next == 'shared') {
      _loadSharedSpaces();
    } else {
      _loadPersonalDrive();
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    if (_section != 'trash' || _busyItemId != null) return;
    await _runAction(
      item,
      'Restored successfully',
      () => _driveService.restoreItem(item['id'].toString()),
    );
  }

  Future<void> _runAction(
    Map<String, dynamic> item,
    String success,
    Future<void> Function() operation,
  ) async {
    if (_busyItemId != null) return;
    setState(() => _busyItemId = item['id'].toString());
    try {
      await operation();
      if (!mounted) return;
      await _loadPersonalDrive();
      _feedback(success);
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<void> _rename(Map<String, dynamic> item) async {
    if (_busyItemId != null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TaskGroupDialog(
        initialName: (item['name'] ?? '').toString(),
        renameTitle: 'Rename ${_isFolder(item) ? 'Folder' : 'File'}',
        fieldLabel: 'Name',
        fieldHint: 'Enter new name...',
        maxNameLength: 200,
        validateName: (value) => value == '.' || value == '..' ||
            RegExp(r'[\x00-\x1f/\\]').hasMatch(value)
                ? 'Use a name without slashes or control characters' : null,
      ),
    );
    if (!mounted || name == null || name == item['name']) return;
    await _runAction(item, 'Renamed successfully',
        () => _driveService.renameItem(item['id'].toString(), name));
  }

  Future<void> _move(Map<String, dynamic> item) async {
    if (_busyItemId != null) return;
    final moved = await showDialog<bool>(
      context: context,
      builder: (_) => DriveMoveDialog(
        item: item, service: _driveService,
        spaceId: _section == 'shared' ? _selectedSpaceId : null,
        spaceName: _section == 'shared'
            ? (_selectedSpace?['name'] ?? 'Shared').toString() : null,
      ),
    );
    if (!mounted || moved != true) return;
    await _loadPersonalDrive();
    _feedback('Moved successfully');
  }

  Future<void> _permissions(Map<String, dynamic> item) async {
    if (_busyItemId != null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => DrivePermissionsDialog(
        item: item, service: _driveService),
    );
    if (!mounted || saved != true) return;
    await _loadPersonalDrive();
    _feedback('Permissions saved');
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (_busyItemId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = Theme.of(dialogContext).extension<AppPalette>()!;
        return AlertDialog(
          backgroundColor: palette.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(23)),
          title: const Text('Move to trash?'),
          content: Text(
            '${item['name']} and its contents will be hidden from people with access. You can restore personal items from Trash.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move to trash'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) return;
    await _runAction(item, 'Moved to Trash',
        () => _driveService.trashItem(item['id'].toString()));
  }

  Future<void> _download(Map<String, dynamic> item) async {
    if (_busyItemId != null || _isFolder(item)) return;
    final id = item['id'].toString();
    setState(() {
      _busyItemId = id;
      _downloadingItemId = id;
      _downloadedItemId = null;
    });
    try {
      final file = _file(item);
      final sheet = _isSheet(item);
      final bytes = sheet
          ? await compute(UniverExcelExport.export,
              (await _driveService.getSpreadsheet(id))['snapshot']
                  as Map<String, dynamic>)
          : await _driveService.downloadFile(file['id'].toString());
      final baseName = (item['name'] ?? 'download').toString();
      final filename = sheet
          ? '${baseName.replaceFirst(RegExp(r'\.(xlsx|xlsm|xls)$',
              caseSensitive: false), '')}.xlsx'
          : baseName;
      final saved = await (widget.downloadSaver ?? DriveDownload.saveAndOpen)(
        bytes,
        filename,
      );
      if (!mounted) return;
      if (saved.saved) {
        setState(() => _downloadedItemId = id);
        // The card itself shows success; don't display a filesystem path.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted && _downloadedItemId == id) {
            setState(() => _downloadedItemId = null);
          }
        });
        if (!saved.opened) {
          _feedback(
            'File downloaded, but no compatible app was found to open it.',
          );
        }
      }
      // A cancelled legacy Android system picker is not a successful save.
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyItemId = null;
          _downloadingItemId = null;
        });
      }
    }
  }

  Widget _folderPath() {
    if (_activeParent == null || _section == 'trash') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          TextButton(
            onPressed: () => _openFolder(null),
            child: Text(_section == 'shared-with-me'
                ? 'Shared with me'
                : _section == 'shared' ? (_selectedSpace?['name'] ?? 'Shared').toString()
                : 'Personal'),
          ),
          for (final crumb in _breadcrumbs) ...[
            Icon(Icons.chevron_right_rounded, color: _p.muted, size: 16),
            TextButton(
              onPressed: () => _openFolder(crumb['id'].toString()),
              child: Text((crumb['name'] ?? '').toString()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Text(
      'Drive',
      style: TextStyle(
        color: _p.ink,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.8,
      ),
    );
  }

  Widget _uploadButton() {
    final busy = _uploadingFiles || _importingExcel || _creatingFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Opacity(
            opacity: _canWriteHere ? 1 : 0.42,
            child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy || !_canWriteHere ? null : _uploadFiles,
                borderRadius: BorderRadius.circular(15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_uploadingFiles)
                      const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      const Icon(Icons.file_upload_outlined,
                          color: Colors.white, size: 19),
                    const SizedBox(width: 9),
                    Text(
                      _uploadingFiles
                          ? 'Uploading $_uploadNumber / $_uploadCount'
                          : 'Upload files',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
        if (_uploadingFiles) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _uploadName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _p.secondaryText, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(_uploadProgress * 100).round()}%',
                style: TextStyle(
                  color: _p.link,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 4,
              backgroundColor: _p.cardBorder,
              color: _p.link,
            ),
          ),
        ],
      ],
    );
  }

  Widget _quickButton(
    String label,
    IconData icon,
    Color accent,
    double width, {
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      width: width,
      height: 43,
      child: Material(
        color: _p.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _p.cardBorder),
            ),
            child: Row(
              children: [
                if (loading)
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(icon, size: 17, color: accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    loading ? 'Importing...' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _p.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActions() {
    final busy = _importingExcel || _creatingFolder || _uploadingFiles ||
        !_canWriteHere;
    return Opacity(
      opacity: _canWriteHere ? 1 : 0.48,
      child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _quickButton(
            'Import Excel',
            Icons.file_download_outlined,
            AppColors.primary,
            122,
            onTap: busy ? null : _importExcel,
            loading: _importingExcel,
          ),
          const SizedBox(width: 8),
          _quickButton(
            'New Spreadsheet',
            Icons.table_chart_outlined,
            const Color(0xFF14AD86),
            151,
            onTap: busy ? null : () => _later('New Spreadsheet'),
          ),
          const SizedBox(width: 8),
          _quickButton(
            'New Folder',
            Icons.create_new_folder_outlined,
            const Color(0xFF7E68F5),
            123,
            onTap: busy ? null : _newFolder,
          ),
        ],
      ),
      ),
    );
  }

  // Reuses the established Messages search field geometry, typography,
  // semantic palette and clear-search behavior.
  Widget _searchField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _p.searchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          setState(() => _query = value);
          if (_section == 'shared') {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 280), () {
              if (mounted && _section == 'shared') _loadPersonalDrive();
            });
          }
        },
        style: TextStyle(
          color: _p.ink,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search files and folders',
          hintStyle: TextStyle(
            color: _p.hintText,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: _p.searchIcon),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: () {
                    _searchController.clear();
                    _searchDebounce?.cancel();
                    setState(() => _query = '');
                    if (_section == 'shared') _loadPersonalDrive();
                  },
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _tabs() {
    const labels = ['Personal', 'Shared', 'Shared with me', 'Trash'];
    const keys = ['personal', 'shared', 'shared-with-me', 'trash'];
    return Container(
      height: 39,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _p.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Tooltip(
                message: 'Open ${labels[i]}',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('drive-tab-${keys[i]}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _switchSection(keys[i]),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: keys[i] == _section
                          ? BoxDecoration(
                              color: _p.card,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: _p.cardShadow,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            )
                          : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            color: keys[i] == _section ? _p.link : _p.muted,
                            fontWeight: keys[i] == _section
                                ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sharedControls() {
    if (_loadingSpaces) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 15),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final space = _selectedSpace;
    if (space == null) {
      return _messagePanel(Icons.groups_outlined,
          _error ?? 'No shared spaces available', retry: _error != null);
    }
    final global = _spaces.where((s) => s['type'] == 'GLOBAL').toList();
    final groups = _spaces.where((s) => s['type'] == 'GROUP').toList();
    final isGlobal = space['type'] == 'GLOBAL';
    final role = (space['access'] ?? 'VIEWER').toString();
    final selectedName = (space['name'] ?? 'Shared').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _p.cardBorder),
            boxShadow: [
              BoxShadow(color: _p.cardShadow, blurRadius: 11,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 43, width: 43,
                decoration: BoxDecoration(
                    color: _p.unreadBackground,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  isGlobal ? Icons.language_rounded : Icons.groups_rounded,
                  color: _p.link, size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedName, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _p.ink, fontSize: 14,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 4),
                    Text(isGlobal
                        ? 'Company-wide shared space'
                        : 'Group workspace',
                        style: TextStyle(
                          color: _p.muted, fontSize: 10.5,
                        )),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 7),
                decoration: BoxDecoration(color: _p.panel,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(role[0] + role.substring(1).toLowerCase(),
                    style: TextStyle(
                      color: _p.secondaryText,
                      fontSize: 10.5, fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('GROUPS', style: TextStyle(
                color: _p.muted, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 0.65)),
            const Spacer(),
            if (_canCreateGroups)
              TextButton.icon(
                key: const ValueKey('shared-add-group'),
                onPressed: _creatingFolder ? null : _newSharedGroup,
                icon: Icon(Icons.add_rounded, size: 15, color: _p.link),
                label: Text('Add', style: TextStyle(
                    color: _p.link, fontSize: 11,
                    fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (final option in [...global, ...groups]) ...[
                _spaceChip(option),
                const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        // Requested layout: a separate Members button *below* group chips.
        if (_canManageShared) ...[
          const SizedBox(height: 13),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('shared-members'),
              onPressed: _members,
              icon: Icon(Icons.manage_accounts_outlined,
                  size: 17, color: _p.link),
              label: Text('Members', style: TextStyle(
                color: _p.ink, fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
              style: OutlinedButton.styleFrom(
                backgroundColor: _p.card,
                side: BorderSide(color: _p.cardBorder),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _spaceChip(Map<String, dynamic> space) {
    final id = space['id'].toString();
    final selected = id == _selectedSpaceId;
    final global = space['type'] == 'GLOBAL';
    return Material(
      color: selected ? AppColors.primary : _p.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('shared-space-$id'),
        onTap: () => _selectSpace(id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : _p.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(global ? Icons.language_rounded : Icons.groups_rounded,
                  size: 15, color: selected ? Colors.white : _p.muted),
              const SizedBox(width: 6),
              Text((space['name'] ?? '').toString(),
                  style: TextStyle(
                    color: selected ? Colors.white : _p.secondaryText,
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileHeading() {
    return Row(
      children: [
        Text(
          _section == 'shared' ? 'FILES & FOLDERS' : 'FILES',
          style: TextStyle(
            color: _p.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _newestFirst = !_newestFirst),
          style: TextButton.styleFrom(
            foregroundColor: _p.link,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sort by date',
                style: TextStyle(
                  color: _p.link,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _newestFirst
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardAction(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool destructive = false,
    bool loading = false,
    bool completed = false,
  }) {
    return IconButton(
      key: ValueKey('drive-action-$label'),
      onPressed: onPressed,
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
      padding: EdgeInsets.zero,
      iconSize: 17,
      color: completed
          ? const Color(0xFF16B48D)
          : destructive
              ? Theme.of(context).colorScheme.error
              : _p.previewText,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(completed ? Icons.check_circle_rounded : icon),
    );
  }

  Widget _fileCard(Map<String, dynamic> item) {
    final folder = _isFolder(item);
    final sheet = _isSheet(item);
    final ownerName = _ownerName(item);
    final access = (item['access'] ?? '').toString();
    final busy = _busyItemId != null;
    final canEdit = const {'OWNER','MANAGER','EDITOR','EDITOR_DELETE'}
        .contains(access);
    final canManage = const {'OWNER','MANAGER'}.contains(access);
    final canMove = _section == 'shared' ? canEdit : access == 'OWNER';
    final canDelete = _section == 'shared'
        ? const {'OWNER', 'MANAGER', 'EDITOR_DELETE'}.contains(access)
        : access == 'OWNER';
    final file = _file(item);
    final bytes = file['sizeBytes'] is num
        ? (file['sizeBytes'] as num).toInt()
        : null;
    final tint = folder
        ? (_section == 'shared'
            ? const Color(0xFFF1A412) : const Color(0xFF8A6DFA))
        : sheet
            ? const Color(0xFF15AF8D)
            : AppColors.primary;
    final tintedBg = tint.withValues(alpha: 0.10);
    final icon = folder
        ? Icons.folder_outlined
        : sheet
            ? Icons.table_chart_outlined
            : Icons.insert_drive_file_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 13, 12, 8),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: _p.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: folder ? () => _openFolder(item['id'].toString()) : null,
            borderRadius: BorderRadius.circular(12),
            child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tintedBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 24, color: tint),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['name'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (ownerName.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '$ownerName · owner',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _p.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: _p.panel,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  _section == 'shared' && sheet
                      ? 'XLSX' : _typeLabel(item),
                  style: TextStyle(
                    color: _p.secondaryText,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          ),
          const SizedBox(height: 12),
          Divider(color: _p.cardBorder, thickness: 1, height: 1),
          const SizedBox(height: 3),
          // Fill the entire card width. An Expanded date area anchors the
          // trailing actions to the far right, even when Shared With Me
          // shows only one Download button.
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, color: _p.muted, size: 13),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _dateLabel(item),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: _p.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!folder)
                  _cardAction(
                    Icons.download_outlined,
                    'Download',
                    busy ? null : () => _download(item),
                    loading: _downloadingItemId == item['id'],
                    completed: _downloadedItemId == item['id'],
                  ),
                if (_section == 'personal' || _section == 'shared') ...[
                  _cardAction(Icons.edit_outlined, 'Rename',
                      canEdit && !busy ? () => _rename(item) : null),
                  _cardAction(Icons.share_outlined, 'Permissions',
                      canManage && !busy ? () => _permissions(item) : null),
                  _cardAction(Icons.drive_file_move_outline, 'Move',
                      canMove && !busy ? () => _move(item) : null),
                  _cardAction(Icons.delete_outline_rounded, 'Delete',
                      canDelete && !busy ? () => _delete(item) : null,
                      destructive: true),
                ],
              ],
            ),
          ),
          if (bytes != null && bytes > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _sizeLabel(bytes),
                style: TextStyle(
                  color: _p.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trashTop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: 'Empty Trash will be available in a future update',
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey('drive-empty-trash'),
              onPressed: null, // Intentionally visual-only in this phase.
              icon: const Icon(Icons.delete_sweep_outlined, size: 19),
              label: const Text(
                'Empty Trash',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor:
                    const Color(0xFFF53861).withValues(alpha: 0.8),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _trashInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: _p.unreadBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: _p.link, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Items in Trash are permanently deleted after 30 days.',
              style: TextStyle(
                color: _p.secondaryText,
                fontWeight: FontWeight.w500,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trashCard(Map<String, dynamic> item) {
    final folder = _isFolder(item);
    final sheet = _isSheet(item);
    final ownerName = _ownerName(item);
    final tint = folder
        ? const Color(0xFF8A6DFA)
        : sheet
            ? const Color(0xFF15AF8D)
            : AppColors.primary;
    final icon = folder
        ? Icons.folder_outlined
        : sheet
            ? Icons.table_chart_outlined
            : Icons.insert_drive_file_outlined;
    final busy = _busyItemId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 13, 12, 8),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: _p.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 45,
                width: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tint, size: 24),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['name'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (ownerName.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '$ownerName · owner',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _p.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: _p.panel,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  sheet ? 'XLSX' : _typeLabel(item),
                  style: TextStyle(
                    color: _p.secondaryText,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: _p.cardBorder, thickness: 1, height: 1),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.schedule_outlined, color: _p.muted, size: 13),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _dateLabel(item),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _p.muted,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
              ),
              _cardAction(
                Icons.restore_rounded,
                'Restore',
                busy ? null : () => _restore(item),
                loading: _busyItemId == item['id'],
              ),
              Tooltip(
                message: 'Permanent deletion is not available yet',
                child: IconButton(
                  key: const ValueKey('drive-permanent-delete'),
                  onPressed: null,
                  tooltip: 'Permanently delete (coming soon)',
                  iconSize: 17,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 34),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.delete_outline_rounded, color: _p.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messagePanel(IconData icon, String message, {bool retry = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: _p.muted),
          const SizedBox(height: 9),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _p.secondaryText, fontSize: 12),
          ),
          if (retry)
            TextButton(onPressed: _refreshDrive, child: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    final isTrash = _section == 'trash';
    final isSharedWithMe = _section == 'shared-with-me';
    final isShared = _section == 'shared';

    return Scaffold(
      backgroundColor: _p.page,
      body: SafeArea(
        child: Column(
          children: [
            // Persistent header: changing tabs only changes action
            // availability, never its position, size or widget identity.
            Padding(
              key: const ValueKey('drive-persistent-header'),
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 13),
                  _uploadButton(),
                  const SizedBox(height: 10),
                  _quickActions(),
                  const SizedBox(height: 15),
                  _searchField(),
                  const SizedBox(height: 13),
                  _tabs(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Only the tab contents refresh/scroll below the stable header.
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshDrive,
                child: ListView(
                  key: const ValueKey('drive-tab-content'),
                  controller: _contentScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 24),
                  children: [
                    if (isTrash) ...[
                      _trashTop(),
                      _trashInfo(),
                      const SizedBox(height: 12),
                    ],
                    if (isShared) _sharedControls(),
                    if (_activeParent != null && !isTrash) _folderPath(),
                    _fileHeading(),
                    const SizedBox(height: 7),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _messagePanel(
                        Icons.cloud_off_outlined, _error!, retry: true)
                    else if (visible.isEmpty)
                      _messagePanel(
                        Icons.folder_open_outlined,
                        _query.isNotEmpty
                            ? 'No files or folders match your search'
                            : isTrash
                                ? 'Your trash is empty'
                                : isSharedWithMe
                                    ? 'No files have been shared with you yet'
                                    : isShared
                                        ? 'No files or folders in this shared space'
                                        : 'No files or folders in Personal yet',
                      )
                    else if (isTrash)
                      ...visible.map(_trashCard)
                    else
                      ...visible.map(_fileCard),
                    if (!_loading && _error == null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          isTrash
                              ? '${visible.length} ${visible.length == 1 ? 'item' : 'items'} in Trash'
                              : isSharedWithMe
                                  ? '${visible.length} ${visible.length == 1 ? 'item' : 'items'} shared with me'
                                  : isShared
                                      ? '${visible.length} ${visible.length == 1 ? 'item' : 'items'} in ${_selectedSpace?['name'] ?? 'Shared'}'
                                      : '${visible.length} ${visible.length == 1 ? 'item' : 'items'} · ${_sizeLabel(_usedBytes)} in Personal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _p.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
