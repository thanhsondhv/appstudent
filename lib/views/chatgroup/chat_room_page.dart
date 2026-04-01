import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoomPage extends StatefulWidget {
  final String groupId;
  final String userCode;

  const ChatRoomPage({
    super.key, 
    required this.groupId, 
    required this.userCode,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  // --- TRẠNG THÁI DỮ LIỆU ---
  bool _isLocked = false; 
  int _userRole = 3; 
  String _groupName = "Đang tải...";
  bool _isLoading = true;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initChatRoom(); 
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // --- KẾT NỐI HỆ THỐNG LAI (HYBRID) ---
  Future<void> _initChatRoom() async {
    try {
      final joinRes = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/v1/chat/join"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "group_id": widget.groupId,
          "user_code": widget.userCode,
        }),
      );

      if (joinRes.statusCode == 200) {
        final data = jsonDecode(joinRes.body);
        if (mounted) {
          setState(() {
            _groupName = data['group_name'];
            _isLocked = data['is_locked'] ?? false;
            _userRole = data['user_role'] ?? 3;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("🔥 Lỗi khởi tạo: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String content = _messageController.text.trim();
    _messageController.clear(); 

    try {
      await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/v1/chat/send"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "group_id": widget.groupId,
          "sender_code": widget.userCode,
          "message_content": content,
          "message_type": "TEXT"
        }),
      );
    } catch (e) {
      debugPrint("🔥 Lỗi gửi tin: $e");
    }
  }

  bool get canMessage => (_userRole == 1 || _userRole == 2) || !_isLocked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_groupName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text("Điều hành • ${widget.groupId}", style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          if (_userRole < 3) 
            IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.groupId)
                      .collection('messages')
                      .orderBy('created_at', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final docs = snapshot.data!.docs;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(10),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return _buildMessageItem(data);
                      },
                    );
                  },
                ),
              ),
              canMessage ? _buildChatInput() : _buildLockedInfo(),
            ],
          ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> data) {
    bool isMe = data['sender_code'] == widget.userCode;
    String? aiSummary = data['ai_summary'];
    bool hasAI = aiSummary != null && aiSummary.isNotEmpty;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) 
            Padding(
              padding: const EdgeInsets.only(left: 5, bottom: 2),
              child: Text(data['sender_code'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue.shade100 : Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(data['content'] ?? ""),
          ),
          if (hasAI) _buildAISummaryCard(aiSummary), 
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildAISummaryCard(String summary) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.7,
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "AI Tóm tắt: $summary",
              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white, 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(25)),
                child: TextField(
                  controller: _messageController,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: "Nhập nội dung điều hành...", 
                    border: InputBorder.none,
                    hintStyle: TextStyle(fontSize: 14)
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blue.shade800,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20), 
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.grey.shade50,
      child: SafeArea(
        child: Text(
          "🔒 Nhóm chỉ dành cho Trưởng/Phó đơn vị gửi thông báo.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}