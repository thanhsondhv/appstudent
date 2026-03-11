import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final GlobalKey<ChatScreenState> chatScreenKey = GlobalKey<ChatScreenState>();

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 🔥 Giữ nguyên kiểu dữ liệu List<Map> để khớp với UI hiện tại của bạn
  final List<Map<String, String>> _messages = [];
  List<String> _suggestions = [];

  int _sessionId = 0;
  bool _isTyping = false;
  String? _currentStudentId;
  bool _isLoadingId = true;
  String? _errorMessage;
  bool _hasConsented = false;

  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Uri _privacyUrl = Uri.parse('https://mobi.vinhuni.edu.vn/privacy-policy');

  @override
  void initState() {
    super.initState();
    _initChatData();
    _checkInitialConsent();
  }

  // --- LOGIC KHỞI TẠO & BẢO MẬT ---

  Future<void> _checkInitialConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _hasConsented = prefs.getBool('ai_consented') ?? false);
    }
  }

  Future<void> _initChatData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');
      if (userId == null) {
        setState(() {
          _errorMessage = "Phiên đăng nhập hết hạn, vui lòng đăng nhập lại!";
          _isLoadingId = false;
        });
        return;
      }
      setState(() {
        _currentStudentId = userId;
        _isLoadingId = false;
      });

      // 🔥 Bổ sung: Tự động tải lịch sử ngay sau khi lấy được StudentId
      _loadChatHistory(userId);

    } catch (e) {
      debugPrint("❌ Lỗi khởi tạo Chat: $e");
    }
  }

  // 🔥 TÍNH NĂNG MỚI: Tải lịch sử từ Server
  Future<void> _loadChatHistory(String studentIdStr) async {
    try {
      final response = await http.get(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot-v2/history/$studentIdStr")
      );
      
      if (response.statusCode == 200) {
        // Giải mã utf8 để tránh lỗi font tiếng Việt
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List rawHistory = data['history'] ?? [];
        
        if (mounted) {
          setState(() {
            _messages.clear();
            for (var item in rawHistory) {
              _messages.add({
                "role": item['role']?.toString() ?? "assistant",
                "content": item['content']?.toString() ?? ""
              });
            }
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi tải lịch sử chat: $e");
    }
  }

  Future<void> _launchUrl() async {
    if (!await launchUrl(_privacyUrl, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $_privacyUrl');
    }
  }

  // --- POPUP XÁC NHẬN (GIỮ NGUYÊN) ---

  void _showConsentPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Icon(Icons.security_outlined, size: 48, color: vinhUniBlue),
              const SizedBox(height: 12),
              const Text("Minh bạch Dữ liệu AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Ứng dụng sử dụng công nghệ RAG kết hợp với Trợ lý AI để hỗ trợ bạn:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 15),
                _buildConsentPoint(Icons.storage, "Dữ liệu học tập cá nhân được truy vấn an toàn từ SQL nội bộ."),
                _buildConsentPoint(Icons.enhanced_encryption, "Thông tin định danh được bảo mật và KHÔNG chia sẻ."),
                _buildConsentPoint(Icons.bolt, "AI của OpenAI chỉ nhận nội dung câu hỏi để tổng hợp câu trả lời."),
                const SizedBox(height: 15),
                const Text(
                  "Bạn có đồng ý sử dụng dịch vụ này không?",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Từ chối")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('ai_consented', true);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() => _hasConsented = true);
                  _sendHello();
                }
              },
              child: const Text("Tôi Đồng Ý", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: vinhUniBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }

  // --- LOGIC NHẮN TIN (GIỮ NGUYÊN) ---

  Future<void> _sendHello() async {
    if (_currentStudentId == null) return;
    final prefs = await SharedPreferences.getInstance();
    String fullName = prefs.getString('full_name') ?? "Sinh viên";
    setState(() => _isTyping = true);

    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot-v2/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": "INITIAL_GREETING",
          "sessionId": 0,
          "studentId": _currentStudentId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add({"role": "assistant", "content": data['mainReply'] ?? "Xin chào $fullName!"});
          _suggestions = List<String>.from(data['suggestions'] ?? []);
          _sessionId = data['sessionId'] ?? 0;
        });
      }
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _currentStudentId == null) return;
    final userMessage = text.trim();
    setState(() {
      _messages.add({"role": "user", "content": userMessage});
      _isTyping = true;
      _suggestions = [];
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/chatbot-v2/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": userMessage,
          "sessionId": _sessionId,
          "studentId": _currentStudentId
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add({"role": "assistant", "content": data['mainReply'] ?? ""});
          _suggestions = List<String>.from(data['suggestions'] ?? []);
          _sessionId = data['sessionId'] ?? _sessionId;
        });
      }
    } catch (e) {
      setState(() => _messages.add({"role": "assistant", "content": "⚠️ Kết nối gián đoạn, bạn thử lại nhé!"}));
    } finally {
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    }
  }

  void activateChatTab() {
    debugPrint("🚀 Tab Chat đã được kích hoạt từ HomeScreen");
    if (!_hasConsented) {
      _showConsentPopup();
    } else {
      if (_messages.isEmpty) {
        _sendHello();
      } else {
        // Nếu đã có tin nhắn, hãy cuộn xuống cuối để SV dễ theo dõi
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // --- UI WIDGETS ---

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 25, left: 12, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                children: [
                  const TextSpan(text: "Dữ liệu được xử lý bởi OpenAI. Xem "),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: _launchUrl,
                      child: Text(
                        "Chính sách bảo mật",
                        style: TextStyle(fontSize: 10, color: vinhUniBlue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                  const TextSpan(text: " để biết cách chúng tôi bảo vệ bạn."),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(24)),
                  child: TextField(
                    controller: _controller,
                    maxLines: 4, minLines: 1,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(hintText: "Nhập câu hỏi...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                    onSubmitted: (val) => _sendMessage(val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18, backgroundColor: vinhUniBlue,
                child: IconButton(icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18), onPressed: () => _sendMessage(_controller.text)),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildBubble(Map<String, String> msg) {
    bool isUser = msg["role"] == "user";
    String content = msg["content"] ?? "";

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // 🔥 CẬP NHẬT: Nhấn giữ để sao chép tin nhắn
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Đã sao chép nội dung tin nhắn"),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating, // Hiển thị dạng nổi hiện đại
              margin: EdgeInsets.only(bottom: 100, left: 20, right: 20),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          decoration: BoxDecoration(
            color: isUser ? vinhUniBlue : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: MarkdownBody(
            data: content,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: isUser ? Colors.white : const Color(0xFF2D3142), fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingId) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_errorMessage != null) return Scaffold(body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))));
    
    if (!_hasConsented) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_awesome, size: 80, color: vinhUniBlue),
              const SizedBox(height: 24),
              const Text("Trợ lý AI VinhUni", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                "Để tiếp tục, vui lòng xác nhận sự đồng ý của bạn về việc sử dụng công nghệ AI hỗ trợ học tập.",
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _showConsentPopup,
                child: const Text("Xác nhận & Bắt đầu", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ]),
          ),
        ),
      );
    }
  return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), 
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          automaticallyImplyLeading: false, 
          title: const Text("Trợ lý Học tập AI", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          backgroundColor: vinhUniBlue,
          foregroundColor: Colors.white,
          centerTitle: true, elevation: 0,
          actions: [
            IconButton(onPressed: () => _loadChatHistory(_currentStudentId!), icon: const Icon(Icons.refresh, size: 20))
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _messages.isEmpty && !_isTyping
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(15),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _buildBubble(_messages[index]),
                    ),
            ),
            if (_isTyping) const LinearProgressIndicator(minHeight: 2, color: Color(0xFF0054A6)),
            _buildSuggestionsArea(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }
  Widget _buildSuggestionsArea() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 45,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _suggestions.length,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ActionChip(
            label: Text(_suggestions[i], style: TextStyle(fontSize: 12, color: vinhUniBlue)),
            backgroundColor: Colors.blue.shade50,
            onPressed: () => _sendMessage(_suggestions[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text("Bắt đầu đặt câu hỏi với Trợ lý AI", style: TextStyle(color: Colors.grey)),
      ]),
    );
  }
}