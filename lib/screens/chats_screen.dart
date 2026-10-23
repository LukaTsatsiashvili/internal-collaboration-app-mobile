import 'dart:async';
import 'package:dio/dio.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../features/chat/data/chat_service.dart';
import '../core/network/api_client.dart';
import '../core/widgets/load_error_state.dart';

// Stitch-inspired messages list. The chat detail, dialog, and networking stay unchanged.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.openCreateOnStart = false,
    this.service,
    this.loadCurrentUserId,
  });

  /// Dashboard quick action opens the existing conversation dialog.
  final bool openCreateOnStart;
  /// Testable source; regular screens use the standard authenticated service.
  final ChatService? service;
  final Future<String?> Function()? loadCurrentUserId;

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

  late final ChatService _chatService;
  int _loadVersion = 0;
  Timer? _liveReloadTimer;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<dynamic> _chats = [];
  String? _errorMessage;
  String? _currentUserId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _chatService = widget.service ?? ChatService();
    _loadData();
    if (widget.service == null) {
      _chatService.watchConversations(_scheduleLiveReload);
    }
    if (widget.openCreateOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNewConversationDialog();
      });
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    _liveReloadTimer?.cancel();
    _chatService.disposeSocket();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleLiveReload() {
    _liveReloadTimer?.cancel();
    _liveReloadTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) unawaited(_loadData(silent: true));
    });
  }

  /// REST stays authoritative; realtime invalidations update the visible
  /// conversations without flashing a loading spinner.
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final version = ++_loadVersion;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      String? currentUserId = _currentUserId;
      if (currentUserId == null && widget.loadCurrentUserId != null) {
        currentUserId = await widget.loadCurrentUserId!();
      } else if (currentUserId == null) {
        final profileResponse = await ApiClient().dio.get('/auth/me');
        if (profileResponse.statusCode == 200 &&
            profileResponse.data['success'] == true) {
          currentUserId = profileResponse.data['data']['id']?.toString();
        }
      }
      final chats = await _chatService.getConversations();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _currentUserId = currentUserId;
        _chats = chats;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _errorMessage = loadErrorDescription(error));
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _isLoading = false);
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
      return '$hour:$minute${timestamp.hour >= 12 ? ' PM' : ' AM'}';
    }
    if (difference == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = '${months[timestamp.month - 1]} ${timestamp.day}';
    return timestamp.year == now.year
        ? label
        : '$label, ${timestamp.year}';
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
    // Once the server exposes presence, use its live Redis/socket status
    // rather than treating a recent logout timestamp as "online".
    if (user is Map && user['isOnline'] is bool) {
      return user['isOnline'] == true;
    }
    // Compatibility only: older production servers have no presence field.
    final value = user == null ? null : user['lastSeenAt'];
    if (value is! String) return false;
    final seen = DateTime.tryParse(value);
    if (seen == null) return false;
    final age = DateTime.now().difference(seen);
    return !age.isNegative && age.inMinutes < 5;
  }

  int _unreadCount(dynamic conversation) {
    // The API includes reactions in unreadCount; this badge is specifically
    // for unread messages. Keep legacy fixtures compatible until migrated.
    final value = conversation['unreadMessageCount'] ??
        conversation['unreadCount'];
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
                  '${_chats.length} active conversations',
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
                isOnline: chat['type'] == 'DIRECT' ? active : null,
                isGroup: chat['type'] == 'GROUP',
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
                      key: ValueKey('chat-online-$conversationId'),
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
    if (_isLoading && _chats.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_errorMessage != null && _chats.isEmpty) {
      return AppLoadErrorViewport(
        description: _errorMessage,
        onRetry: _loadData,
      );
    }

    final visible = _visibleChats;
    final list = RefreshIndicator(
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
    if (_errorMessage == null) return list;
    return Column(
      children: [
        AppLoadErrorNotice(onRetry: _loadData),
        const SizedBox(height: 9),
        Expanded(child: list),
      ],
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
  /// Optional display-only status derived from the existing chat list.
  /// Presence synchronization is intentionally outside this UI redesign.
  final bool? isOnline;
  final bool isGroup;
  final ChatService? service;
  final Future<String?> Function()? loadCurrentUserId;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
    this.isOnline,
    this.isGroup = false,
    this.service,
    this.loadCurrentUserId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late final ChatService _chatService;
  int _loadVersion = 0;
  int _messageEventRevision = 0;
  Timer? _markReadTimer;
  bool _markReadInFlight = false;
  bool _readAgain = false;
  String? _loadError;
  bool _socketInitialized = false;
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
    _chatService = widget.service ?? ChatService();
    _initializeChat();
  }

  Future<void> _initializeChat({bool silent = false}) async {
    final version = ++_loadVersion;
    final eventRevision = _messageEventRevision;
    if (mounted && !silent) setState(() => _isLoading = true);
    try {
      if (!_socketInitialized) {
        _socketInitialized = true;
        // Subscribe before the REST fetch, so incoming messages cannot fall
        // between loading history and registering event listeners.
        await _chatService.initSocket(_onRealtimeMessage);
        _chatService.joinConversation(widget.conversationId);
      }
      final profile = widget.loadCurrentUserId != null
          ? await widget.loadCurrentUserId!()
          : await _getProfileId();
      final messages = await _chatService.getMessages(widget.conversationId);
      if (!mounted || version != _loadVersion) return;
      if (eventRevision != _messageEventRevision) {
        // Never overwrite an event received while this GET was in flight
        // with an older HTTP snapshot. Fetch the authoritative history again.
        unawaited(_initializeChat(silent: true));
        return;
      }
      setState(() {
        _currentUserId = profile;
        _messages = messages;
        _loadError = null;
        _isLoading = false;
      });
      _scheduleMarkReadIfNeeded(messages);
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loadError = loadErrorDescription(error);
        _isLoading = false;
      });
    }
  }

  bool _hasUnreadReceipt(dynamic message) {
    if (_currentUserId == null || message is! Map) return false;
    if (message['senderId'] == _currentUserId) return false;
    final receipts = message['receipts'];
    if (receipts is! List) return false;
    return receipts.any((receipt) =>
        receipt is Map &&
        receipt['userId']?.toString() == _currentUserId &&
        receipt['readAt'] == null);
  }

  void _scheduleMarkReadIfNeeded(List<dynamic> messages) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!messages.any(_hasUnreadReceipt)) return;
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_markRead());
      }
    });
  }

  Future<void> _markRead() async {
    if (_markReadInFlight) {
      _readAgain = true;
      return;
    }
    _markReadInFlight = true;
    try {
      await _chatService.markConversationRead(widget.conversationId);
    } catch (_) {
      // Leave the server unread state intact if this request fails.
      // The next successful inbox/chat refresh can retry it.
    } finally {
      _markReadInFlight = false;
      if (_readAgain && mounted) {
        _readAgain = false;
        _scheduleMarkReadIfNeeded(_messages);
      }
    }
  }

  void _onRealtimeMessage(dynamic incoming) {
    if (!mounted || incoming is! Map) return;
    final conversationId =
        incoming['conversationId'] ?? incoming['conversation']?['id'];
    if (conversationId != null && conversationId != widget.conversationId) {
      return;
    }
    if (incoming['__realtimeRefresh'] == true) {
      unawaited(_initializeChat(silent: true));
      return;
    }
    final id = incoming['id'];
    if (id == null) return;
    _messageEventRevision++;
    final index = _messages.indexWhere((message) => message['id'] == id);
    if (incoming['__realtimeDeleted'] == true) {
      if (index < 0) return;
      setState(() {
        _messages[index] = {
          ..._messages[index],
          'content': '',
          'attachments': <dynamic>[],
          'deletedAt': DateTime.now().toUtc().toIso8601String(),
        };
      });
      return;
    }
    setState(() {
      if (index >= 0) {
        final previous = _messages[index];
        _messages[index] = {
          ...previous,
          ...incoming,
          'content': incoming['content'] ?? previous['content'] ?? '',
          'senderId': incoming['senderId'] ?? previous['senderId'],
          'sender': incoming['sender'] ?? previous['sender'],
        };
      } else {
        _messages.add(Map<String, dynamic>.from(incoming));
      }
    });
    _scheduleMarkReadIfNeeded([incoming]);
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
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (context) {
        final palette = Theme.of(context).extension<AppPalette>() ??
            (Theme.of(context).brightness == Brightness.dark
                ? AppPalette.dark : AppPalette.light);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.cardBorder),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: palette.panelShadow,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4,
                    ),
                    child: Divider(color: palette.cardBorder, height: 16),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.reply_rounded, color: palette.link, size: 20,
                    ),
                    title: Text(
                      'პასუხის გაცემა (Reply)',
                      style: TextStyle(color: palette.ink, fontSize: 14),
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
                      leading: Icon(
                        Icons.edit_outlined, color: palette.link, size: 20,
                      ),
                      title: Text(
                        'შეცვლა (Edit)',
                        style: TextStyle(color: palette.ink, fontSize: 14),
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
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error, size: 20,
                      ),
                      title: Text(
                        'წაშლა (Delete)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14,
                        ),
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

  String get _chatInitials {
    final parts = widget.chatName.trim().split(RegExp(r'\\s+'))
        .where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length > 1) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final name = parts.first;
    return name.substring(0, name.length < 2 ? 1 : 2).toUpperCase();
  }

  PreferredSizeWidget _chatAppBar(AppPalette palette) {
    final online = widget.isOnline == true;
    return AppBar(
      key: const ValueKey('chat-detail-header'),
      automaticallyImplyLeading: false,
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
      toolbarHeight: 68,
      title: Row(
        children: [
          IconButton(
            key: const ValueKey('chat-detail-back'),
            tooltip: 'უკან',
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: palette.secondaryText, size: 19),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 3),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: widget.isGroup
                    ? const Icon(Icons.groups_rounded,
                        size: 23, color: AppColors.success)
                    : Text(
                        _chatInitials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
              ),
              if (online && !widget.isGroup)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.panel, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.chatName,
                  key: const ValueKey('chat-detail-contact-name'),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (widget.isGroup || widget.isOnline != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (online && !widget.isGroup) ...[
                        const Icon(Icons.circle, color: AppColors.success, size: 6),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        widget.isGroup
                            ? 'ჯგუფური საუბარი'
                            : online ? 'Active now' : 'Offline',
                        key: const ValueKey('chat-detail-presence'),
                        style: TextStyle(
                          color: online && !widget.isGroup
                              ? AppColors.success : palette.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: palette.cardBorder),
      ),
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
    _loadVersion++;
    _markReadTimer?.cancel();
    _chatService.disposeSocket();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppPalette.dark : AppPalette.light);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: _chatAppBar(palette),
      body: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.page,
                palette.unreadBackground.withValues(alpha: 0.65),
                palette.page,
              ],
            ),
          ),
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              if (_loadError != null && _messages.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AppLoadErrorNotice(onRetry: _initializeChat),
                ),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: _isLoading && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null && _messages.isEmpty
                    ? AppLoadErrorViewport(
                        description: _loadError,
                        onRetry: _initializeChat,
                      )
                    : _messages.isEmpty
                    ? const Center(child: Text('დაიწყეთ საუბარი...'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
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
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.panel,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: palette.cardBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.block,
                                      size: 14,
                                      color: palette.muted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ეს შეტყობინება წაიშალა',
                                      style: TextStyle(
                                        color: palette.muted,
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
                          // Consecutive messages from one person appear as a
                          // single visual group, as in the supplied reference.
                          // This changes only labels/spacing, not message data.
                          final previous = reversedIndex > 0
                              ? _messages[reversedIndex - 1] : null;
                          final previousSender = previous == null ? null
                              : previous['senderId'] ?? previous['sender']?['id'];
                          final currentAt = DateTime.tryParse(
                              msg['createdAt']?.toString() ?? '');
                          final previousAt = DateTime.tryParse(
                              previous?['createdAt']?.toString() ?? '');
                          final sameWindow = currentAt != null &&
                              previousAt != null &&
                              currentAt.difference(previousAt).inMinutes.abs() < 5;
                          final showHeader =
                              previousSender != senderId || !sameWindow;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (showHeader)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 11, bottom: 5, left: 5, right: 5,
                                    ),
                                    child: Text(
                                      headerText,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: palette.secondaryText,
                                      ),
                                    ),
                                  ),

                                GestureDetector(
                                  onLongPress: () => _showActionModal(msg),
                                  child: Container(
                                    key: ValueKey('chat-bubble-${msg['id']}'),
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11,
                                    ),
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe ? null : palette.card,
                                      gradient: isMe
                                          ? const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                AppColors.gradientStart,
                                                AppColors.gradientEnd,
                                              ],
                                            ) : null,
                                      border: isMe ? null :
                                          Border.all(color: palette.cardBorder),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isMe
                                              ? AppColors.primary.withValues(alpha: 0.15)
                                              : palette.cardShadow,
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(17),
                                        topRight: const Radius.circular(17),
                                        bottomLeft: Radius.circular(isMe ? 17 : 5),
                                        bottomRight: Radius.circular(isMe ? 5 : 17),
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
                                              color: isMe
                                                  ? Colors.white.withValues(alpha: 0.16)
                                                  : palette.unreadBackground,
                                              border: Border(
                                                left: BorderSide(
                                                  color: isMe ? Colors.white70
                                                      : palette.link,
                                                  width: 3,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  repliedSenderName,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isMe ? Colors.white
                                                        : palette.ink,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  repliedMessage['content'] ??
                                                      '',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isMe
                                                        ? Colors.white70
                                                        : palette.secondaryText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        if (content.isNotEmpty)
                                          Text(
                                            content,
                                            style: TextStyle(
                                              color: isMe ? Colors.white
                                                  : palette.ink,
                                              fontSize: 14,
                                              height: 1.45,
                                              fontWeight: FontWeight.w500,
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
                                                color: palette.panel,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: palette.cardBorder,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.insert_drive_file,
                                                    color: AppColors.primary,
                                                    size: 25,
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
                                                              TextStyle(
                                                                color: palette.ink,
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
                                                                TextStyle(
                                                                  color: palette.muted,
                                                                  fontSize: 11,
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.download,
                                                      color: AppColors.primary,
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
                                            color: palette.panel,
                                            border: Border.all(color: palette.cardBorder),
                                            borderRadius: BorderRadius.circular(12),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.panel,
                      border: Border.all(color: palette.cardBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'შეტყობინების რედაქტირება',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: palette.ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'რედაქტირების გაუქმება',
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: palette.secondaryText),
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
                ),

              if (_replyingToMessageId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.panel,
                      border: Border.all(color: palette.cardBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.reply_rounded,
                            size: 19, color: AppColors.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'პასუხი: $_replyingToSenderName',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _replyingToContent ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'პასუხის გაუქმება',
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: palette.secondaryText),
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
                ),

              // Theme-consistent composer. Existing attach/send callbacks
              // and editing/reply state remain exactly the same.
              Container(
                key: const ValueKey('chat-detail-composer-area'),
                decoration: BoxDecoration(
                  color: palette.panel,
                  border: Border(top: BorderSide(color: palette.cardBorder)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: palette.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: palette.cardShadow,
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const ValueKey('chat-detail-attach'),
                        tooltip: 'ფაილის მიმაგრება',
                        icon: _isUploadingFile
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.attach_file_rounded,
                                color: palette.secondaryText, size: 22),
                        onPressed: _isUploadingFile ? null : _pickAndSendFile,
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-detail-message-input'),
                          controller: _messageController,
                          keyboardType: TextInputType.multiline,
                          minLines: 1,
                          maxLines: 4,
                          style: TextStyle(color: palette.ink, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: _editingMessageId != null
                                ? 'შეცვალეთ შეტყობინება...'
                                : 'დაწერეთ შეტყობინება...',
                            hintStyle: TextStyle(
                              color: palette.hintText, fontSize: 12.5,
                            ),
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 15,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 5, 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              AppColors.gradientStart, AppColors.gradientEnd,
                            ]),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.20),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: IconButton(
                            key: const ValueKey('chat-detail-send'),
                            tooltip: _editingMessageId != null
                                ? 'ცვლილების შენახვა'
                                : 'გაგზავნა',
                            onPressed: _sendMessage,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(39, 39),
                              padding: const EdgeInsets.all(8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              _editingMessageId != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                              size: 19,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
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
}

class NewConversationDialog extends StatefulWidget {
  const NewConversationDialog({super.key, this.service});

  final ChatService? service;

  @override
  State<NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<NewConversationDialog> {
  late final ChatService _chatService;
  int _usersRequestVersion = 0;
  String? _usersLoadError;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  // Independent search terms prevent Direct/Group switching from resetting filters.
  final TextEditingController _directSearchController =
      TextEditingController();

  bool _isGroup = false;
  bool _isLoadingUsers = true;
  bool _isSubmitting = false;
  List<dynamic> _users = [];

  String? _selectedUserId;
  final List<String> _selectedUserIds = [];
  String _memberQuery = '';
  String _directQuery = '';

  @override
  void initState() {
    super.initState();
    _chatService = widget.service ?? ChatService();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final version = ++_usersRequestVersion;
    if (mounted) setState(() => _isLoadingUsers = true);
    try {
      final users = await _chatService.getUsers();
      if (!mounted || version != _usersRequestVersion) return;
      setState(() {
        _users = users;
        _usersLoadError = null;
      });
    } catch (error) {
      if (!mounted || version != _usersRequestVersion) return;
      setState(() => _usersLoadError = loadErrorDescription(error));
    } finally {
      if (mounted && version == _usersRequestVersion) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  @override
  void dispose() {
    _usersRequestVersion++;
    _groupNameController.dispose();
    _searchController.dispose();
    _directSearchController.dispose();
    super.dispose();
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

        // Capture the navigator while the dialog context is still mounted.
        // The modal is popped before entering chat, including when launched
        // from a Dashboard Quick Action.
        final navigator = Navigator.of(context);
        navigator.pop(true);

        // Open the newly-created conversation without reusing a popped
        // dialog's BuildContext.
        navigator.push(
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

  AppPalette get _colors => Theme.of(context).extension<AppPalette>()!;

  String _name(dynamic user) {
    final first = (user['firstName'] ?? '').toString().trim();
    final last = (user['lastName'] ?? '').toString().trim();
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');
    final display = (user['displayName'] ?? '').toString().trim();
    return full.isNotEmpty
        ? full
        : display.isNotEmpty
            ? display
            : (user['email'] ?? '').toString();
  }

  String _subtitle(dynamic user) {
    final department = user['department'];
    final departmentName = department is Map
        ? (department['name'] ?? '').toString().trim()
        : '';
    final number = (user['employeeNumber'] ?? '').toString().trim();
    if (departmentName.isNotEmpty && number.isNotEmpty) {
      return 'Store #$number · $departmentName';
    }
    if (departmentName.isNotEmpty) return departmentName;
    final job = (user['jobTitle'] ?? '').toString().trim();
    return job.isNotEmpty ? job : (user['email'] ?? '').toString();
  }

  List<dynamic> get _visibleMembers {
    final query = _memberQuery.toLowerCase().trim();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      return _name(user).toLowerCase().contains(query) ||
          _subtitle(user).toLowerCase().contains(query) ||
          (user['email'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
  }

  List<dynamic> get _visibleDirectMembers {
    final query = _directQuery.toLowerCase().trim();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      return _name(user).toLowerCase().contains(query) ||
          _subtitle(user).toLowerCase().contains(query) ||
          (user['email'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
  }

  Widget _label(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            color: _colors.secondaryText,
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  InputDecoration _field(String hint, {Widget? prefixIcon, Widget? suffixIcon}) {
    final p = _colors;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: p.cardBorder),
    );
    return InputDecoration(
      filled: true,
      fillColor: p.card,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: p.hintText),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 14,
      ),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.link, width: 1.4),
      ),
    );
  }

  Widget _modeButton(String label, bool group) {
    final p = _colors;
    final selected = _isGroup == group;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _isGroup = group),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.card : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [BoxShadow(color: p.cardShadow, blurRadius: 8)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 16, color: p.link),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? p.link : p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeSwitch() {
    final p = _colors;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.searchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [_modeButton('Direct', false), _modeButton('Group', true)],
      ),
    );
  }

  Widget _directFields() {
    final p = _colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _label('PERSON')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: p.unreadBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _selectedUserId == null ? '0 Selected' : '1 Selected',
                style: TextStyle(
                  color: p.link,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        TextField(
          controller: _directSearchController,
          onChanged: (query) => setState(() => _directQuery = query),
          style: TextStyle(color: p.ink, fontSize: 12),
          textInputAction: TextInputAction.search,
          decoration: _field(
            'Search colleagues...',
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 19,
              color: p.searchIcon,
            ),
            suffixIcon: _directQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _directSearchController.clear();
                      setState(() => _directQuery = '');
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: p.muted,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 9),
        // Reuse the Group member list layout, with single selection enabled.
        _memberList(singleSelection: true),
      ],
    );
  }

  Widget _groupFields() {
    final p = _colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('GROUP NAME'),
        TextField(
          controller: _groupNameController,
          style: TextStyle(color: p.ink, fontSize: 13),
          decoration: _field('შეიყვანეთ სახელი'),
        ),
        const SizedBox(height: 17),
        Row(
          children: [
            Expanded(child: _label('MEMBERS')),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: p.unreadBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _selectedUserIds.length.toString() + ' Selected',
                style: TextStyle(
                  color: p.link,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        TextField(
          controller: _searchController,
          onChanged: (query) => setState(() => _memberQuery = query),
          style: TextStyle(color: p.ink, fontSize: 12),
          textInputAction: TextInputAction.search,
          decoration: _field(
            'Search members...',
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 19,
              color: p.searchIcon,
            ),
            suffixIcon: _memberQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _memberQuery = '');
                    },
                    icon: Icon(Icons.close_rounded, size: 17, color: p.muted),
                  ),
          ),
        ),
        const SizedBox(height: 9),
        _memberList(),
      ],
    );
  }

  Widget _memberList({bool singleSelection = false}) {
    final p = _colors;
    final visible = singleSelection ? _visibleDirectMembers : _visibleMembers;
    final height = (MediaQuery.sizeOf(context).height * 0.26)
        .clamp(120.0, 220.0)
        .toDouble();
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: p.cardBorder),
      ),
      child: _isLoadingUsers && _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _usersLoadError != null && _users.isEmpty
          ? AppLoadErrorViewport(
              compact: true,
              description: _usersLoadError,
              onRetry: _loadUsers,
            )
          : visible.isEmpty
              ? Center(
                  child: Text(
                    (singleSelection ? _directQuery : _memberQuery).isEmpty
                        ? 'No colleagues found'
                        : 'No matching colleagues',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => Divider(
                    color: p.cardBorder,
                    height: 1,
                    indent: 54,
                    endIndent: 10,
                  ),
                  itemBuilder: (context, index) {
                    final user = visible[index];
                    final userId = user['id'] as String;
                    final name = _name(user);
                    final selected = singleSelection
                        ? _selectedUserId == userId
                        : _selectedUserIds.contains(userId);
                    final paletteIndex = userId.codeUnits.fold<int>(
                      0,
                      (sum, code) => sum + code,
                    ) % 4;
                    const gradients = <List<Color>>[
                      [Color(0xFF6C91FF), Color(0xFF315DE9)],
                      [Color(0xFFBF6BFA), Color(0xFF823CE4)],
                      [Color(0xFF1CD2B4), Color(0xFF0AB198)],
                      [Color(0xFFFFBD6C), Color(0xFFE58A3B)],
                    ];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (singleSelection) {
                              // Exactly zero or one selected colleague.
                              _selectedUserId = selected ? null : userId;
                            } else if (selected) {
                              _selectedUserIds.remove(userId);
                            } else {
                              _selectedUserIds.add(userId);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 33,
                                height: 33,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: gradients[paletteIndex],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  name.isEmpty
                                      ? '?'
                                      : name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _subtitle(user),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 9),
                              Container(
                                height: 19,
                                width: 19,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: selected
                                      ? AppColors.primary
                                      : p.searchBackground,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : p.cardBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _submitButton() {
    final button = Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isSubmitting ? null : _startConversation,
          child: Center(
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Start conversation',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
    return _isGroup
        ? SizedBox(width: double.infinity, child: button)
        : Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 182, child: button),
          );
  }

  @override
  Widget build(BuildContext context) {
    final p = _colors;
    return Dialog(
      backgroundColor: p.page,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(27),
        side: BorderSide(color: p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'New conversation',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Material(
                    color: p.searchBackground,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _modeSwitch(),
              const SizedBox(height: 17),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _isGroup ? _groupFields() : _directFields(),
                ),
              ),
              const SizedBox(height: 16),
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }
}
