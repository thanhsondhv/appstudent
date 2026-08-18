import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../core/auth/session.dart';
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
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/api/login_by_face"));
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
      return {"status": "ERROR", "message": "Lỗi Server AI (Code ${response.statusCode})"};
    } catch (e) { 
      return {"status": "ERROR", "message": "Lỗi kết nối Face ID"}; 
    }
  }

  // --- 4. WEBHOOK: ĐĂNG KÝ MÁY BƠM TIN NHẮN MS TEAMS ---
  Future<void> registerTeamsWebhook(String userCode) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/ms-webhook/subscribe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_code': userCode}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint("✅ [Webhook] Đã đăng ký máy bơm tin nhắn cho: $userCode");
      }
    } catch (e) {
      debugPrint("❌ [Webhook] Lỗi đăng ký: $e");
    }
  }

  // --- 5. LƯU PHIÊN ĐĂNG NHẬP TỔNG THỂ ---
  // Từ 18/08/2026 uỷ quyền cho Session — nơi duy nhất ghi thông tin phiên.
  // Trước đây hàm này và LoginHandler.executeSuccessfulLogin làm gần giống nhau
  // nhưng khác ở vài chi tiết, dẫn tới phiên không nhất quán giữa các cách đăng nhập.
  Future<void> _saveUserSession(Map<String, dynamic> data) async {
    await Session.save(data);

    // Kích hoạt máy bơm tin nhắn Teams cho mã người dùng vừa đăng nhập
    final userCode = await Session.userCode;
    if (userCode.isNotEmpty) {
      registerTeamsWebhook(userCode);
    }
  }

  Future<bool> verifyOffice365Session(String sessionToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_token': sessionToken}),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'success') {
          await _saveUserSession(resData['data']); 
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, String>?> getUserPublicInfo(String username) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/get_fullname/$username'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {'full_name': data['full_name'], 'numeric_id': data['numeric_id']};
        }
      }
    } catch (e) { debugPrint("Lỗi lấy thông tin: $e"); }
    return null;
  }
}