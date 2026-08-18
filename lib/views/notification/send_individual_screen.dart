import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart'; //
import '../../services/vinhuni_api_client.dart'; //

class SendIndividualScreen extends StatefulWidget {
  const SendIndividualScreen({super.key});
  @override
  State<SendIndividualScreen> createState() => _SendIndividualScreenState();
}

class _SendIndividualScreenState extends State<SendIndividualScreen> {
  final _messageController = TextEditingController();
  final _searchController = TextEditingController(); // Controller riêng cho tìm kiếm
  Timer? _debounce; 
  
  String _targetRole = "SINHVIEN"; 
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
      _senderId = prefs.getString('user_code') ?? "";
      _senderName = prefs.getString('full_name') ?? "Cán bộ";
    });
  }

  // 🔥 1. HÀM CHỌN NGƯỜI & CLEAR TEXT TÌM KIẾM
  void _selectUser(String id, String name) {
    setState(() {
      _selectedUser = {'id': id, 'name': name};
      _chatHistory = []; 
      _replyingTo = null;
      _searchController.clear(); // 👈 XÓA TRẮNG Ô TÌM KIẾM NGAY KHI CHỌN
    });
    FocusScope.of(context).unfocus(); // Đóng bàn phím tìm kiếm
    _loadHistoryForUser(id);
  }

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
        "group_id": "CONV_${[_senderId, _selectedUser!['id']].reduce((a, b) => a.compareTo(b) < 0 ? a : b)}",
        "sender_code": _senderId,
        "sender_name": _senderName,
        "message_content": msg,
        "target_id": _selectedUser!['id'],
        "role": _targetRole,
        "reply_to_id": _replyingTo?['message_id'],
      };

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
        // 🔥 NÚT BACK MÀU TRẮNG
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(_selectedUser != null ? _selectedUser!['name'] : "TƯƠNG TÁC CÁ NHÂN", 
              style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
            if (_selectedUser != null)
              Text("Đang kết nối với ${_selectedUser!['id']}", style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: vinhUniBlue, elevation: 0,
        centerTitle: true,
      ),
      body: Column(children: [
        _buildSearchArea(), 
        Expanded(child: _buildChatArea()), 
        _buildInputArea() 
      ]),
    );
  }

  Widget _buildSearchArea() {
    return Container(
      color: const Color(0xFF0054A6), padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
      child: Column(children: [
        _buildRoleTabs(),
        const SizedBox(height: 10),
        Autocomplete<UserSearchModel>(
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
          fieldViewBuilder: (ctx, ctrl, focus, onSub) {
            // Liên kết searchController để có thể clear() từ bên ngoài
            if (_searchController.text.isEmpty && ctrl.text.isNotEmpty) {
              // Đồng bộ nếu cần
            }
            return TextField(
              controller: ctrl, focusNode: focus,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (v) => _searchController.text = v,
              decoration: InputDecoration(
                hintText: "Tìm ${_targetRole == 'SINHVIEN' ? 'Sinh viên' : 'Cán bộ'}...",
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                suffixIcon: ctrl.text.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white54, size: 18),
                  onPressed: () => ctrl.clear(),
                ) : null,
                filled: true, fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0)
              ),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildRoleTabs() {
    return Row(children: [
      _roleTab("SINH VIÊN", "SINHVIEN"), const SizedBox(width: 10), _roleTab("CÁN BỘ", "CANBO"),
    ]);
  }

  Widget _roleTab(String label, String value) {
    bool active = _targetRole == value;
    return GestureDetector(
      onTap: () => setState(() { _targetRole = value; _selectedUser = null; _chatHistory = []; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        decoration: BoxDecoration(color: active ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: active ? const Color(0xFF0054A6) : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // 🔥 2. GIAO DIỆN CHAT BUBBLES CĂN 2 BÊN
  Widget _buildChatArea() {
    if (_selectedUser == null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 80, color: Colors.blue.withOpacity(0.1)),
          const Text("Chọn một cuộc hội thoại để bắt đầu", style: TextStyle(color: Colors.grey, fontSize: 13)),
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

        return Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Hiển thị tên người gửi (Căn 2 bên)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(isMe ? "Bạn" : (item['sender_name'] ?? "Đối phương"), 
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            GestureDetector(
              onLongPress: () => setState(() => _replyingTo = item),
              child: Align(
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item['reply_to'] != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                          child: Text("↩️ ${item['reply_to']}", style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54, fontStyle: FontStyle.italic), maxLines: 2),
                        ),
                      Text(item['message_content'] ?? "", 
                        style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14, height: 1.3)),
                      const SizedBox(height: 4),
                      Text(item['time'] ?? "", 
                        style: TextStyle(fontSize: 9, color: isMe ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w300)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _buildInputArea() {
    if (_selectedUser == null) return const SizedBox();
    
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 25), // Padding dưới để tránh phím ảo
      decoration: BoxDecoration(
        color: Colors.white, 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]
      ),
      child: Column(
        children: [
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 18, color: Color(0xFF0054A6)),
                  const SizedBox(width: 10),
                  Expanded(child: Text("Trả lời: ${_replyingTo!['message_content']}", style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyingTo = null))
                ],
              ),
            ),
          Row(children: [
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(25)),
              child: TextField(
                controller: _messageController, 
                maxLines: 4, minLines: 1, 
                decoration: const InputDecoration(hintText: "Nhập tin nhắn...", border: InputBorder.none, hintStyle: TextStyle(fontSize: 14, color: Colors.grey))
              ),
            )),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF0054A6),
              child: IconButton(
                onPressed: _isLoading ? null : _handleSend, 
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20)
              ),
            ),
          ]),
        ],
      ),
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