import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  bool isBlocked = false;
  bool iAmTheBlocker = false;

  @override
  void initState() {
    super.initState();
    _checkBlocked();
    _loadMessages();
    _setupSocket();
  }

  // ---------------- BLOCK CHECK ----------------
  Future<void> _checkBlocked() async {
    final res = await http.get(
      Uri.parse(
        'http://10.0.2.2:5000/api/messages/is-blocked/${widget.myId}/${widget.otherUser['id']}',
      ),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (!mounted) return;

      setState(() {
        isBlocked = data['blocked'];
        iAmTheBlocker = data['iBlocked'];
      });
    }
  }

  // ---------------- LOAD MESSAGES (DB SOURCE OF TRUTH) ----------------
  Future<void> _loadMessages() async {
    final res = await http.get(
      Uri.parse(
        'http://10.0.2.2:5000/api/messages/${widget.myId}/${widget.otherUser['id']}',
      ),
    );

    if (res.statusCode == 200) {
      if (!mounted) return;

      setState(() {
        messages
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(jsonDecode(res.body)));
      });

      _scrollBottom();
    }
  }

  // ---------------- SOCKET (NOTIFY ONLY) ----------------
  void _setupSocket() {
    widget.socket.off('receive-message');

    widget.socket.on('receive-message', (data) {
      // Reload ONLY if this chat is affected
      if (data['sender_id'] == widget.otherUser['id'] ||
          data['receiver_id'] == widget.otherUser['id']) {
        _loadMessages();
      }
    });
  }

  // ---------------- SEND MESSAGE ----------------
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
      // Reload from DB to avoid duplicates / missing messages
      await _loadMessages();

      // Notify receiver only
      widget.socket.emit('send-message', {
        'sender_id': widget.myId,
        'receiver_id': widget.otherUser['id'],
      });
    }
  }

  // ---------------- DELETE FOR ME ----------------
  Future<void> _deleteForMe(int messageId) async {
    await http.post(
      Uri.parse('http://10.0.2.2:5000/api/messages/delete-for-me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'messageId': messageId, 'userId': widget.myId}),
    );

    await _loadMessages();
  }

  // ---------------- CLEAR CHAT ----------------
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

  // ---------------- BLOCK / UNBLOCK ----------------
  Future<void> _toggleBlock() async {
    final endpoint = iAmTheBlocker ? 'unblock' : 'block';

    await http.post(
      Uri.parse('http://10.0.2.2:5000/api/messages/$endpoint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'blocker_id': widget.myId,
        'blocked_id': widget.otherUser['id'],
      }),
    );

    await _checkBlocked();
  }

  void _scrollBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.otherUser['name']),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') _confirmClear();
              if (v == 'block') _confirmBlock();
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
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('images/chat_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(10),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final m = messages[i];
                  final isMe = m['sender_id'] == widget.myId;

                  return GestureDetector(
                    onLongPress: () => _confirmDelete(m['id']),
                    child: Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isMe ? 12 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 12),
                          ),
                        ),
                        child: Text(
                          m['message'],
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (isBlocked) _blockedUI() else _inputUI(),
          ],
        ),
      ),
    );
  }

  Widget _blockedUI() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            iAmTheBlocker
                ? "You have blocked this contact."
                : "You cannot reply to this conversation.",
            style: const TextStyle(color: Colors.grey),
          ),
          if (iAmTheBlocker)
            TextButton(
              onPressed: _toggleBlock,
              child: const Text(
                "UNBLOCK",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputUI() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Type message',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.green,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- CONFIRM DIALOGS ----------------
  void _confirmDelete(int messageId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'This message will be deleted for you permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteForMe(messageId);
            },
            child: const Text('Delete for me'),
          ),
        ],
      ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text(
          'Are you sure you want to clear messages in this chat? This won\'t delete them for the other user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearChat();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock() {
    final title = iAmTheBlocker ? 'Unblock Contact?' : 'Block Contact?';
    final content = iAmTheBlocker
        ? 'You will be able to send and receive messages again.'
        : 'Blocked contacts cannot call you or send you messages.';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _toggleBlock();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }
}
