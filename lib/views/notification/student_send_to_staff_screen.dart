import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart'; 
import '../../services/vinhuni_api_client.dart'; 

class StudentSendToStaffScreen extends StatefulWidget {
  const StudentSendToStaffScreen({super.key});
  @override
  State<StudentSendToStaffScreen> createState() => _StudentSendToStaffScreenState();
}

class _StudentSendToStaffScreenState extends State<StudentSendToStaffScreen> {
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _debounce; 
  
  // 🔥 MẶC ĐỊNH LÀ CÁN BỘ: Sinh viên tìm Cán bộ để gửi tin
  final String _targetRole = "CANBO"; 
  Map<String, dynamic>? _selectedUser; 
  Map<String, dynamic>? _replyingTo;   
  List<dynamic> _chatHistory = []; 
  bool _isLoading = false, _isHistoryLoading = false;
  String _senderId = "", _senderName = "";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Lấy thông tin sinh viên từ máy
      _senderId = prefs.getString('user_code') ?? "";
      _senderName = prefs.getString('full_name') ?? "Sinh viên";
    });
  }

  void _selectUser(String id, String name) {
    setState(() {
      _selectedUser = {'id': id, 'name': name};
      _chatHistory = []; 
      _replyingTo = null;
      _searchController.clear(); 
    });
    FocusScope.of(context).unfocus(); 
    _loadHistoryForUser(id);
  }

  // Load lịch sử chat giữa SV và Cán bộ cụ thể
  Future<void> _loadHistoryForUser(String targetId) async {
    if (!mounted) return;
    setState(() => _isHistoryLoading = true);
    try {
      final response = await VinhUniClient.instance.get(
        "/api/lecturer/chat-history", 
        queryParameters: {"sender_id": _senderId, "target_id": targetId}
      );
      if (mounted) setState(() { _chatHistory = response.data['data'] ?? []; _isHistoryLoading = false; });
    } catch (e) { if (mounted) setState(() => _isHistoryLoading = false); }
  }

  Future<void> _handleSend() async {
    if (_messageController.text.trim().isEmpty || _selectedUser == null) return;
    setState(() => _isLoading = true);
    try {
      final msg = _messageController.text.trim();
      final body = {
        // GroupId 1-1 đồng bộ với Backend
        "group_id": "CONV_${[_senderId, _selectedUser!['id']].reduce((a, b) => a.compareTo(b) < 0 ? a : b)}",
        "sender_code": _senderId,
        "sender_name": _senderName,
        "message_content": msg,
        "target_id": _selectedUser!['id'],
        "role": _targetRole,
        "reply_to_id": _replyingTo?['message_id'],
      };

      // Gọi API gửi tin nhắn cá nhân
      final res = await VinhUniClient.instance.post('/api/admin/send-notification-individual', data: body);
      if (res.statusCode == 200) {
        _messageController.clear();
        setState(() => _replyingTo = null);
        _loadHistoryForUser(_selectedUser!['id']); 
      }
    } catch (e) { NotificationHelper.showSnack(context, "Lỗi: $e", Colors.red); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    const Color vinhUniBlue = Color(0xFF0054A6);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(_selectedUser != null ? _selectedUser!['name'] : "LIÊN HỆ CÁN BỘ", 
              style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
            if (_selectedUser != null)
              const Text("Kênh phản hồi trực tiếp", style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: vinhUniBlue, elevation: 0, centerTitle: true,
      ),
      body: Column(children: [
        _buildSearchArea(), 
        Expanded(child: _buildChatArea()), 
        _buildInputArea() 
      ]),
    );
  }

  // --- COMPONENT: TÌM KIẾM CÁN BỘ ---
  Widget _buildSearchArea() {
    return Container(
      color: const Color(0xFF0054A6), padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
      child: Autocomplete<UserSearchModel>(
        displayStringForOption: (o) => "${o.name} (${o.id})",
        optionsBuilder: (v) async {
          if (v.text.length < 2) return const Iterable.empty();
          final Completer<Iterable<UserSearchModel>> completer = Completer();
          if (_debounce?.isActive ?? false) _debounce!.cancel();
          _debounce = Timer(const Duration(milliseconds: 500), () async {
            final results = await _searchUsersApi(v.text);
            completer.complete(results);
          });
          return completer.future;
        },
        onSelected: (s) => _selectUser(s.id, s.name),
        fieldViewBuilder: (ctx, ctrl, focus, onSub) => TextField(
          controller: ctrl, focusNode: focus,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: "Nhập tên hoặc mã cán bộ...",
            hintStyle: const TextStyle(color: Colors.white60),
            prefixIcon: const Icon(Icons.search, color: Colors.white),
            filled: true, fillColor: Colors.white.withOpacity(0.15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0)
          ),
        ),
      ),
    );
  }

  Widget _buildChatArea() {
    if (_selectedUser == null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.support_agent_rounded, size: 80, color: Colors.blue.withOpacity(0.1)),
          const Text("Tìm cán bộ để bắt đầu phản hồi", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ));
    }
    if (_isHistoryLoading) return const Center(child: CircularProgressIndicator());
    
    return ListView.builder(
      reverse: true, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20), 
      itemCount: _chatHistory.length,
      itemBuilder: (context, index) {
        final item = _chatHistory[index];
        bool isMe = item['sender_code'] == _senderId;
        return _buildMessageItem(item, isMe);
      },
    );
  }

  Widget _buildMessageItem(dynamic item, bool isMe) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(isMe ? "Bạn" : (item['sender_name'] ?? "Cán bộ"), 
            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF0054A6) : Colors.white,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(2),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)]
            ),
            child: Text(item['message_content'] ?? "", 
              style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildInputArea() {
    if (_selectedUser == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 25),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: TextField(controller: _messageController, decoration: const InputDecoration(hintText: "Nhập nội dung phản hồi...", border: InputBorder.none))),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: const Color(0xFF0054A6),
          child: IconButton(onPressed: _isLoading ? null : _handleSend, icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
        ),
      ]),
    );
  }

  Future<Iterable<UserSearchModel>> _searchUsersApi(String q) async {
    try {
      final res = await VinhUniClient.instance.get("/api/admin/search-user", queryParameters: {"q": q, "role": _targetRole});
      final List<dynamic> data = res.data;
      return data.map((j) => UserSearchModel.fromJson(j));
    } catch (e) { return const Iterable.empty(); }
  }
}