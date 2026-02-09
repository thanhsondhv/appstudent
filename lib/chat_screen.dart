import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatScreen extends StatefulWidget {
  final String studentId;
  const ChatScreen({super.key, required this.studentId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  
  // Danh sách các câu hỏi gợi ý từ AI
  List<String> _currentSuggestions = [];
  int _sessionId = 0; 
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Chủ động gọi AI chào hỏi khi sinh viên vừa mở Tab
    _sendInitialGreeting();
  }

  void _sendInitialGreeting() {
    _sendMessage("INITIAL_GREETING", isSilent: true);
  }

  // Gửi tin nhắn tới backend Python
  Future<void> _sendMessage(String text, {bool isSilent = false}) async {
    if (text.trim().isEmpty) return;

    setState(() {
      // isSilent dùng để ẩn tin nhắn mồi (như INITIAL_GREETING) khỏi UI
      if (!isSilent) {
        _messages.add({"role": "user", "content": text});
      }
      _isTyping = true;
      _currentSuggestions = []; // Tạm ẩn gợi ý khi đang gửi
    });
    
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": text,
          "sessionId": _sessionId, 
          "studentId": widget.studentId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _messages.add({"role": "assistant", "content": data['mainReply']});
          _sessionId = data['sessionId'];
          
          // Cập nhật các gợi ý mới từ AI
          if (data['suggestions'] != null) {
            _currentSuggestions = List<String>.from(data['suggestions']);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add({"role": "assistant", "content": "⚠️ Lỗi kết nối AI. Vui lòng thử lại!"});
      });
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(15),
            itemCount: _messages.length,
            itemBuilder: (context, index) => _buildBubble(_messages[index]),
          ),
        ),
        
        if (_isTyping) const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator()),
        
        // Hiển thị danh sách gợi ý
        if (!_isTyping && _currentSuggestions.isNotEmpty) _buildSuggestions(),
        
        _buildInputArea(),
      ],
    );
  }

  // Widget hiển thị các Thẻ gợi ý cuộn ngang
  Widget _buildSuggestions() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _currentSuggestions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(_currentSuggestions[index], style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF0056b3)),
              onPressed: () => _sendMessage(_currentSuggestions[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg) {
    bool isUser = msg["role"] == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0056b3) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: isUser ? const Radius.circular(15) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(15),
          ),
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
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
                  decoration: const InputDecoration(hintText: "Nhập câu hỏi của bạn...", border: InputBorder.none),
                  onSubmitted: (val) => _sendMessage(val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF0056b3),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: () => _sendMessage(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}