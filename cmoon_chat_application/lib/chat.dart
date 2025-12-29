import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart'; // NEW: OneSignal for push notifications

class ChatPage extends StatefulWidget {
  final int myId;
  final Map<String, dynamic> otherUser;
  final IO.Socket socket;

  const ChatPage({
    super.key,
    required this.myId,
    required this.otherUser,
    required this.socket,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Map<String, dynamic>> messages = [];
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool isBlocked = false;
  bool iAmTheBlocker = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBlocked();
    _loadMessages();
    _setupSocketListeners();

    // Mark messages as delivered when chat is opened
    widget.socket.emit('chat-opened', {
      'senderId': widget.otherUser['id'],
      'receiverId': widget.myId,
    });

    // NEW: Handle foreground push notifications from OneSignal
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data != null) {
        final senderId = data['senderId']?.toString();
        if (senderId == widget.otherUser['id'].toString()) {
          // This notification is for the current chat → reload messages
          _loadMessages();
        }
      }
    });
  }

  @override
  void dispose() {
    widget.socket.off('new-message-arrived');
    widget.socket.off('messages-delivered');
    widget.socket.off('messages-read-by-recipient');
    widget.socket.off('message-deleted-for-me');
    widget.socket.off('chat-cleared-for-me');
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    widget.socket.off('new-message-arrived');
    widget.socket.off('messages-delivered');
    widget.socket.off('messages-read-by-recipient');
    widget.socket.off('message-deleted-for-me');
    widget.socket.off('chat-cleared-for-me');

    // New message arrived
    widget.socket.on('new-message-arrived', (_) {
      _loadMessages();
    });

    // My messages were delivered
    widget.socket.on('messages-delivered', (data) {
      if (data['senderId'] == widget.myId &&
          data['receiverId'] == widget.otherUser['id']) {
        setState(() {
          for (var msg in messages) {
            if (msg['sender_id'] == widget.myId && msg['status'] == 'sent') {
              msg['status'] = 'delivered';
            }
          }
        });
      }
    });

    // My messages were read by the other person
    widget.socket.on('messages-read-by-recipient', (data) {
      if (data['senderId'] == widget.myId &&
          data['receiverId'] == widget.otherUser['id']) {
        setState(() {
          for (var msg in messages) {
            if (msg['sender_id'] == widget.myId && msg['status'] != 'read') {
              msg['status'] = 'read';
            }
          }
        });
      }
    });

    // Single message deleted for me
    widget.socket.on('message-deleted-for-me', (data) {
      if (data != null && data['messageId'] != null) {
        setState(() {
          messages.removeWhere((m) => m['id'] == data['messageId']);
        });
      }
    });

    // Whole chat cleared for me
    widget.socket.on('chat-cleared-for-me', (data) {
      if (data != null && data['otherUserId'] == widget.otherUser['id']) {
        setState(() {
          messages.clear();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat cleared for you')));
      }
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        if (animate) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _loadMessages() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    try {
      final res = await http.get(
        Uri.parse(
          'http://10.0.2.2:5000/api/messages/${widget.myId}/${widget.otherUser['id']}',
        ),
      );

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);

        setState(() {
          messages
            ..clear()
            ..addAll(data.cast<Map<String, dynamic>>());
        });

        _scrollToBottom(animate: false);

        // Mark messages from other user as read
        if (messages.any((m) => m['sender_id'] == widget.otherUser['id'])) {
          widget.socket.emit('messages-read', {
            'senderId': widget.otherUser['id'],
            'receiverId': widget.myId,
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load messages')));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    if (controller.text.trim().isEmpty || isBlocked) return;

    final text = controller.text.trim();
    controller.clear();

    // Optimistic UI
    final tempMessage = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'conversation_id': 0,
      'sender_id': widget.myId,
      'receiver_id': widget.otherUser['id'],
      'message': text,
      'message_type': 'text',
      'status': 'sent',
      'createdAt': DateTime.now().toIso8601String(),
      'file_url': null,
    };

    setState(() {
      messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_id': widget.myId,
          'receiver_id': widget.otherUser['id'],
          'message': text,
        }),
      );
      _loadMessages();
    } catch (e) {
      setState(() {
        messages.removeLast();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  Future<void> _deleteForMe(int messageId) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/delete-for-me'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'messageId': messageId, 'userId': widget.myId}),
      );

      if (response.statusCode == 200) {
        setState(() {
          messages.removeWhere((m) => m['id'] == messageId);
        });
      } else {
        throw Exception('Delete failed');
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/clear-chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.myId,
          'otherUserId': widget.otherUser['id'],
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          messages.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Chat cleared for you')));
        }
      } else {
        throw Exception('Clear chat failed');
      }
    } catch (e) {
      debugPrint('Clear chat error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to clear chat')));
      }
    }
  }

  // ── Block / Unblock ────────────────────────────────────────────

  Future<void> _blockUser() async {
    try {
      await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'blocker_id': widget.myId,
          'blocked_id': widget.otherUser['id'],
        }),
      );
      setState(() {
        isBlocked = true;
        iAmTheBlocker = true;
      });
    } catch (e) {
      debugPrint('Block error: $e');
    }
  }

  Future<void> _unblockUser() async {
    try {
      await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/unblock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'blocker_id': widget.myId,
          'blocked_id': widget.otherUser['id'],
        }),
      );
      setState(() {
        isBlocked = false;
        iAmTheBlocker = false;
      });
    } catch (e) {
      debugPrint('Unblock error: $e');
    }
  }

  Future<void> _checkBlocked() async {
    try {
      final res = await http.get(
        Uri.parse(
          'http://10.0.2.2:5000/api/messages/is-blocked/${widget.myId}/${widget.otherUser['id']}',
        ),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          isBlocked = data['blocked'];
          iAmTheBlocker = data['iBlocked'];
        });
      }
    } catch (_) {}
  }

  // ── Attachments ────────────────────────────────────────────────

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("Camera"),
            onTap: () {
              Navigator.pop(context);
              _pickFromCamera();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text("Gallery"),
            onTap: () {
              Navigator.pop(context);
              _pickFromGallery();
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text("File"),
            onTap: () {
              Navigator.pop(context);
              _pickFile();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    final img = await ImagePicker().pickImage(source: ImageSource.camera);
    if (img != null) _uploadFile(File(img.path), "image");
  }

  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;

    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img != null) _uploadFile(File(img.path), "image");
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      _uploadFile(File(result.files.single.path!), "file");
    }
  }

  Future<void> _uploadFile(File file, String type) async {
    try {
      final uri = Uri.parse('http://10.0.2.2:5000/api/messages/upload');

      final req = http.MultipartRequest("POST", uri);
      req.fields['sender_id'] = widget.myId.toString();
      req.fields['receiver_id'] = widget.otherUser['id'].toString();
      req.fields['message_type'] = type;
      req.files.add(await http.MultipartFile.fromPath('file', file.path));

      await req.send();
      _loadMessages();
    } catch (e) {
      debugPrint('File upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload file')));
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(widget.otherUser['name']),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block') _showBlockDialog();
              if (v == 'clear') _clearChat();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Text(
                  iAmTheBlocker ? 'Unblock Contact' : 'Block Contact',
                ),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final isMe = m['sender_id'] == widget.myId;
                      final date = DateTime.parse(m['createdAt']).toLocal();

                      final showDateHeader =
                          i == 0 ||
                          DateTime.parse(
                                messages[i - 1]['createdAt'],
                              ).toLocal().day !=
                              date.day;

                      return Column(
                        children: [
                          if (showDateHeader)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                formatDateLabel(date),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          GestureDetector(
                            onLongPress: () => _showDeleteDialog(m['id']),
                            child: Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? const Color(0xFFDCF8C6)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (m['message_type'] == 'image')
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          'http://10.0.2.2:5000/${m['file_url']}',
                                          width: 220,
                                          fit: BoxFit.cover,
                                          loadingBuilder:
                                              (
                                                context,
                                                child,
                                                loadingProgress,
                                              ) {
                                                if (loadingProgress == null)
                                                  return child;
                                                return const SizedBox(
                                                  width: 220,
                                                  height: 150,
                                                  child: Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  ),
                                                );
                                              },
                                        ),
                                      )
                                    else if (m['message_type'] == 'file')
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.insert_drive_file,
                                              color: Colors.blue[700],
                                              size: 28,
                                            ),
                                            const SizedBox(width: 10),
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    m['file_url']
                                                        .split('/')
                                                        .last,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    "Tap to download",
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Text(
                                        m['message'] ?? '',
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          formatTime(m['createdAt']),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          _buildStatusIcon(
                                            m['status'] ?? 'sent',
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (isBlocked)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade100,
              width: double.infinity,
              child: const Text(
                "You have blocked this contact. You cannot send or receive messages.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (!isBlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _showAttachmentOptions,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: "Type a message",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'sent':
        return const Icon(Icons.done, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return Icon(Icons.done_all, size: 16, color: Colors.blue[700]);
      default:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
    }
  }

  void _showDeleteDialog(int messageId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete message?"),
        content: const Text("This will delete the message only for you."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteForMe(messageId);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String formatTime(String iso) =>
      DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());

  String formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day)
      return "Today";

    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day)
      return "Yesterday";

    return DateFormat('d MMMM yyyy').format(date);
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          iAmTheBlocker ? "Unblock this contact?" : "Block this contact?",
        ),
        content: Text(
          iAmTheBlocker
              ? "You will be able to send and receive messages again."
              : "If you block this contact, you won't be able to send or receive messages.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (iAmTheBlocker) {
                await _unblockUser();
              } else {
                await _blockUser();
              }
            },
            child: Text(
              "Yes",
              style: TextStyle(
                color: iAmTheBlocker ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
