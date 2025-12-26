import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _checkBlocked();
    _loadMessages();
    _setupSocket();

    widget.socket.emit('chat-opened', {
      'senderId': widget.otherUser['id'],
      'receiverId': widget.myId,
    });
  }

  // ================= SCROLL =================
  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showDeleteDialog(int messageId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Message"),
        content: const Text("Do you want to delete this message?"),
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
            child: const Text(
              "Delete for me",
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  // ================= DATE HELPERS =================
  String formatTime(String iso) =>
      DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());

  String formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) return "Today";
    if (msgDate == yesterday) return "Yesterday";
    return DateFormat('d MMMM yyyy').format(date);
  }

  // ================= CHECK BLOCK =================
  Future<void> _checkBlocked() async {
    final res = await http.get(
      Uri.parse(
        'http://10.0.2.2:5000/api/messages/is-blocked/${widget.myId}/${widget.otherUser['id']}',
      ),
    );

    if (res.statusCode == 200 && mounted) {
      final data = jsonDecode(res.body);
      setState(() {
        isBlocked = data['blocked'];
        iAmTheBlocker = data['iBlocked'];
      });
    }
  }

  // ================= LOAD MESSAGES =================
  Future<void> _loadMessages() async {
    final res = await http.get(
      Uri.parse(
        'http://10.0.2.2:5000/api/messages/${widget.myId}/${widget.otherUser['id']}',
      ),
    );

    if (res.statusCode == 200 && mounted) {
      setState(() {
        messages
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(jsonDecode(res.body)));
      });

      _scrollBottom();

      widget.socket.emit('message-read', {
        'senderId': widget.otherUser['id'],
        'receiverId': widget.myId,
      });
    }
  }

  // ================= SOCKET =================
  void _setupSocket() {
    widget.socket.off('receive-message');
    widget.socket.off('message-status-update');
    widget.socket.off('message-deleted-for-me');

    widget.socket.on('receive-message', (_) => _loadMessages());
    widget.socket.on('message-status-update', (_) => _loadMessages());

    widget.socket.on('message-deleted-for-me', (data) {
      setState(() {
        messages.removeWhere((m) => m['id'] == data['messageId']);
      });
    });
  }

  // ================= SEND MESSAGE =================
  Future<void> _sendMessage() async {
    if (controller.text.trim().isEmpty || isBlocked) return;

    final text = controller.text.trim();
    controller.clear();

    final res = await http.post(
      Uri.parse('http://10.0.2.2:5000/api/messages/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender_id': widget.myId,
        'receiver_id': widget.otherUser['id'],
        'message': text,
      }),
    );

    if (res.statusCode == 200) {
      await _loadMessages();
      widget.socket.emit('send-message', {
        'sender_id': widget.myId,
        'receiver_id': widget.otherUser['id'],
      });
    }
  }

  // ================= DELETE FOR ME =================
  Future<void> _deleteForMe(int messageId) async {
    await http.post(
      Uri.parse('http://10.0.2.2:5000/api/messages/delete-for-me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'messageId': messageId, 'userId': widget.myId}),
    );

    setState(() {
      messages.removeWhere((m) => m['id'] == messageId);
    });

    widget.socket.emit('delete-for-me', {
      'messageId': messageId,
      'userId': widget.myId,
    });
  }

  // ================= CLEAR CHAT =================
  Future<void> _clearChat() async {
    await http.post(
      Uri.parse('http://10.0.2.2:5000/api/messages/clear-chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': widget.myId,
        'otherUserId': widget.otherUser['id'],
      }),
    );

    setState(() => messages.clear());
  }

  // ================= BLOCK / UNBLOCK =================
  Future<void> _blockUser() async {
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
  }

  Future<void> _unblockUser() async {
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
  }

  // ================= BLOCK CONFIRMATION =================
  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          iAmTheBlocker
              ? "Unblock this contact?"
              : "Are you sure you want to block this contact?",
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
            child: const Text("Yes", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  // ================= MESSAGE STATUS ICON =================
  Widget _statusTick(String status) {
    IconData icon = Icons.check;
    Color color = Colors.grey;

    if (status == 'delivered') icon = Icons.done_all;
    if (status == 'read') {
      icon = Icons.done_all;
      color = Colors.blue;
    }

    return Icon(icon, size: 16, color: color);
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(widget.otherUser['name']),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') {
                _showBlockDialog();
              } else if (value == 'clear') {
                _clearChat();
              }
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
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                final isMe = m['sender_id'] == widget.myId;
                final msgTime = DateTime.parse(m['createdAt']).toLocal();

                final showDateHeader =
                    i == 0 ||
                    DateTime.parse(
                          messages[i - 1]['createdAt'],
                        ).toLocal().day !=
                        msgTime.day;

                return Column(
                  children: [
                    if (showDateHeader)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              formatDateLabel(msgTime),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                          constraints: const BoxConstraints(maxWidth: 280),
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFFDCF8C6)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(m['message']),
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
                                  const SizedBox(width: 4),
                                  if (isMe) _statusTick(m['status']),
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
              child: const Text(
                "You have blocked this contact",
                textAlign: TextAlign.center,
              ),
            ),

          if (!isBlocked)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Type message',
                      ),
                    ),
                  ),
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
}
