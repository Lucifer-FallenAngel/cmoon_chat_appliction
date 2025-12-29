import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'chat.dart';

class DashboardPage extends StatefulWidget {
  final int userId;
  final String userName;
  final String? profilePic;
  final IO.Socket? socket; // ← now optional

  const DashboardPage({
    super.key,
    required this.userId,
    required this.userName,
    this.profilePic,
    this.socket,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IO.Socket _socket; // internal socket instance

  List<Map<String, dynamic>> users = [];
  Set<int> onlineUserIds = {};

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    // Initialize TabController
    _tabController = TabController(length: 2, vsync: this);

    // Initialize socket - use provided one or create new
    _socket =
        widget.socket ??
        IO.io(
          'http://10.0.2.2:5000',
          IO.OptionBuilder()
              .setTransports(['websocket'])
              .enableAutoConnect()
              .build(),
        );

    _initSocketListeners();
    _fetchUsers();
  }

  void _initSocketListeners() {
    // Remove previous listeners to prevent duplicates
    _socket.off('online-users-updated');
    _socket.off('new-message-arrived');

    _socket.onConnect((_) {
      _socket.emit('user-online', widget.userId);
    });

    // Online status updates
    _socket.on('online-users-updated', (data) {
      if (data is List) {
        setState(() {
          onlineUserIds = Set<int>.from(
            data.map((e) => int.tryParse(e.toString()) ?? 0),
          );
          onlineUserIds.remove(0); // remove invalid entries
        });
      }
    });

    // New incoming message → refresh user list
    _socket.on('new-message-arrived', (_) {
      _fetchUsers();
    });
  }

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);

    try {
      final res = await http.get(
        Uri.parse('http://10.0.2.2:5000/api/users?myId=${widget.userId}'),
      );

      if (res.statusCode == 200 && mounted) {
        final List data = jsonDecode(res.body);
        setState(() {
          users = data.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  @override
  void dispose() {
    _tabController.dispose();

    // Only disconnect if we created the socket ourselves
    if (widget.socket == null) {
      _socket.disconnect();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onlineUsers = users
        .where((u) => onlineUserIds.contains(u['id']))
        .toList();
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.fromLTRB(16, statusBarHeight + 16, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 26,
                        backgroundImage: widget.profilePic != null
                            ? NetworkImage(widget.profilePic!)
                            : const AssetImage('images/default_user.png')
                                  as ImageProvider,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
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
                    Tab(text: "All (${users.length})"),
                    Tab(text: "Online (${onlineUsers.length})"),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
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

  Widget _buildUserList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          "No users yet",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchUsers,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final u = list[i];
          final isOnline = onlineUserIds.contains(u['id']);
          final unread = (u['unread'] as num?)?.toInt() ?? 0;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatPage(
                    myId: widget.userId,
                    otherUser: u,
                    socket: _socket, // ← pass our internal socket
                  ),
                ),
              );
              // Refresh after returning from chat
              _fetchUsers();
            },
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: u['profile_pic'] != null
                      ? NetworkImage(
                          "http://10.0.2.2:5000/uploads/profile_pics/${u['profile_pic']}",
                        )
                      : const AssetImage('images/default_user.png')
                            as ImageProvider,
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              u['name'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isOnline ? "Online" : "Offline",
              style: TextStyle(
                color: isOnline ? Colors.green : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            trailing: unread > 0
                ? Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unread.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
