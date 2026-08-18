// views/chatgroup/chat_group_list_page.dart
import 'package:flutter/material.dart';
import 'chat_room_page.dart';
import 'package:vinhuni_app/services/database_helper.dart';
import '../../services/vinhuni_api_client.dart';

class ChatGroupListPage extends StatefulWidget {
  final String userCode;

  const ChatGroupListPage({super.key, required this.userCode});

  @override
  State<ChatGroupListPage> createState() => _ChatGroupListPageState();
}

class _ChatGroupListPageState extends State<ChatGroupListPage> {
  List<dynamic> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGroups();
  }

  // ==========================================
  // 1. LOGIC GỌI API & DATABASE
  // ==========================================

  Future<void> _fetchGroups() async {
    final localGroups = await DatabaseHelper.instance.getChatGroups();
    if (localGroups.isNotEmpty && mounted) {
      setState(() {
        _groups = localGroups;
        _isLoading = false;
      });
    }

    try {
      final response = await VinhUniClient.instance.get(
        "/api/v1/chat/my_groups/${widget.userCode}",
      );

      if (response.statusCode == 200) {
        final List<dynamic> serverGroups = response.data;
        await DatabaseHelper.instance.saveChatGroups(serverGroups);

        if (mounted) {
          setState(() {
            _groups = serverGroups;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi đồng bộ: $e. Đang sử dụng dữ liệu Offline.");
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  Future<void> _createNewGroup(String groupName) async {
    try {
      final response = await VinhUniClient.instance.post(
        "/api/v1/chat/groups/create",
        data: {
          "group_name": groupName,
          "created_by": widget.userCode, 
          "members": [] 
        }
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tạo nhóm '$groupName' thành công!"), backgroundColor: Colors.green)
        );
        _fetchGroups();
      }
    } catch (e) {
      debugPrint("❌ Lỗi tạo nhóm: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi khi tạo nhóm! Vui lòng thử lại."), backgroundColor: Colors.red)
      );
    }
  }

  // 🔥 ĐÃ ĐƯỢC CỦA CỐ: Gọi API báo cho Python giải tán liên kết thành viên
  void _deleteGroup(String groupId) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Đang xử lý rời nhóm trên hệ thống..."), duration: Duration(seconds: 1))
      );
    }

    try {
      // 1. Gọi API báo cho server Python xóa thành viên ra khỏi nhóm
      final response = await VinhUniClient.instance.post(
        "/api/v1/chat/group/leave",
        data: {
          "group_id": groupId,
          "user_code": widget.userCode
        }
      );

      if (response.statusCode == 200) {
        // 2. Xóa sạch ở SQLite nội bộ máy
        await DatabaseHelper.instance.deleteChatGroupLocal(groupId);
        
        // 3. Cập nhật trạng thái giao diện ngay lập tức
        if (mounted) {
          setState(() {
            _groups.removeWhere((element) => element['GroupId'] == groupId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Đã rời nhóm và xóa khỏi danh sách thành công!"), backgroundColor: Colors.green)
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Lỗi rời nhóm từ Server: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi kết nối Server. Không thể rời nhóm lúc này!"), backgroundColor: Colors.red)
      );
    }
  }

  // ==========================================
  // 2. GIAO DIỆN CHÍNH & POPUP
  // ==========================================

  void _showCreateGroupDialog() {
    final TextEditingController groupNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Tạo nhóm mới", style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 18)),
          content: TextField(
            controller: groupNameController,
            decoration: const InputDecoration(
              hintText: "Nhập tên nhóm...",
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900),
              onPressed: () async {
                if (groupNameController.text.trim().isEmpty) return;
                Navigator.pop(ctx); 
                _createNewGroup(groupNameController.text.trim());
              },
              child: const Text("Tạo ngay", style: TextStyle(color: Colors.white)),
            )
          ],
        );
      }
    );
  }

  void _showDeleteConfirmDialog(String groupId, String groupName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận rời nhóm", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("Bạn có chắc chắn muốn rời và xóa nhóm '$groupName' khỏi danh sách không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () { 
              Navigator.pop(ctx); 
              _deleteGroup(groupId); 
            }, 
            child: const Text("Rời Nhóm", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Chat Điều Hành", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade900,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupDialog, 
        backgroundColor: Colors.blue.shade900,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _fetchGroups, 
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: _groups.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _buildGroupItem(_groups[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildGroupItem(Map<String, dynamic> g) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Text(g['GroupName'][0].toUpperCase(), style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
        ),
        title: Text(g['GroupName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(g['LastMessage'] ?? "Chưa có tin nhắn mới", maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(g['LastTime'] ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 5),
            if (g['UnreadCount'] != null && g['UnreadCount'] > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text("${g['UnreadCount']}", style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatRoomPage(groupId: g['GroupId'], userCode: widget.userCode),
            ),
          ).then((value) {
            _fetchGroups(); 
          });
        },
        onLongPress: () => _showDeleteConfirmDialog(g['GroupId'], g['GroupName']),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("Bạn chưa tham gia nhóm điều hành nào.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}