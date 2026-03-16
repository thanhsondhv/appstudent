import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';

class AuthService {
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn';
  final LocalAuthentication _localAuth = LocalAuthentication();

  // --- 1. ĐĂNG NHẬP BẰNG MẬT KHẨU ---
  Future<Map<String, dynamic>?> login(String user, String pass) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user.trim(), 'password': pass.trim()}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
          // Lưu dữ liệu vào máy
          await _saveUserSession(jsonResponse['data']);
          return jsonResponse['data'];
        }
      }
      return null;
    } catch (e) {
      debugPrint("🔥 Lỗi login: $e");
      return null;
    }
  }

  // --- 2. XÁC THỰC FACE ID CỦA MÁY (DEVICE AUTH) ---
  Future<bool> authenticateWithDevice() async {
    try {
      bool canCheck = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canCheck) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Vui lòng xác thực để truy cập VinhUni App',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true, useErrorDialogs: true),
        authMessages: [
          const IOSAuthMessages(cancelButton: 'Hủy', lockOut: 'Vui lòng bật lại Face ID'),
          const AndroidAuthMessages(signInTitle: 'Xác thực VinhUni', cancelButton: 'Hủy'),
        ],
      );
    } catch (e) { return false; }
  }

  // --- 3. ĐĂNG NHẬP FACE PRO (QUÉT AI) ---
  Future<Map<String, dynamic>> loginByFacePro({required File frontFile}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/api/login_by_face_pro"));
      request.files.add(await http.MultipartFile.fromPath('photo_front', frontFile.path));
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'SUCCESS' && data['user_data'] != null) {
          await _saveUserSession(data['user_data']);
        }
        return data;
      }
      return {"status": "ERROR", "message": "Lỗi Server AI"};
    } catch (e) { return {"status": "ERROR", "message": "Lỗi kết nối"}; }
  }

  // --- 4. LƯU PHIÊN ĐĂNG NHẬP ---
  Future<void> _saveUserSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    // numericId (1679) dùng để hiện ảnh/thông báo
    String rawId = data['user_code']?.toString() ?? data['student_id']?.toString() ?? "";
    String numericId = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericId.isEmpty) numericId = rawId;

    // username (ntson) dùng để gửi lên API login
    String userName = data['user_name']?.toString() ?? "";

    await prefs.setString('user_code', numericId); 
    await prefs.setString('user_name', userName);  
    await prefs.setString('full_name', data['full_name'] ?? "Người dùng");
    await prefs.setString('user_role', data['user_role'] ?? data['role'] ?? "SinhVien");
    await prefs.setBool('is_logged_in', true);
    
    debugPrint("✅ Session: numericId=$numericId, userName=$userName");
  }
}