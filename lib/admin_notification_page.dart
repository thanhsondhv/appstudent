import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  _AdminNotificationPageState createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _targetIdController = TextEditingController();

  final String domain = "https://mobi.vinhuni.edu.vn/api/admin"; // Đổi IP khi chạy thật

  String selectedType = 'Toàn trường';
  String? selectedTargetId;
  List<dynamic> targetList = [];
  bool isLoadingTarget = false;
  bool isSending = false;

  final List<String> notificationTypes = [
    'Toàn trường',
    'Khoa',
    'Lớp HP',
    'Lớp HC',
    'Sinh viên'
  ];

  // Hàm lấy danh sách động dựa trên loại thông báo
  Future<void> _fetchTargetList(String type) async {
    String endpoint = "";
    if (type == 'Khoa') endpoint = "/get-departments";
    else if (type == 'Lớp HP') endpoint = "/get-course-sections";
    else if (type == 'Lớp HC') endpoint = "/get-admin-classes";
    else {
      setState(() { targetList = []; selectedTargetId = null; });
      return;
    }

    setState(() => isLoadingTarget = true);
    try {
      final response = await http.get(Uri.parse('$domain$endpoint'));
      if (response.statusCode == 200) {
        setState(() {
          targetList = json.decode(response.body);
          selectedTargetId = null; // Reset khi đổi loại
        });
      }
    } catch (e) {
      _showSnackBar("Lỗi tải danh sách: $e", Colors.red);
    } finally {
      setState(() => isLoadingTarget = false);
    }
  }

  // Hàm gửi dữ liệu về Server
  Future<void> _submitNotification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSending = true);
    try {
      final response = await http.post(
        Uri.parse('$domain/send-notification'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "title": _titleController.text,
          "content": _contentController.text,
          "type": selectedType,
          "target_id": selectedType == 'Sinh viên' ? _targetIdController.text : selectedTargetId,
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar("Đã đẩy thông báo vào hàng đợi!", Colors.green);
        Navigator.pop(context); // Quay lại sau khi gửi
      } else {
        _showSnackBar("Gửi thất bại!", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Lỗi kết nối: $e", Colors.red);
    } finally {
      setState(() => isSending = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gửi thông báo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0056b3),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel("Tiêu đề thông báo"),
              TextFormField(
                controller: _titleController,
                decoration: _inputStyle("Nhập tiêu đề ngắn gọn..."),
                validator: (v) => v!.isEmpty ? "Vui lòng nhập tiêu đề" : null,
              ),
              const SizedBox(height: 20),
              
              _buildLabel("Loại đối tượng nhận tin"),
              DropdownButtonFormField<String>(
                value: selectedType,
                items: notificationTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) {
                  setState(() => selectedType = v!);
                  _fetchTargetList(v!);
                },
                decoration: _inputStyle("Chọn loại..."),
              ),
              const SizedBox(height: 20),

              // UI thay đổi linh hoạt dựa trên lựa chọn
              if (selectedType == 'Khoa' || selectedType == 'Lớp HP' || selectedType == 'Lớp HC')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Chọn cụ thể"),
                    isLoadingTarget 
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: selectedTargetId,
                          items: targetList.map((e) => DropdownMenuItem(
                            value: e['id'].toString(), 
                            child: Text(e['name'], style: const TextStyle(fontSize: 13))
                          )).toList(),
                          onChanged: (v) => setState(() => selectedTargetId = v),
                          decoration: _inputStyle("Chọn từ danh sách..."),
                          validator: (v) => v == null ? "Vui lòng chọn đối tượng" : null,
                        ),
                    const SizedBox(height: 20),
                  ],
                ),

              if (selectedType == 'Sinh viên')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Mã sinh viên nhận tin"),
                    TextFormField(
                      controller: _targetIdController,
                      decoration: _inputStyle("Ví dụ: 205714..."),
                      validator: (v) => v!.isEmpty ? "Nhập mã SV" : null,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),

              _buildLabel("Nội dung chi tiết"),
              TextFormField(
                controller: _contentController,
                maxLines: 5,
                decoration: _inputStyle("Nhập nội dung thông báo..."),
                validator: (v) => v!.isEmpty ? "Vui lòng nhập nội dung" : null,
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isSending ? null : _submitNotification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0056b3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: isSending 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("GỬI THÔNG BÁO NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
  );

  InputDecoration _inputStyle(String hint) => InputDecoration(
    hintText: hint,
    fillColor: Colors.grey[50],
    filled: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
  );
}