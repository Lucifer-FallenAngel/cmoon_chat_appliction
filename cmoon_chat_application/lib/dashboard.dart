import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'chat.dart';

class DashboardPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String? profilePic;

  const DashboardPage({
    super.key,
    required this.userId,
    required this.userName,
    this.profilePic,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IO.Socket socket;

  List<Map<String, dynamic>> users = [];
  List<int> onlineUserIds = [];

  int get myId => int.parse(widget.userId);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initSocket();
    _fetchUsers();
  }

  // ---------------- SOCKET ----------------
  void _initSocket() {
    socket = IO.io(
      'http://10.0.2.2:5000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      socket.emit('user-online', myId);
    });

    socket.on('online-users', (data) {
      setState(() {
        onlineUserIds = List<int>.from(
          data.map((e) => int.parse(e.toString())),
        );
      });
    });

    // 🔔 Message notification → refresh from DB
    socket.on('receive-message', (_) {
      _fetchUsers(); // DB is source of truth
    });
  }

  // ---------------- USERS ----------------
  Future<void> _fetchUsers() async {
    final res = await http.get(
      Uri.parse('http://10.0.2.2:5000/api/users?myId=$myId'),
    );

    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);

      if (!mounted) return;

      setState(() {
        users = data
            .map<Map<String, dynamic>>(
              (u) => {
                'id': u['id'],
                'name': u['name'],
                'profile_pic': u['profile_pic'],
                'unread': u['unread'] ?? 0,
              },
            )
            .toList();
      });
    }
  }

  @override
  void dispose() {
    socket.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Hi, Good Morning";
    if (h < 17) return "Hi, Good Afternoon";
    return "Hi, Good Evening";
  }

  @override
  Widget build(BuildContext context) {
    final onlineUsers = users
        .where((u) => onlineUserIds.contains(u['id']))
        .toList();

    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ---------------- HEADER ----------------
          Container(
            padding: EdgeInsets.fromLTRB(16, statusBarHeight + 16, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundImage: widget.profilePic != null
                          ? NetworkImage(widget.profilePic!)
                          : const AssetImage('images/default_user.png')
                              as ImageProvider,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(text: "Registered (${users.length})"),
                    Tab(text: "Online (${onlineUsers.length})"),
                  ],
                ),
              ],
            ),
          ),

          // ---------------- LIST ----------------
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(users),
                _buildUserList(onlineUsers),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- USER TILE ----------------
  Widget _buildUserList(List<Map<String, dynamic>> list) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final u = list[i];
        final isOnline = onlineUserIds.contains(u['id']);
        final unread = u['unread'] ?? 0;

        return ListTile(
          onTap: () async {
            // ✅ Mark messages as read in DB
            await http.post(
              Uri.parse('http://10.0.2.2:5000/api/messages/read-all'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'sender_id': u['id'],
                'receiver_id': myId,
              }),
            );

            setState(() => u['unread'] = 0);

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChatPage(myId: myId, otherUser: u, socket: socket),
              ),
            );

            // 🔄 Refresh after coming back
            _fetchUsers();
          },
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: u['profile_pic'] != null
                    ? NetworkImage(
                        "http://10.0.2.2:5000/uploads/profile_pics/${u['profile_pic']}",
                      )
                    : const AssetImage('images/default_user.png')
                        as ImageProvider,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 6,
                  backgroundColor: isOnline ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          title: Text(
            u['name'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            isOnline ? "Online" : "Offline",
            style: TextStyle(color: isOnline ? Colors.green : Colors.red),
          ),
          trailing: unread > 0
              ? CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.green,
                  child: Text(
                    unread.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                )
              : null,
        );
      },
    );
  }
}
