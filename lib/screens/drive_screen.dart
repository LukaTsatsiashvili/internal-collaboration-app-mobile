import 'package:flutter/material.dart';
import '../features/drive/data/drive_service.dart';
import '../core/theme/app_dropdown_theme.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  final DriveService _driveService = DriveService();
  
  bool _isLoading = true;
  List<dynamic> _driveItems = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDriveData();
  }

  Future<void> _fetchDriveData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _driveService.getDriveItems();
      setState(() {
        _driveItems = items;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('კორპორატიული Drive'),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'ჩემი'),
              Tab(text: 'გაზიარებული'),
              Tab(text: 'ნაგავი'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Mine Tab
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                    : _driveItems.isEmpty
                        ? const Center(child: Text('ფაილები არ მოიძებნა'))
                        : RefreshIndicator(
                            onRefresh: _fetchDriveData,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _driveItems.length,
                              itemBuilder: (context, index) {
                                final item = _driveItems[index];
                                final isFolder = item['type'] == 'folder';
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      isFolder ? Icons.folder : Icons.insert_drive_file,
                                      color: isFolder ? Colors.amber : Colors.blue,
                                    ),
                                    title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('ზომა: ${item['size'] ?? '--'}  •  ${item['date'] ?? ''}'),
                                    trailing: AppDropdownTheme(
                                      child: PopupMenuButton<String>(
                                      position: PopupMenuPosition.under,
                                      offset: AppDropdownTheme.menuGap,
                                      onSelected: (value) {},
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'download', child: Text('გადმოწერა')),
                                        const PopupMenuItem(value: 'share', child: Text('გაზიარება')),
                                        const PopupMenuItem(value: 'delete', child: Text('წაშლა', style: TextStyle(color: Colors.red))),
                                      ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
            // Shared Tab
            const Center(child: Text('სხვა მომხმარებლების მიერ გაზიარებული ფაილები')),
            // Trash Tab
            const Center(child: Text('წაშლილი ფაილები (Trash)')),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ფაილების ატვირთვის ფუნქციონალი მალე დაემატება')),
            );
          },
          icon: const Icon(Icons.upload_file),
          label: const Text('ატვირთვა'),
        ),
      ),
    );
  }
}