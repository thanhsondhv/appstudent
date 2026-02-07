import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminNotificationPage extends StatefulWidget {
  @override
  _AdminNotificationPageState createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  String _selectedType = "Toàn trường";
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isLoading = false;

  // Lưu ý: Thay đổi URL này cho khớp với Backend của bạn
  final String domain = "http://localhost:8080"; 

  Future<void> _handleSend() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Vui lòng nhập đủ nội dung")));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$domain/api/admin/send-notification'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "title": _titleController.text,
          "content": _contentController.text,
          "type": _selectedType,
          "target": _targetController.text.trim(),
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 Đã gửi thành công!")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🔥 Lỗi: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gửi thông báo"), backgroundColor: const Color(0xFF0056b3)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedType,
              items: ["Toàn trường", "Khóa", "Lớp hành chính", "Lớp học phần", "Sinh viên cụ thể"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() { _selectedType = val!; _targetController.clear(); }),
              decoration: const InputDecoration(labelText: "Đối tượng", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            if (_selectedType != "Toàn trường")
              TextField(controller: _targetController, decoration: const InputDecoration(labelText: "Mã đối tượng", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: "Tiêu đề", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: _contentController, maxLines: 5, decoration: const InputDecoration(labelText: "Nội dung", border: OutlineInputBorder())),
            const SizedBox(height: 25),
            _isLoading ? const CircularProgressIndicator() : SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _handleSend,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0056b3)),
                child: const Text("XÁC NHẬN GỬI", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }
}