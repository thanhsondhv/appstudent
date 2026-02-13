import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  String studentName = "Sinh viên";
  String studentId = "";
  bool isNotifEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentName = prefs.getString('full_name') ?? "Sinh viên";
      studentId = prefs.getString('user_id') ?? "---";
      isNotifEnabled = prefs.getBool('receive_notifications') ?? true;
    });
  }

  void _toggleNotification(bool value) async {
    setState(() => isNotifEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('receive_notifications', value);

    if (value) {
      await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      _showMessage("Đã BẬT nhận thông báo từ trường");
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic("vinhuni_all_students");
      _showMessage("Đã TẮT nhận thông báo");
    }
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Đổi mật khẩu"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Mật khẩu cũ")),
            const SizedBox(height: 10),
            TextField(controller: newPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Mật khẩu mới")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              await _changePassword(oldPassCtrl.text, newPassCtrl.text);
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(String oldPass, String newPass) async {
    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/change-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": studentId, "old_pass": oldPass, "new_pass": newPass}),
      );
      final res = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showMessage("✅ Đổi mật khẩu thành công!");
      } else {
        _showMessage("⚠️ ${res['message']}");
      }
    } catch (e) {
      _showMessage("Lỗi kết nối server");
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text("Tài khoản", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header Info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  CircleAvatar(radius: 30, backgroundColor: vinhUniBlue.withOpacity(0.1), child: Icon(Icons.person, size: 35, color: vinhUniBlue)),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text("MSV: $studentId", style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 25),
            
            const Align(alignment: Alignment.centerLeft, child: Text("CÀI ĐẶT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  SwitchListTile(
                    activeColor: vinhUniBlue,
                    secondary: const Icon(Icons.notifications_active_outlined, color: Colors.orange),
                    title: const Text("Nhận thông báo"),
                    subtitle: const Text("Tin tức từ trường và giảng viên"),
                    value: isNotifEnabled,
                    onChanged: _toggleNotification,
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(Icons.lock_outline, "Đổi mật khẩu", Colors.blue, onTap: _showChangePasswordDialog),
                  const Divider(height: 1),
                  _buildMenuTile(Icons.fingerprint, "Sinh trắc học (Vân tay/FaceID)", Colors.purple, onTap: () => _showMessage("Tính năng đang phát triển")),
                ],
              ),
            ),

            const SizedBox(height: 25),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  _buildMenuTile(Icons.info_outline, "Giới thiệu ứng dụng", Colors.teal, onTap: () {}),
                  const Divider(height: 1),
                  _buildMenuTile(Icons.logout, "Đăng xuất", Colors.red, onTap: _logout, showArrow: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, Color color, {VoidCallback? onTap, bool showArrow = true}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: showArrow ? const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey) : null,
      onTap: onTap,
    );
  }
}