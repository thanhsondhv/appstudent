import 'package:flutter/material.dart';
import 'package:vinhuni_app/services/teams_service.dart';
import 'teams_message_screen.dart'; // Sơn dùng chung màn hình tin nhắn nhé

class TeamsChannelScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const TeamsChannelScreen({super.key, required this.teamId, required this.teamName});

  @override
  State<TeamsChannelScreen> createState() => _TeamsChannelScreenState();
}

class _TeamsChannelScreenState extends State<TeamsChannelScreen> {
  final TeamsService _teamsService = TeamsService();
  List<dynamic> _channels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
  setState(() => _isLoading = true);
  try {
    print("📡 [DEBUG FE] Đang tải kênh cho Team: ${widget.teamId}");
    final data = await _teamsService.getChannels(widget.teamId);
    
    // 🔥 DEBUG: In số lượng kênh nhận được
    print("📡 [DEBUG FE] Danh sách kênh nhận được: $data");
    print("📡 [DEBUG FE] Số lượng kênh: ${data.length}");

    if (mounted) {
      setState(() {
        _channels = data;
        _isLoading = false;
      });
    }
  } catch (e) {
    print("❌ [DEBUG FE] Lỗi load kênh: $e");
    if (mounted) setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teamName, style: const TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFF0078D4),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _channels.length,
            itemBuilder: (context, index) {
              final channel = _channels[index];
              return ListTile(
                leading: const Icon(Icons.tag, color: Color(0xFF0078D4)), // Biểu tượng dấu # của Kênh
                title: Text(channel['displayName'] ?? "Kênh không tên"),
                subtitle: Text(channel['description'] ?? "Bấm để xem thảo luận"),
                onTap: () {
                  // Mở màn hình tin nhắn (Sơn truyền chatId là ID của Kênh)
                  Navigator.push(context, MaterialPageRoute(builder: (ctx) => 
                    TeamsMessageScreen(chatId: channel['id'], chatTitle: channel['displayName'])));
                },
              );
            },
          ),
    );
  }
}