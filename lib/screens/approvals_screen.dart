import 'package:flutter/material.dart';
import '../features/approvals/data/approval_service.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.focusRequestId});

  /// Optional request ID supplied by the notification deep link.
  final String? focusRequestId;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final ApprovalService _approvalService = ApprovalService();
  
  bool _isLoading = true;
  List<dynamic> _requests = [];
  String? _errorMessage;
  bool _focusedOpened = false;

  @override
  void initState() {
    super.initState();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _approvalService.getApprovalRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
      });
      if (widget.focusRequestId != null && !_focusedOpened) {
        for (final request in requests) {
          if (request is Map && request['id']?.toString() == widget.focusRequestId) {
            _focusedOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showFocusedRequest(request);
            });
            break;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showFocusedRequest(dynamic request) {
    final steps = request['steps'] is List ? request['steps'] as List : <dynamic>[];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text((request['title'] ?? 'მოთხოვნა').toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('სტატუსი: ${request['status'] ?? '-'}'),
              const SizedBox(height: 12),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${step is Map ? (step['name'] ?? 'Step') : 'Step'}: '
                    '${step is Map ? (step['status'] ?? '-') : '-'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('დახურვა'),
          ),
        ],
      ),
    );
  }

  void _handleActionDialog(String requestId, String title) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('განხილვა: $title'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            labelText: 'კომენტარი (არასავალდებულო)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('გაუქმება'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _submitAction(requestId, 'REJECT', commentController.text);
            },
            child: const Text('უარყოფა'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitAction(requestId, 'APPROVE', commentController.text);
            },
            child: const Text('დამტკიცება'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAction(String requestId, String action, String comment) async {
    try {
      await _approvalService.performAction(
        requestId: requestId,
        action: action,
        comment: comment.isEmpty ? null : comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ოპერაცია წარმატებით შესრულდა')),
        );
        _fetchApprovals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('მოთხოვნები')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : _requests.isEmpty
                  ? const Center(child: Text('მოთხოვნები არ მოიძებნა'))
                  : RefreshIndicator(
                      onRefresh: _fetchApprovals,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final req = _requests[index];
                          final requestId = req['id'] ?? '';
                          final title = req['title'] ?? 'მოთხოვნა';
                          final status = req['status'] ?? 'PENDING';

                          return Card(
                            child: ListTile(
                              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('სტატუსი: $status\nტიპი: ${req['type'] ?? 'სხვა'}'),
                              isThreeLine: true,
                              trailing: FilledButton.tonalIcon(
                                onPressed: () => _handleActionDialog(requestId, title),
                                icon: const Icon(Icons.rate_review, size: 16),
                                label: const Text('განხილვა'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ახალი მოთხოვნის შექმნის ფორმა მალე დაემატება')),
          );
        },
        child: const Icon(Icons.post_add),
      ),
    );
  }
}