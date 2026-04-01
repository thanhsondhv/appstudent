import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart';

class SendIndividualScreen extends StatefulWidget {
  const SendIndividualScreen({super.key});

  @override
  State<SendIndividualScreen> createState() => _SendIndividualScreenState();
}

class _SendIndividualScreenState extends State<SendIndividualScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tempBulkController = TextEditingController(); // Hứng dữ liệu dán dấu phẩy
  
  List<dynamic> _customGroupList = [];
  String? _selectedCustomGroup;
  List<Map<String, dynamic>> _verifiedStudents = []; // Danh sách người nhận cuối cùng
  bool _isLoading = false;
  String _senderId = "";

  @override
  void initState() {
    super.initState();
    _loadSender();
  }

  Future<void> _loadSender() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _senderId = prefs.getString('user_code') ?? ""; });
    _loadCustomGroups();
  }

  // --- LOGIC NHÓM ẢO ---
  Future<void> _loadCustomGroups() async {
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/custom-groups/$_senderId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _customGroupList = data['data'] ?? []; });
      }
    } catch (e) { debugPrint("Lỗi tải nhóm ảo"); }
  }

  Future<void> _fetchGroupMembers(String groupId) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/custom-group-members/$groupId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (var sv in data['data']) {
          _addStudentToVerified(sv['id'].toString(), sv['name'].toString());
        }
      }
    } catch (e) {}
    setState(() => _isLoading = false);
  }

  // --- LOGIC TÌM KIẾM & XÁC MINH ---
  void _addStudentToVerified(String id, String name) {
    if (!_verifiedStudents.any((e) => e['id'] == id)) {
      setState(() { _verifiedStudents.add({'id': id, 'name': name}); });
    }
  }

  Future<void> _verifyBulk(String input) async {
    if (input.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/check-multiple-users?q=${Uri.encodeComponent(input)}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (var sv in data['data']) {
          _addStudentToVerified(sv['id'].toString(), sv['name'].toString());
        }
        _tempBulkController.clear();
        NotificationHelper.showSnack(context, "Đã thêm ${data['data'].length} người vào danh sách", Colors.green);
      }
    } catch (e) { NotificationHelper.showSnack(context, "Lỗi kiểm tra danh sách", Colors.red); }
    setState(() => _isLoading = false);
  }

  Future<void> _handleSend() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty || _verifiedStudents.isEmpty) {
      NotificationHelper.showSnack(context, "Vui lòng nhập đủ nội dung và người nhận!", Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final body = {
        "sender_id": _senderId,
        "scope": "INDIVIDUAL",
        "target_id": _verifiedStudents.map((e) => e['id']).join(","),
        "category": "GENERAL",
        "title": _titleController.text,
        "content": _contentController.text,
      };
      final res = await http.post(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/admin/send-notification-individual'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body)
      );
      if (res.statusCode == 200) {
        NotificationHelper.showSnack(context, "Gửi thành công!", Colors.green);
        Navigator.pop(context); // Quay lại portal để xem lịch sử
      }
    } catch (e) { NotificationHelper.showSnack(context, "Lỗi kết nối", Colors.red); }
    finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("GỬI CHO CÁ NHÂN", style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0054A6),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("1. Chọn người nhận", Icons.person_add_rounded),
            
            // --- NHÓM ẢO ---
            NotificationHelper.buildLabel("Từ nhóm ảo đã lưu"),
            NotificationHelper.buildDropdown(
              hint: "Chọn nhóm của bạn",
              items: _customGroupList.map((e) => e['id'].toString()).toList(),
              value: _selectedCustomGroup,
              onChanged: (v) { setState(() => _selectedCustomGroup = v); _fetchGroupMembers(v!); },
              displayFunc: (id) => _customGroupList.firstWhere((e) => e['id'].toString() == id)['name'],
            ),
            
            const SizedBox(height: 15),
            
            // --- TÌM KIẾM CÁ NHÂN / DÁN LIST ---
            NotificationHelper.buildLabel("Tìm lẻ hoặc dán mã (cách nhau dấu phẩy)"),
            Row(
              children: [
                Expanded(
                  child: Autocomplete<UserSearchModel>(
                    displayStringForOption: (o) => "${o.name} (${o.id})",
                    optionsBuilder: (v) async => v.text.length < 2 ? const Iterable.empty() : await _searchUsersApi(v.text),
                    onSelected: (s) => _addStudentToVerified(s.id, s.name),
                    fieldViewBuilder: (ctx, ctrl, focus, onSub) => TextField(
                      controller: ctrl, focusNode: focus,
                      onChanged: (v) => _tempBulkController.text = v,
                      decoration: NotificationHelper.inputDecor("Nhập tên/MSV/Mã CB...", Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _verifyBulk(_tempBulkController.text),
                  icon: const Icon(Icons.add_task_rounded, color: Colors.blue, size: 32),
                )
              ],
            ),

            // --- DANH SÁCH ĐÃ CHỌN (CHIPS) ---
            if (_verifiedStudents.isNotEmpty) _buildSelectedList(),

            const Divider(height: 40),
            _buildSectionTitle("2. Nội dung thông báo", Icons.mail_outline_rounded),
            TextField(controller: _titleController, decoration: NotificationHelper.inputDecor("Tiêu đề thông báo", Icons.title)),
            const SizedBox(height: 12),
            TextField(controller: _contentController, maxLines: 4, decoration: NotificationHelper.inputDecor("Nội dung chi tiết...", Icons.message)),
            
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton.icon(
                onPressed: _handleSend,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text("GỬI THÔNG BÁO NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0054A6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- WIDGETS PHỤ TRỢ ---

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(children: [Icon(icon, color: Colors.blueGrey, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey))]),
    );
  }

  Widget _buildSelectedList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Đã chọn ${_verifiedStudents.length} người", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
            TextButton(onPressed: () => setState(() => _verifiedStudents.clear()), child: const Text("Xóa hết", style: TextStyle(color: Colors.red, fontSize: 12))),
          ],
        ),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.shade50.withOpacity(0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
          child: Wrap(
            spacing: 8, runSpacing: 4,
            children: _verifiedStudents.map((sv) => Chip(
              label: Text("${sv['name']} (${sv['id']})", style: const TextStyle(fontSize: 10)),
              onDeleted: () => setState(() => _verifiedStudents.remove(sv)),
              deleteIconColor: Colors.red,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(onPressed: _showSaveGroupDialog, icon: const Icon(Icons.save_as_rounded, size: 18), label: const Text("Lưu danh sách này thành nhóm ảo")),
      ],
    );
  }

  Future<void> _showSaveGroupDialog() async {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Tên nhóm ảo mới", style: TextStyle(fontSize: 16)),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "VD: Nhóm SV nghiên cứu khoa học")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
        ElevatedButton(onPressed: () { _saveGroup(ctrl.text); Navigator.pop(ctx); }, child: const Text("Lưu lại")),
      ],
    ));
  }

  Future<void> _saveGroup(String name) async {
    if (name.isEmpty) return;
    try {
      final res = await http.post(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/create-custom-group"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"group_name": name, "sender_id": _senderId, "student_ids": _verifiedStudents.map((e) => e['id']).join(",")})
      );
      if (res.statusCode == 200) { NotificationHelper.showSnack(context, "Đã tạo nhóm ảo thành công!", Colors.green); _loadCustomGroups(); }
    } catch (e) {}
  }

  Future<Iterable<UserSearchModel>> _searchUsersApi(String q) async {
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/search-user?q=${Uri.encodeComponent(q)}"));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((j) => UserSearchModel.fromJson(j));
      }
    } catch (e) {}
    return const Iterable.empty();
  }
}