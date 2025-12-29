import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

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
  final FocusNode focusNode = FocusNode();

  bool showEmojiPicker = false;
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

    focusNode.addListener(() {
      if (focusNode.hasFocus && showEmojiPicker) {
        setState(() => showEmojiPicker = false);
      }
    });

    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data != null) {
        final senderId = data['senderId']?.toString();
        if (senderId == widget.otherUser['id'].toString()) {
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
    focusNode.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    widget.socket.off('new-message-arrived');
    widget.socket.off('messages-delivered');
    widget.socket.off('messages-read-by-recipient');
    widget.socket.off('message-deleted-for-me');
    widget.socket.off('chat-cleared-for-me');

    widget.socket.on('new-message-arrived', (_) => _loadMessages());

    widget.socket.on('messages-delivered', (data) {
      if (data is Map &&
          data['senderId'] == widget.myId &&
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

    widget.socket.on('messages-read-by-recipient', (data) {
      if (data is Map &&
          data['senderId'] == widget.myId &&
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

    widget.socket.on('message-deleted-for-me', (data) {
      if (data is Map && data['messageId'] != null) {
        setState(() {
          messages.removeWhere((m) => m['id'] == data['messageId']);
        });
      }
    });

    widget.socket.on('chat-cleared-for-me', (data) {
      if (data is Map && data['otherUserId'] == widget.otherUser['id']) {
        setState(() {
          messages.clear();
        });
        _showSnackBar('Chat cleared for you');
      }
    });
  }

  Future<void> _loadMessages() async {
    if (isLoading || !mounted) return;
    setState(() => isLoading = true);

    try {
      final res = await http.get(
        Uri.parse(
          'http://10.0.2.2:5000/api/messages/${widget.myId}/${widget.otherUser['id']}',
        ),
      );

      if (res.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(res.body);

        setState(() {
          messages
            ..clear()
            ..addAll(data.cast<Map<String, dynamic>>());
        });

        _scrollToBottom(animate: false);

        if (messages.any((m) => m['sender_id'] == widget.otherUser['id'])) {
          widget.socket.emit('messages-read', {
            'senderId': widget.otherUser['id'],
            'receiverId': widget.myId,
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) _showSnackBar('Failed to load messages');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || isBlocked) return;

    controller.clear();

    final tempId = DateTime.now().millisecondsSinceEpoch;
    final tempMessage = {
      'id': tempId,
      'conversation_id': 0,
      'sender_id': widget.myId,
      'receiver_id': widget.otherUser['id'],
      'message': text,
      'message_type': 'text',
      'status': 'sending',
      'createdAt': DateTime.now().toIso8601String(),
      'file_url': null,
    };

    setState(() {
      messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_id': widget.myId,
          'receiver_id': widget.otherUser['id'],
          'message': text,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Send failed with status: ${response.statusCode}');
      }

      await _loadMessages();
    } catch (e) {
      debugPrint('Send message error: $e');
      if (mounted) {
        setState(() {
          final msg = messages.firstWhere((m) => m['id'] == tempId);
          msg['status'] = 'failed';
        });
        _showSnackBar('Failed to send message');
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

      if (response.statusCode == 200 && mounted) {
        setState(() {
          messages.removeWhere((m) => m['id'] == messageId);
        });
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) _showSnackBar('Failed to delete message');
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

      if (response.statusCode == 200 && mounted) {
        setState(() => messages.clear());
        _showSnackBar('Chat cleared for you');
      } else {
        throw Exception('Clear failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Clear chat error: $e');
      if (mounted) _showSnackBar('Failed to clear chat');
    }
  }

  // Block / Unblock
  Future<void> _blockUser() async {
    try {
      final res = await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'blocker_id': widget.myId,
          'blocked_id': widget.otherUser['id'],
        }),
      );

      if (res.statusCode == 200 && mounted) {
        setState(() {
          isBlocked = true;
          iAmTheBlocker = true;
        });
      }
    } catch (e) {
      debugPrint('Block error: $e');
    }
  }

  Future<void> _unblockUser() async {
    try {
      final res = await http.post(
        Uri.parse('http://10.0.2.2:5000/api/messages/unblock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'blocker_id': widget.myId,
          'blocked_id': widget.otherUser['id'],
        }),
      );

      if (res.statusCode == 200 && mounted) {
        setState(() {
          isBlocked = false;
          iAmTheBlocker = false;
        });
      }
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

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          isBlocked = data['blocked'] ?? false;
          iAmTheBlocker = data['iBlocked'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('Check blocked error: $e');
    }
  }

  // Attachments
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
    if (status != PermissionStatus.granted) return;

    final img = await ImagePicker().pickImage(source: ImageSource.camera);
    if (img != null) await _uploadFile(File(img.path), "image");
  }

  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.request();
    if (status != PermissionStatus.granted) return;

    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img != null) await _uploadFile(File(img.path), "image");
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      await _uploadFile(File(result.files.single.path!), "file");
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

      final streamedResponse = await req.send();
      if (streamedResponse.statusCode != 200 &&
          streamedResponse.statusCode != 201) {
        throw Exception('Upload failed: ${streamedResponse.statusCode}');
      }

      await _loadMessages();
    } catch (e) {
      debugPrint('File upload failed: $e');
      if (mounted) _showSnackBar('Failed to upload file');
    }
  }

  // Helpers
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      if (animate) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });
  }

  String formatTime(String iso) {
    return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());
  }

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

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'sending':
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.done, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return Icon(Icons.done_all, size: 16, color: Colors.blue[700]);
      case 'failed':
        return const Icon(Icons.error_outline, size: 16, color: Colors.red);
      default:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
    }
  }

  void _showDeleteDialog(int messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !showEmojiPicker,
      onPopInvokedWithResult: (didPop, result) {
        if (showEmojiPicker && !didPop) {
          setState(() => showEmojiPicker = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.green,
          title: Text(widget.otherUser['name'] ?? 'Chat'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'block') _showBlockDialog();
                if (value == 'clear') _clearChat();
              },
              itemBuilder: (context) => [
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
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final isMe = m['sender_id'] == widget.myId;
                        final date = DateTime.parse(m['createdAt']).toLocal();

                        final showDateHeader =
                            index == 0 ||
                            DateTime.parse(
                                  messages[index - 1]['createdAt'],
                                ).toLocal().day !=
                                date.day;

                        return Column(
                          children: [
                            if (showDateHeader)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
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
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  }
                                                  return const SizedBox(
                                                    width: 220,
                                                    height: 150,
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  );
                                                },
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return const SizedBox(
                                                    width: 220,
                                                    height: 150,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.broken_image,
                                                        size: 60,
                                                        color: Colors.grey,
                                                      ),
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
                                                              ?.split('/')
                                                              ?.last ??
                                                          'File',
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
                                            _buildStatusIcon(m['status']),
                                          ],
                                          if (m['status'] == 'failed' && isMe)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                              ),
                                              child: Text(
                                                'Failed',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.red[700],
                                                ),
                                              ),
                                            ),
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

            // Blocked warning
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

            // Input area
            if (!isBlocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file),
                          onPressed: _showAttachmentOptions,
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.sentences,
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
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() => showEmojiPicker = !showEmojiPicker);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          color: Colors.green,
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),

                    // Emoji picker
                    if (showEmojiPicker)
                      SizedBox(
                        height: 280,
                        child: EmojiPicker(
                          onEmojiSelected: (category, emoji) {
                            controller.text += emoji.emoji;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          },
                          config: Config(
                            height: 280,
                            emojiViewConfig: EmojiViewConfig(
                              columns: 7,
                              emojiSizeMax: 28,
                              backgroundColor: const Color(0xFFF2F2F2),
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              indicatorColor: Colors.green,
                              iconColor: Colors.grey,
                              iconColorSelected: Colors.green,
                            ),
                            bottomActionBarConfig: BottomActionBarConfig(
                              backgroundColor: Colors.green,
                              buttonColor: Colors.green,
                            ),
                            skinToneConfig: const SkinToneConfig(enabled: true),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
