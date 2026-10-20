import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_selector/file_selector.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/drive/data/drive_service.dart';
import '../features/drive/data/excel_to_univer.dart';
import '../features/drive/data/drive_download.dart';
import '../features/drive/data/univer_excel_export.dart';
import 'drive_move_dialog.dart';
import 'drive_permissions_dialog.dart';
import 'task_group_dialog.dart';

/// Visual-first Personal Drive, styled with the same semantic palette and
/// search field as Messages. All listed data comes from the real Drive API.
class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key, this.service});

  final DriveService? service;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late final DriveService _driveService;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _newestFirst = true;
  bool _importingExcel = false;
  bool _creatingFolder = false;
  int _usedBytes = 0;
  int _loadVersion = 0;
  String? _activeParent;
  List<Map<String, dynamic>> _breadcrumbs = [];
  String? _busyItemId;

  AppPalette get _p => Theme.of(context).extension<AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _driveService = widget.service ?? DriveService();
    _loadPersonalDrive();
  }

  @override
  void dispose() {
    _loadVersion++;
    _searchController.dispose();
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
      final listing = await _driveService.getPersonalListing(parentId: _activeParent);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _items = listing.items;
        _usedBytes = listing.usedBytes;
        _breadcrumbs = listing.breadcrumbs;
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

  DateTime? _updatedAt(Map<String, dynamic> item) {
    final value = item['updatedAt'] ?? item['createdAt'];
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
    if (_creatingFolder || _importingExcel) return;
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
      await _driveService.createFolder(name, parentId: _activeParent);
      if (!mounted) return;
      await _loadPersonalDrive();
      _feedback('Folder created successfully');
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _creatingFolder = false);
    }
  }

  Future<void> _importExcel() async {
    if (_importingExcel || _creatingFolder) return;
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
          parentId: _activeParent);
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
    if (_activeParent == id) return;
    setState(() => _activeParent = id);
    _loadPersonalDrive();
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
      builder: (_) => DriveMoveDialog(item: item, service: _driveService),
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
    setState(() => _busyItemId = item['id'].toString());
    try {
      final file = _file(item);
      final sheet = _isSheet(item);
      final bytes = sheet
          ? await compute(UniverExcelExport.export,
              (await _driveService.getSpreadsheet(
                  item['id'].toString()))['snapshot'] as Map<String, dynamic>)
          : await _driveService.downloadFile(file['id'].toString());
      final baseName = (item['name'] ?? 'download').toString();
      final filename = sheet
          ? '${baseName.replaceFirst(RegExp(r'\.(xlsx|xlsm|xls)
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
    return SizedBox(
      width: double.infinity,
      height: 48,
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
            onTap: () => _later('Upload files'),
            borderRadius: BorderRadius.circular(15),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.file_upload_outlined, color: Colors.white, size: 19),
                SizedBox(width: 9),
                Text(
                  'Upload files',
                  style: TextStyle(
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
    final busy = _importingExcel || _creatingFolder;
    return SingleChildScrollView(
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
        onChanged: (value) => setState(() => _query = value),
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
                    setState(() => _query = '');
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
                message: i == 0
                    ? 'Personal Drive'
                    : 'This tab will be designed in a later step',
                child: Container(
                  alignment: Alignment.center,
                  decoration: i == 0
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
                        color: i == 0 ? _p.link : _p.muted,
                        fontWeight:
                            i == 0 ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 10.5,
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

  Widget _fileHeading() {
    return Row(
      children: [
        Text(
          'FILES',
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
  }) {
    return IconButton(
      key: ValueKey('drive-action-$label'),
      onPressed: onPressed,
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
      padding: EdgeInsets.zero,
      iconSize: 17,
      color: destructive ? Theme.of(context).colorScheme.error
          : _p.previewText,
      icon: Icon(icon),
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
    final canMove = access == 'OWNER';
    final canDelete = access == 'OWNER';
    final file = _file(item);
    final bytes = file['sizeBytes'] is num
        ? (file['sizeBytes'] as num).toInt()
        : null;
    final tint = folder
        ? const Color(0xFF8A6DFA)
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
                  _typeLabel(item),
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
          Row(
            children: [
              Icon(Icons.schedule_outlined, color: _p.muted, size: 13),
              const SizedBox(width: 5),
              Flexible(
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
              const Spacer(),
              if (!folder)
                _cardAction(Icons.download_outlined, 'Download',
                    busy ? null : () => _download(item)),
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
            TextButton(onPressed: _loadPersonalDrive, child: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;

    return Scaffold(
      backgroundColor: _p.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPersonalDrive,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 24),
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
              _folderPath(),
              _fileHeading(),
              const SizedBox(height: 7),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _messagePanel(Icons.cloud_off_outlined, _error!, retry: true)
              else if (visible.isEmpty)
                _messagePanel(
                  Icons.folder_open_outlined,
                  _query.isEmpty
                      ? 'No files or folders in Personal yet'
                      : 'No files or folders match your search',
                )
              else
                ...visible.map(_fileCard),
              if (!_loading && _error == null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${visible.length} ${visible.length == 1 ? 'item' : 'items'} · ${_sizeLabel(_usedBytes)} in Personal',
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
    );
  }
}
,
              caseSensitive: false), '')}.xlsx'
          : baseName;
      final saved = await DriveDownload.save(bytes, filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Saved: ${saved.path}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () { OpenFilex.open(saved.path); },
          ),
        ));
    } catch (error) {
      _feedback(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Widget _folderPath() {
    if (_activeParent == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          TextButton(
            onPressed: () => _openFolder(null),
            child: const Text('Personal'),
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
    return SizedBox(
      width: double.infinity,
      height: 48,
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
            onTap: () => _later('Upload files'),
            borderRadius: BorderRadius.circular(15),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.file_upload_outlined, color: Colors.white, size: 19),
                SizedBox(width: 9),
                Text(
                  'Upload files',
                  style: TextStyle(
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
    final busy = _importingExcel || _creatingFolder;
    return SingleChildScrollView(
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
        onChanged: (value) => setState(() => _query = value),
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
                    setState(() => _query = '');
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
                message: i == 0
                    ? 'Personal Drive'
                    : 'This tab will be designed in a later step',
                child: Container(
                  alignment: Alignment.center,
                  decoration: i == 0
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
                        color: i == 0 ? _p.link : _p.muted,
                        fontWeight:
                            i == 0 ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 10.5,
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

  Widget _fileHeading() {
    return Row(
      children: [
        Text(
          'FILES',
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

  Widget _cardAction(IconData icon, String label, {bool destructive = false}) {
    return IconButton(
      onPressed: () => _later(label),
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
      padding: EdgeInsets.zero,
      iconSize: 17,
      color: destructive ? _p.muted : _p.previewText,
      icon: Icon(icon),
    );
  }

  Widget _fileCard(Map<String, dynamic> item) {
    final folder = _isFolder(item);
    final sheet = _isSheet(item);
    final ownerName = _ownerName(item);
    final file = _file(item);
    final bytes = file['sizeBytes'] is num
        ? (file['sizeBytes'] as num).toInt()
        : null;
    final tint = folder
        ? const Color(0xFF8A6DFA)
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
          Row(
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
                  _typeLabel(item),
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
              Flexible(
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
              const Spacer(),
              _cardAction(Icons.download_outlined, 'Download'),
              _cardAction(Icons.edit_outlined, 'Rename'),
              _cardAction(Icons.share_outlined, 'Share'),
              _cardAction(Icons.arrow_forward_rounded,
                  folder ? 'Open folder' : 'Open'),
              _cardAction(Icons.delete_outline_rounded, 'Delete',
                  destructive: true),
            ],
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
            TextButton(onPressed: _loadPersonalDrive, child: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;

    return Scaffold(
      backgroundColor: _p.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPersonalDrive,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 24),
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
              _fileHeading(),
              const SizedBox(height: 7),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _messagePanel(Icons.cloud_off_outlined, _error!, retry: true)
              else if (visible.isEmpty)
                _messagePanel(
                  Icons.folder_open_outlined,
                  _query.isEmpty
                      ? 'No files or folders in Personal yet'
                      : 'No files or folders match your search',
                )
              else
                ...visible.map(_fileCard),
              if (!_loading && _error == null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${visible.length} ${visible.length == 1 ? 'item' : 'items'} · ${_sizeLabel(_usedBytes)} in Personal',
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
    );
  }
}
