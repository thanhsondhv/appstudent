import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  int _sessionId = 0;
  bool _isTyping = false;
  String? _currentStudentId;
  bool _isLoadingId = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  /// Khởi tạo và gửi lời chào tự động
  Future<void> _initChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');

      if (userId == null) {
        setState(() {
          _errorMessage = "Vui lòng đăng nhập để sử dụng chức năng này!";
          _isLoadingId = false;
        });
        return;
      }

      setState(() {
        _currentStudentId = userId;
        _isLoadingId = false;
      });

      // --- THÊM MỚI: Tự động gửi tín hiệu chào ---
      _sendHello(); 

    } catch (e) {
      setState(() {
        _errorMessage = "Lỗi khởi tạo: $e";
        _isLoadingId = false;
      });
    }
  }

  /// Hàm gửi tín hiệu chào (Không hiển thị tin nhắn người dùng lên UI)
  Future<void> _sendHello() async {
    if (_currentStudentId == null) return;
    
    setState(() => _isTyping = true); // Hiện trạng thái đang nhập...

    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": "INITIAL_GREETING", // Tín hiệu đặc biệt cho Backend
          "sessionId": 0,
          "studentId": _currentStudentId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _messages.add({
              "role": "assistant",
              "content": data['mainReply'] ?? "Xin chào! Mình có thể giúp gì cho bạn?"
            });
            _sessionId = data['sessionId'] ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Lỗi gửi lời chào: $e");
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _currentStudentId == null) return;

    final userMessage = text.trim();
    setState(() {
      _messages.add({"role": "user", "content": userMessage});
      _isTyping = true;
    });

    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": userMessage,
          "sessionId": _sessionId,
          "studentId": _currentStudentId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add({
            "role": "assistant",
            "content": data['mainReply'] ?? "Mình không nhận được câu trả lời."
          });
          _sessionId = data['sessionId'] ?? _sessionId;
        });
      } else {
        throw Exception("Lỗi server (${response.statusCode})");
      }
    } catch (e) {
      setState(() {
        _messages.add({
          "role": "assistant",
          "content": "⚠️ Không thể kết nối với AI. Vui lòng kiểm tra lại mạng!"
        });
      });
    } finally {
      if (mounted) {
        setState(() => _isTyping = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chatbot Vinh Uni"),
        backgroundColor: const Color(0xFF0056b3),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingId) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isTyping
                ? _buildEmptyState() // Chỉ hiện nếu chưa có lời chào
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(15),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildBubble(_messages[index]),
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: LinearProgressIndicator(minHeight: 2, color: Color(0xFF0056b3)),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  // Widget hiển thị khi chưa có tin nhắn (Có thể sẽ ít hiện vì lời chào load rất nhanh)
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("Đang kết nối với trợ lý ảo...", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg) {
    bool isUser = msg["role"] == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0056b3) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isUser ? 15 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 15),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
          ],
        ),
        child: MarkdownBody(
          data: msg["content"]!,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: "Hỏi về lịch học, điểm số...",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) _sendMessage(val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF0056b3)),
              onPressed: () => _sendMessage(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}