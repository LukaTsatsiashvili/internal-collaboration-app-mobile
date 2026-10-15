import 'package:flutter/material.dart';
import '../features/dashboard/data/dashboard_service.dart';
import 'main_navigation.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final String currentLanguage;
  final ThemeMode currentThemeMode;

  const DashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.currentLanguage,
    required this.currentThemeMode,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();

  bool _isLoading = true;
  String _userName = 'მომხმარებელი';
  String _activeTasksCount = '...';
  String _pendingApprovalsCount = '...';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _dashboardService.getUserProfile();
      final metrics = await _dashboardService.getDashboardMetrics();

      if (mounted) {
        setState(() {
          if (profile != null) {
            _userName = profile['firstName'] ?? profile['name'] ?? profile['email'] ?? 'მომხმარებელი';
          }
          _activeTasksCount = metrics['activeTasks'] ?? '0';
          _pendingApprovalsCount = metrics['pendingApprovals'] ?? '0';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('სამუშაო სივრცე'),
        actions: buildGlobalActions(
          context,
          widget.onToggleTheme,
          widget.onChangeLanguage,
          widget.currentLanguage,
          widget.currentThemeMode,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'მოგესალმებით, $_userName!',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'აქტიური დავალებები',
                          _activeTasksCount,
                          Icons.task,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          'მოლოდინში დამტკიცება',
                          _pendingApprovalsCount,
                          Icons.pending_actions,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 24),
            const Text('სწრაფი ქმედებები', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildActionButton(context, Icons.add_task, 'ახალი დავალება', () {}),
                  const SizedBox(width: 12),
                  _buildActionButton(context, Icons.post_add, 'მოთხოვნის შექმნა', () {}),
                  const SizedBox(width: 12),
                  _buildActionButton(context, Icons.group_add, 'ჯგუფის შექმნა', () {}),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('სისტემური სტატუსი', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildActivityItem('ბექენდ სერვერთან კავშირი', 'აქტიური (Online)', Colors.green),
            _buildActivityItem('რეალურ დროში სოკეტები', 'დაკავშირებულია', Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String subtitle, Color indicatorColor) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: indicatorColor.withValues(alpha: 0.2),
        child: Icon(Icons.circle, size: 12, color: indicatorColor),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      contentPadding: EdgeInsets.zero,
    );
  }
}