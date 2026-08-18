import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:vinhuni_app/services/teams_service.dart';
// Đảm bảo đường dẫn này đúng với cấu trúc thư mục của Sơn
import 'teams_message_screen.dart';

class TeamsChatListScreen extends StatefulWidget {
  const TeamsChatListScreen({super.key});

  @override
  State<TeamsChatListScreen> createState() => _TeamsChatListScreenState();
}

class _TeamsChatListScreenState extends State<TeamsChatListScreen> {
  final TeamsService _teamsService = TeamsService();
  bool _isLoading = true;
  List<dynamic> _chats = []; 
  List<dynamic> _teams = []; 

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _initGlobalListener(); 
  }

  /// 📡 Lắng nghe thông báo để tự động cập nhật danh sách tin nhắn
  void _initGlobalListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['cat'] == 'MS_CHAT' || message.data['cat'] == 'MS_CHANNEL') {
        debugPrint("📡 [FCM] Có tin mới. Đang cập nhật danh sách...");
        _loadAllData(); 
      }
    });
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _teamsService.getMyChats(),
        _teamsService.getMyTeams(),
      ]);
      if (mounted) {
        setState(() {
          _chats = results[0];
          _teams = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi tải Teams: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFF0078D4)),
          const SizedBox(width: 20),
          const Text("Đang vào nhóm..."),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("VinhUni Teams (A3)", 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF0078D4),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: "Trò chuyện", icon: Icon(Icons.chat_outlined, size: 20)),
              Tab(text: "Nhóm (Teams)", icon: Icon(Icons.groups_outlined, size: 20)),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadAllData)
          ],
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4)))
          : TabBarView(children: [
              _buildListView(_chats, isChatMode: true),
              _buildListView(_teams, isChatMode: false),
            ]),
      ),
    );
  }

  Widget _buildListView(List<dynamic> items, {required bool isChatMode}) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(isChatMode ? Icons.chat_bubble_outline : Icons.group_off_outlined, 
             size: 60, color: Colors.grey[300]),
        const SizedBox(height: 10),
        // 🔥 ĐÃ FIX: Bỏ chữ const ở đây để không bị lỗi Colors.grey[500]
        Text("Không có dữ liệu hiển thị", style: TextStyle(color: Colors.grey[500])),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
        itemBuilder: (context, index) {
          final item = items[index];
          String title = isChatMode ? (item['topic'] ?? "Cuộc trò chuyện") : (item['displayName'] ?? "Tên Nhóm");
          String subtitle = isChatMode ? (item['lastMessagePreview'] ?? "Bấm để xem...") : (item['description'] ?? "Nhóm chính thức");

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isChatMode ? Colors.blue.shade50 : Colors.orange.shade50,
              child: Icon(isChatMode ? Icons.person_outline : Icons.groups_rounded, 
                          color: isChatMode ? const Color(0xFF0078D4) : Colors.orange),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), 
                        maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]), 
                           maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () async {
              if (isChatMode) {
                Navigator.push(context, MaterialPageRoute(builder: (ctx) => 
                  TeamsMessageScreen(chatId: item['id'], chatTitle: title)));
              } else {
                _showLoadingDialog(context);
                try {
                  final channels = await _teamsService.getChannels(item['id']);
                  if (!mounted) return;
                  Navigator.pop(context);
                  if (channels.isNotEmpty) {
                    final mainChannel = channels.firstWhere(
                      (c) => c['displayName'].toString().toLowerCase().contains('general') || 
                            c['displayName'].toString().toLowerCase().contains('chung'),
                      orElse: () => channels[0],
                    );
                    Navigator.push(context, MaterialPageRoute(builder: (ctx) => 
                      TeamsMessageScreen(chatId: mainChannel['id'], chatTitle: title, teamId: item['id'])));
                  }
                } catch (e) {
                  if (mounted) Navigator.pop(context);
                }
              }
            },
          );
        },
      ),
    );
  }
}