import 'package:dio/dio.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../features/chat/data/chat_service.dart';
import '../features/auth/data/auth_service.dart';
import '../core/network/api_client.dart';

// Stitch-inspired messages list. The chat detail, dialog, and networking stay unchanged.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  // All Messages colors now come from the app-wide ThemeExtension.
  AppPalette get _palette => Theme.of(context).extension<AppPalette>()!;
  Color get _ink => _palette.ink;
  Color get _muted => _palette.muted;
  Color get _page => _palette.page;
  Color get _surface => _palette.panel;
  Color get _card => _palette.card;
  Color get _cardBorder => _palette.cardBorder;
  Color get _searchBackground => _palette.searchBackground;
  Color get _secondaryText => _palette.secondaryText;
  Color get _previewText => _palette.previewText;
  Color get _hintColor => _palette.hintText;
  Color get _searchIconColor => _palette.searchIcon;
  Color get _linkColor => _palette.link;
  Color get _cardShadow => _palette.cardShadow;
  Color get _surfaceShadow => _palette.panelShadow;
  static const Color _blue = AppColors.primary;

  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<dynamic> _chats = [];
  String? _errorMessage;
  String? _currentUserId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Preserve the existing user/conversation API and its ordering.
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileResponse = await ApiClient().dio.get('/auth/me');
      if (profileResponse.statusCode == 200 &&
          profileResponse.data['success'] == true) {
        _currentUserId = profileResponse.data['data']['id'];
      }
      final chats = await _chatService.getConversations();
      if (!mounted) return;
      setState(() {
        _chats = chats;
      });
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

  void _showNewConversationDialog() {
    showDialog(
      context: context,
      builder: (context) => const NewConversationDialog(),
    ).then((created) {
      if (created == true && mounted) {
        _loadData();
      }
    });
  }

  dynamic _otherUser(dynamic conversation) {
    if (conversation['type'] != 'DIRECT') return null;
    final members = conversation['members'];
    if (members is! List) return null;
    for (final member in members) {
      if (member is Map &&
          member['user'] is Map &&
          member['userId'] != _currentUserId) {
        return member['user'];
      }
    }
    return null;
  }

  String _conversationName(dynamic conversation) {
    String name = (conversation['name'] ??
            conversation['title'] ??
            'კორპორატიული ჩათი')
        .toString();
    final user = _otherUser(conversation);
    if (user != null) {
      name = (user['displayName'] ?? user['email'] ?? 'პირადი ჩათი')
          .toString();
    }
    return name;
  }

  dynamic _lastMessage(dynamic conversation) {
    final supplied = conversation['lastMessage'];
    if (supplied is Map) return supplied;
    final messages = conversation['messages'];
    // The API returns newest first (one item). Do not reverse its order.
    if (messages is List && messages.isNotEmpty && messages.first is Map) {
      return messages.first;
    }
    return null;
  }

  String _conversationPreview(dynamic conversation) {
    final message = _lastMessage(conversation);
    if (message == null) return 'Start a conversation →';
    final content = (message['content'] ?? '').toString();
    return content.trim().isEmpty ? 'Attachment' : content;
  }

  String _dateLabel(dynamic conversation) {
    final value = _lastMessage(conversation)?['createdAt'] ??
        conversation['updatedAt'];
    if (value is! String) return '';
    final timestamp = DateTime.tryParse(value)?.toLocal();
    if (timestamp == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) {
      final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      return hour.toString() +
          ':' +
          minute +
          (timestamp.hour >= 12 ? ' PM' : ' AM');
    }
    if (difference == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = months[timestamp.month - 1] +
        ' ' +
        timestamp.day.toString();
    return timestamp.year == now.year
        ? label
        : label + ', ' + timestamp.year.toString();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  List<Color> _avatarColors(String seed) {
    const palette = [
      [Color(0xFF6688FA), Color(0xFF365BEF)],
      [Color(0xFFC85CF5), Color(0xFF8735E7)],
      [Color(0xFF32CFB1), Color(0xFF0EB49E)],
      [Color(0xFF718096), Color(0xFF414F64)],
      [Color(0xFF9DACE7), Color(0xFF778AD8)],
      [Color(0xFFF1A66B), Color(0xFFE57861)],
    ];
    final index = seed.codeUnits.fold<int>(0, (sum, code) => sum + code) %
        palette.length;
    return palette[index];
  }

  bool _recentlyActive(dynamic conversation) {
    final user = _otherUser(conversation);
    final value = user == null ? null : user['lastSeenAt'];
    if (value is! String) return false;
    final seen = DateTime.tryParse(value);
    if (seen == null) return false;
    final age = DateTime.now().difference(seen);
    return !age.isNegative && age.inMinutes < 5;
  }

  int _unreadCount(dynamic conversation) {
    final value = conversation['unreadCount'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<dynamic> get _visibleChats {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _chats;
    return _chats.where((chat) {
      return _conversationName(chat).toLowerCase().contains(query) ||
          _conversationPreview(chat).toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.85,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _chats.length.toString() + ' active conversations',
                  style: TextStyle(
                    color: _secondaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showNewConversationDialog,
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(alpha: 0.21),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'New conversation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _searchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: TextStyle(
          color: _ink,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Find a conversation',
          hintStyle: TextStyle(
            color: _hintColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: _searchIconColor,
          ),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildConversationCard(dynamic chat) {
    final name = _conversationName(chat);
    final preview = _conversationPreview(chat);
    final hasMessages = _lastMessage(chat) != null;
    final colors = _avatarColors(name);
    final unread = _unreadCount(chat);
    final active = _recentlyActive(chat);
    final conversationId = (chat['id'] ?? '').toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatDetailScreen(
                conversationId: conversationId,
                chatName: name,
              ),
            ),
          ).then((_) {
            if (mounted) _loadData();
          });
        },
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: _cardShadow,
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: colors.last.withValues(alpha: 0.13),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (active)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        height: 11,
                        width: 11,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: _card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink,
                              fontSize: 12.5,
                              fontWeight:
                                  unread > 0 ? FontWeight.w800 : FontWeight.w700,
                              letterSpacing: -0.17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _dateLabel(chat),
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasMessages
                                  ? _previewText
                                  : _linkColor,
                              fontSize: 11,
                              fontWeight: hasMessages
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 19),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : unread.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: _muted, size: 30),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB83C52)),
              ),
              TextButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final visible = _visibleChats;
    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadData,
      child: visible.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                Center(
                  child: Text(
                    _query.isNotEmpty
                        ? 'No matching conversations'
                        : 'No conversations yet',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 2, bottom: 15),
              itemCount: visible.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 9),
              itemBuilder: (context, index) =>
                  _buildConversationCard(visible[index]),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            _buildSectionHeader(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                padding: const EdgeInsets.fromLTRB(13, 14, 13, 0),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: _surfaceShadow,
                      blurRadius: 22,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildSearchField(),
                    const SizedBox(height: 15),
                    Expanded(child: _buildConversationList()),
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

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String chatName;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();

  bool _isLoading = true;
  bool _isUploadingFile = false;
  List<dynamic> _messages = [];
  String? _currentUserId;

  String? _replyingToMessageId;
  String? _replyingToContent;
  String? _replyingToSenderName;
  String? _editingMessageId;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      final profile = await AuthService().checkSession()
          ? await _getProfileId()
          : null;
      final messages = await _chatService.getMessages(widget.conversationId);

      setState(() {
        _currentUserId = profile;
        _messages = messages;
        _isLoading = false;
      });

      _chatService.joinConversation(widget.conversationId);

      _chatService.initSocket((incomingMessage) {
        final msgConvId =
            incomingMessage['conversationId'] ??
            incomingMessage['conversation']?['id'];
        if (msgConvId == null || msgConvId == widget.conversationId) {
          setState(() {
            final index = _messages.indexWhere(
              (m) => m['id'] == incomingMessage['id'],
            );
            if (index != -1) {
              final oldMsg = _messages[index];
              _messages[index] = {
                ...oldMsg,
                ...incomingMessage,
                'content': incomingMessage['content'] ?? '',
                'senderId': incomingMessage['senderId'] ?? oldMsg['senderId'],
                'sender': incomingMessage['sender'] ?? oldMsg['sender'],
              };
            } else {
              _messages.add(incomingMessage);
            }
          });
        }
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getProfileId() async {
    try {
      final response = await ApiClient().dio.get('/auth/me');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['id'];
      }
    } catch (_) {}
    return null;
  }

  // 🔹 ფაილის არჩევა, ატვირთვა და მესიჯად გაგზავნა
  Future<void> _pickAndSendFile() async {
    try {
      // 1. ფაილის არჩევა
      const XTypeGroup fileTypes = XTypeGroup(
        label: 'Files',
        extensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'txt'],
      );

      final XFile? file = await openFile(acceptedTypeGroups: [fileTypes]);

      // მომხმარებელმა არჩევა გააუქმა
      if (file == null || !mounted) return;

      setState(() => _isUploadingFile = true);

      // 2. ფაილის ატვირთვა სერვერზე
      final String? fileId = await _chatService.uploadFile(
        file.path,
        file.name,
      );

      // 3. შეტყობინების გაგზავნა
      if (fileId != null) {
        await _chatService.sendMessageHttp(
          widget.conversationId,
          '',
          attachmentIds: [fileId],
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingFile = false);
      }
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessageId != null) {
      final messageId = _editingMessageId!;
      _messageController.clear();
      setState(() {
        _editingMessageId = null;
      });

      try {
        await _chatService.editMessage(messageId, text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    final replyingTo = _replyingToMessageId;
    _messageController.clear();
    setState(() {
      _replyingToMessageId = null;
      _replyingToContent = null;
      _replyingToSenderName = null;
    });

    try {
      await _chatService.sendMessageHttp(
        widget.conversationId,
        text,
        replyToMessageId: replyingTo,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteMessage(String messageId) async {
    setState(() {
      final index = _messages.indexWhere((m) => m['id'] == messageId);
      if (index != -1) {
        _messages[index] = {
          ..._messages[index],
          'content': '', // ოპტიმისტური წაშლა UI-სთვის
        };
      }
    });

    try {
      await _chatService.deleteMessage(messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showActionModal(Map<dynamic, dynamic> rawMessage) {
    FocusScope.of(context).unfocus();

    final message = Map<String, dynamic>.from(rawMessage);
    final messageId = message['id'] ?? '';
    final content = message['content'] ?? '';
    final senderId = message['senderId'] ?? message['sender']?['id'];
    final isMe = _currentUserId != null && senderId == _currentUserId;

    String senderName = 'მომხმარებელი';
    final senderObj = message['sender'];
    if (senderObj != null) {
      final fName = senderObj['firstName'] ?? '';
      final lName = senderObj['lastName'] ?? '';
      final combined = '$fName $lName'.trim();
      if (combined.isNotEmpty) {
        senderName = combined;
      } else {
        senderName =
            senderObj['displayName'] ?? senderObj['email'] ?? 'მომხმარებელი';
      }
    } else if (message['senderName'] != null) {
      senderName = message['senderName'];
    }

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['👍', '❤️', '🔥', '👏', '😂', '🎉'].map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: () async {
                          Navigator.pop(context);
                          setState(() {
                            final msgIndex = _messages.indexWhere(
                              (m) => m['id'] == messageId,
                            );
                            if (msgIndex != -1) {
                              List reactions = List.from(
                                _messages[msgIndex]['reactions'] ?? [],
                              );
                              reactions.add({
                                'emoji': emoji,
                                'userId': _currentUserId,
                              });
                              _messages[msgIndex] = {
                                ..._messages[msgIndex],
                                'reactions': reactions,
                              };
                            }
                          });
                          try {
                            await _chatService.addReaction(messageId, emoji);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(color: Colors.white24, height: 16),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.reply,
                      color: Colors.white,
                      size: 20,
                    ),
                    title: const Text(
                      'პასუხის გაცემა (Reply)',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _replyingToMessageId = messageId;
                        _replyingToContent = content;
                        _replyingToSenderName = isMe ? 'თქვენ' : senderName;
                      });
                    },
                  ),
                  if (isMe) ...[
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.edit,
                        color: Colors.blueAccent,
                        size: 20,
                      ),
                      title: const Text(
                        'შეცვლა (Edit)',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _editingMessageId = messageId;
                          _messageController.text = content;
                          _replyingToMessageId = null;
                        });
                      },
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      title: const Text(
                        'წაშლა (Delete)',
                        style: TextStyle(color: Colors.redAccent, fontSize: 14),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _deleteMessage(messageId);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _chatService.disposeSocket();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chatName)),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? const Center(child: Text('დაიწყეთ საუბარი...'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final reversedIndex = _messages.length - 1 - index;
                          final msg = _messages[reversedIndex];

                          final content = msg['content'] ?? '';
                          final List attachments = msg['attachments'] ?? [];

                          // 🔹 მესიჯი ითვლება წაშლილად მხოლოდ მაშინ, როცა კონტენტიც ცარიელია და ატაჩმენტიც არ აქვს
                          final bool isDeleted =
                              content.isEmpty && attachments.isEmpty;

                          final senderId =
                              msg['senderId'] ?? msg['sender']?['id'];
                          final isMe =
                              _currentUserId != null &&
                              senderId == _currentUserId;

                          if (isDeleted) {
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.block,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ეს შეტყობინება წაიშალა',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          String senderName = 'მომხმარებელი';
                          final sObj = msg['sender'];
                          if (sObj != null) {
                            final fN = sObj['firstName'] ?? '';
                            final lN = sObj['lastName'] ?? '';
                            final comb = '$fN $lN'.trim();
                            if (comb.isNotEmpty) {
                              senderName = comb;
                            } else {
                              senderName =
                                  sObj['displayName'] ??
                                  sObj['email'] ??
                                  'მომხმარებელი';
                            }
                          } else if (msg['senderName'] != null) {
                            senderName = msg['senderName'];
                          }

                          dynamic repliedMessage;
                          String repliedSenderName = 'მომხმარებელი';
                          if (msg['replyToMessageId'] != null) {
                            try {
                              repliedMessage = _messages.firstWhere(
                                (m) => m['id'] == msg['replyToMessageId'],
                              );
                              if (repliedMessage != null) {
                                final repSenderObj = repliedMessage['sender'];
                                if (repSenderObj != null) {
                                  final fName = repSenderObj['firstName'] ?? '';
                                  final lName = repSenderObj['lastName'] ?? '';
                                  final combined = '$fName $lName'.trim();
                                  if (combined.isNotEmpty) {
                                    repliedSenderName = combined;
                                  } else {
                                    repliedSenderName =
                                        repSenderObj['displayName'] ??
                                        repSenderObj['email'] ??
                                        'მომხმარებელი';
                                  }
                                } else if (repliedMessage['senderName'] !=
                                    null) {
                                  repliedSenderName =
                                      repliedMessage['senderName'];
                                }
                              }
                            } catch (_) {
                              repliedMessage = null;
                            }
                          }

                          final timeStr = _formatTime(msg['createdAt']);
                          final headerText = isMe
                              ? 'თქვენ · $timeStr'
                              : '$senderName · $timeStr';

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 2,
                                    left: 4,
                                    right: 4,
                                  ),
                                  child: Text(
                                    headerText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),

                                GestureDetector(
                                  onLongPress: () => _showActionModal(msg),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.75,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade800,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(
                                          isMe ? 16 : 4,
                                        ),
                                        bottomRight: Radius.circular(
                                          isMe ? 4 : 16,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (repliedMessage != null)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.2,
                                              ),
                                              border: const Border(
                                                left: BorderSide(
                                                  color: Colors.white70,
                                                  width: 3,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  repliedSenderName,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  repliedMessage['content'] ??
                                                      '',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        if (content.isNotEmpty)
                                          Text(
                                            content,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                            ),
                                          ),

                                        // 🔹 ატაჩმენტების (ფაილების) რენდერი
                                        if (attachments.isNotEmpty) ...[
                                          if (content.isNotEmpty)
                                            const SizedBox(height: 6),
                                          ...attachments.map((att) {
                                            // 🔹 სახელი ზუსტად ვიღებთ შიდა file ობიექტიდან ან ძველი გზებით
                                            final fileObj = att['file'] is Map
                                                ? att['file']
                                                : null;
                                            final fileName =
                                                fileObj?['originalName'] ??
                                                fileObj?['name'] ??
                                                att['originalName'] ??
                                                att['name'] ??
                                                'ფაილი';

                                            final rawSize =
                                                fileObj?['sizeBytes'] ??
                                                att['size'];
                                            final fileSize = rawSize != null
                                                ? '${(rawSize / 1024).toStringAsFixed(0)} KB'
                                                : '';

                                            // 🔹 ფაილის ID დაუნლოუდისთვის
                                            final fileId =
                                                fileObj?['id'] ??
                                                att['fileId'] ??
                                                att['id'] ??
                                                '';

                                            return Container(
                                              margin: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.insert_drive_file,
                                                    color: Colors.blue,
                                                    size: 28,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          fileName,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .black87,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        if (fileSize.isNotEmpty)
                                                          Text(
                                                            fileSize,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                  fontSize: 11,
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.download,
                                                      color: Colors.blue,
                                                      size: 20,
                                                    ),
                                                    onPressed: () async {
                                                      if (fileId.isEmpty) {
                                                        return;
                                                      }
                                                      try {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'მიმდინარეობს ფაილის გადმოწერა...',
                                                            ),
                                                          ),
                                                        );

                                                        // 1. ბაიტების წამოღება სერვერიდან ავტორიზაციით
                                                        final response =
                                                            await ApiClient().dio.get(
                                                              '/files/$fileId/download',
                                                              options: Options(
                                                                responseType:
                                                                    ResponseType
                                                                        .bytes,
                                                              ),
                                                            );

                                                        // 2. საჯარო Downloads საქაღალდის აღება ანდროიდისთვის
                                                        Directory? directory;
                                                        if (Platform
                                                            .isAndroid) {
                                                          directory = Directory(
                                                            '/storage/emulated/0/Download',
                                                          );
                                                          if (!await directory
                                                              .exists()) {
                                                            directory =
                                                                await getExternalStorageDirectory();
                                                          }
                                                        } else {
                                                          directory =
                                                              await getApplicationDocumentsDirectory();
                                                        }

                                                        final savedFile = File(
                                                          '${directory?.path}/$fileName',
                                                        );

                                                        // 3. ფაილის ფიზიკური ჩაწერა საჯარო სივრცეში
                                                        await savedFile
                                                            .writeAsBytes(
                                                              response.data,
                                                            );

                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).hideCurrentSnackBar();
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'ფაილი ჩამოიტვირთა: Downloads/$fileName',
                                                              ),
                                                              backgroundColor:
                                                                  Colors.green,
                                                            ),
                                                          );
                                                        }

                                                        // 4. ფაილის ავტომატურად გახსნა მომხმარებლისთვის
                                                        // (საჭიროა import 'package:open_filex/open_filex.dart';)
                                                        await OpenFilex.open(
                                                          savedFile.path,
                                                        );
                                                      } catch (e) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).hideCurrentSnackBar();
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'ჩამოტვირთვის შეცდომა: $e',
                                                              ),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),

                                if (msg['reactions'] != null &&
                                    (msg['reactions'] as List).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Wrap(
                                      spacing: 4,
                                      children: (msg['reactions'] as List).map((
                                        r,
                                      ) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            r['emoji'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              if (_editingMessageId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: Colors.blueGrey.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit,
                        size: 20,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'შეტყობინების რედაქტირება',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            _editingMessageId = null;
                            _messageController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),

              if (_replyingToMessageId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 20, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'პასუხი: $_replyingToSenderName',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              _replyingToContent ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            _replyingToMessageId = null;
                            _replyingToContent = null;
                            _replyingToSenderName = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // ტექსტური ველი და მიმაგრების (Attach) ღილაკი
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    IconButton(
                      icon: _isUploadingFile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file, color: Colors.grey),
                      onPressed: _isUploadingFile ? null : _pickAndSendFile,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'შეცვალეთ შეტყობინება...'
                              : 'დაწერეთ შეტყობინება...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _editingMessageId != null ? Icons.check : Icons.send,
                        color: Colors.blue,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewConversationDialog extends StatefulWidget {
  const NewConversationDialog({super.key});

  @override
  State<NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<NewConversationDialog> {
  final ChatService _chatService = ChatService();
  final TextEditingController _groupNameController = TextEditingController();

  bool _isGroup = false;
  bool _isLoadingUsers = true;
  bool _isSubmitting = false;
  List<dynamic> _users = [];

  String? _selectedUserId;
  final List<String> _selectedUserIds = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _chatService.getUsers();
      setState(() {
        _users = users;
        _isLoadingUsers = false;
      });
    } catch (_) {
      setState(() => _isLoadingUsers = false);
    }
  }

  void _startConversation() async {
    if (_isGroup) {
      if (_groupNameController.text.trim().isEmpty ||
          _selectedUserIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('გთხოვთ მიუთითოთ ჯგუფის სახელი და აირჩიოთ წევრები'),
          ),
        );
        return;
      }
    } else {
      if (_selectedUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('გთხოვთ აირჩიოთ თანამშრომელი')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      // ვირჩევთ სწორ მონაწილეებს
      final participants = _isGroup ? _selectedUserIds : [_selectedUserId!];

      // თუ პირადი ჩატია, სახელს ვპოულობთ არჩეული მომხმარებლის სახელიდან
      String? chatTitle = _isGroup ? _groupNameController.text.trim() : null;
      if (!_isGroup) {
        final selectedUser = _users.firstWhere(
          (u) => u['id'] == _selectedUserId,
          orElse: () => null,
        );
        if (selectedUser != null) {
          chatTitle =
              '${selectedUser['firstName'] ?? ''} ${selectedUser['lastName'] ?? ''}'
                  .trim();
          if (chatTitle.isEmpty) chatTitle = selectedUser['email'];
        }
      }

      final conversationData = await _chatService.createConversation(
        isGroup: _isGroup,
        title: _isGroup ? _groupNameController.text.trim() : null,
        memberIds: participants,
      );

      if (conversationData != null && mounted) {
        final conversationId = conversationData['id'];
        final resolvedTitle =
            conversationData['title'] ?? chatTitle ?? 'კორპორატიული ჩათი';

        // ვხურავთ დიალოგს და ვაბრუნებთ true-ს
        Navigator.pop(context, true);

        // პირდაპირ ვხსნით ახლადშექმნილი ჩატის ეკრანს
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              chatName: resolvedTitle,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('New conversation', style: TextStyle(fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Direct')),
                    ButtonSegment<bool>(value: true, label: Text('Group')),
                  ],
                  selected: {_isGroup},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _isGroup = newSelection.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
              if (_isGroup) ...[
                const Text(
                  'Group name',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _groupNameController,
                  decoration: const InputDecoration(
                    hintText: 'შეიყვანეთ სახელი',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                _isGroup ? 'Members' : 'Person',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              _isLoadingUsers
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _isGroup
                  ? Container(
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final userId = user['id'];
                          final name =
                              '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'
                                  .trim();
                          final isSelected = _selectedUserIds.contains(userId);

                          return CheckboxListTile(
                            title: Text(
                              name.isEmpty ? user['email'] : name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedUserIds.add(userId);
                                } else {
                                  _selectedUserIds.remove(userId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _selectedUserId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Choose a colleague',
                      ),
                      items: _users.map<DropdownMenuItem<String>>((user) {
                        final name =
                            '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'
                                .trim();
                        return DropdownMenuItem<String>(
                          value: user['id'],
                          child: Text(
                            name.isEmpty ? user['email'] : name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedUserId = val;
                        });
                      },
                    ),
              if (_isGroup) ...[const SizedBox(height: 6)],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _isSubmitting ? null : _startConversation,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Start conversation'),
        ),
      ],
    );
  }
}
