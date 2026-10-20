import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import '../features/drive/data/drive_service.dart';

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
  int _usedBytes = 0;
  int _loadVersion = 0;

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
      final listing = await _driveService.getPersonalListing();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _items = listing.items;
        _usedBytes = listing.usedBytes;
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

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Drive',
            style: TextStyle(
              color: _p.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.8,
            ),
          ),
        ),
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: _p.card,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.notifications_none_rounded,
              size: 19, color: _p.secondaryText),
        ),
        const SizedBox(width: 7),
        Container(
          width: 37,
          height: 37,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
          ),
          child: const Icon(Icons.hub_rounded, color: Colors.white, size: 19),
        ),
      ],
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

  Widget _quickButton(String label, IconData icon, Color accent, double width) {
    return SizedBox(
      width: width,
      height: 43,
      child: Material(
        color: _p.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _later(label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _p.cardBorder),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _quickButton('Import Excel', Icons.file_download_outlined,
              AppColors.primary, 122),
          const SizedBox(width: 8),
          _quickButton('New Spreadsheet', Icons.table_chart_outlined,
              const Color(0xFF14AD86), 151),
          const SizedBox(width: 8),
          _quickButton('New Folder', Icons.create_new_folder_outlined,
              const Color(0xFF7E68F5), 123),
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
                    '${visible.length} items · ${_sizeLabel(_usedBytes)} in Personal',
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
