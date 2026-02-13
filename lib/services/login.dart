import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // 👈 THÊM DÒNG NÀY ĐỂ HẾT LỖI debugPrint

class AuthService {
  // Domain của bạn
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn'; 

  Future<bool> login(String user, String pass) async {
    final loginUri = Uri.parse('$baseUrl/api/login');
    
    try {
      debugPrint("📡 --- DEBUG LOGIN START ---");
      debugPrint("📡 URL: $loginUri");
      debugPrint("📡 Data gửi đi: {'username': '${user.trim()}', 'password': '***'}");

      final response = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user.trim(),
          'password': pass.trim()
        }),
      ).timeout(const Duration(seconds: 15)); // Tăng timeout lên 15s cho chắc chắn

      debugPrint("📩 Mã phản hồi từ Server: ${response.statusCode}");
      debugPrint("📩 Nội dung Server trả về: ${response.body}");

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
          final data = jsonResponse['data'];
          final prefs = await SharedPreferences.getInstance();
          
          // Lưu thông tin người dùng
          await prefs.setString('user_id', data['student_id'].toString());
          await prefs.setString('full_name', data['full_name'] ?? "Sinh viên");
          
          debugPrint("✅ Đăng nhập thành công: ${data['full_name']}");
          return true;
        }
      } else if (response.statusCode == 401) {
        debugPrint("❌ Lỗi: Sai tài khoản hoặc mật khẩu (401)");
      } else {
        debugPrint("❌ Lỗi hệ thống: Status Code ${response.statusCode}");
      }
      return false;
    } catch (e) {
      debugPrint("🔥 LỖI KẾT NỐI (FATAL): $e");
      return false;
    }
  }
}