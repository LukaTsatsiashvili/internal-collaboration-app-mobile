import 'package:flutter/material.dart';
import '../core/theme/app_theme_extensions.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('შეტყობინებები'),
        actions: [
          TextButton(onPressed: () {}, child: const Text('ყველას წაკითხვა')),
        ],
      ),
      body: ListView(
        children: [
          _buildNotificationItem(
            icon: Icons.task_alt,
            color: Colors.green,
            title: 'დავალება განახლდა',
            description: 'გიორგიმ შეცვალა დავალების სტატუსი: API სერვისის ოპტიმიზაცია.',
            time: '15 წუთის წინ',
            isRead: false,
            context: context,
          ),
          _buildNotificationItem(
            icon: Icons.approval,
            color: Colors.blue,
            title: 'ახალი დამტკიცების ნაბიჯი',
            description: 'თქვენ გევალებათ აღჭურვილობის შეძენის მოთხოვნის განხილვა.',
            time: '2 საათის წინ',
            isRead: false,
            context: context,
          ),
          _buildNotificationItem(
            icon: Icons.chat,
            color: Colors.orange,
            title: 'ახალი მითითება (Mention)',
            description: 'ნინომ დაგგაკოთ არხში: #IT დეპარტამენტი.',
            time: 'გუშინ',
            isRead: true,
            context: context,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String time,
    required bool isRead,
    required BuildContext context,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      color: isRead ? Colors.transparent : palette.unreadBackground,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(description),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontSize: 10, color: palette.muted)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}