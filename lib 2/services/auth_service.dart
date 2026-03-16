import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Các import cần thiết để Việt hóa thông báo cho iOS và Android
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
          // Lưu phiên trực tiếp ở đây để đảm bảo an toàn
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

  // --- 2. XÁC THỰC THIẾT BỊ (MỞ QUYỀN VÀ VIỆT HÓA) ---
  Future<bool> authenticateWithDevice() async {
    try {
      // Kiểm tra tính khả dụng của phần cứng sinh trắc học
      bool canCheck = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canCheck) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Vui lòng xác thực để truy cập VinhUni App',
        options: const AuthenticationOptions(
          biometricOnly: false, // Cho phép dùng PIN/Mật khẩu nếu chưa cài FaceID
          stickyAuth: true,
          useErrorDialogs: true, 
        ),
        // Cấu hình tin nhắn tiếng Việt thay cho tiếng Anh mặc định
        authMessages: [ 
          const IOSAuthMessages( 
            cancelButton: 'Hủy',
            goToSettingsButton: 'Cài đặt',
            goToSettingsDescription: 'Vui lòng thiết lập Face ID hoặc Mật mã trên điện thoại của bạn.',
            lockOut: 'Vui lòng bật lại Face ID',
          ),
          const AndroidAuthMessages( 
            signInTitle: 'Xác thực VinhUni',
            biometricHint: 'Quét vân tay hoặc khuôn mặt',
            cancelButton: 'Hủy',
          ),
        ],
      );
    } catch (e) {
      debugPrint("❌ Lỗi Local Auth: $e");
      return false;
    }
  }

  // --- 3. ĐĂNG NHẬP FACE ID PRO (GỬI ẢNH LÊN SERVER AI) ---
  Future<Map<String, dynamic>> loginByFacePro({required File frontFile}) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/api/login_by_face_pro"),
      );

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
    } catch (e) {
      return {"status": "ERROR", "message": "Lỗi kết nối: $e"};
    }
  }

  // --- 4. HELPER: LƯU PHIÊN ĐĂNG NHẬP ---
  Future<void> _saveUserSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    String sid = data['student_id']?.toString() ?? data['user_code']?.toString() ?? "";
    
    // 🔥 ĐÃ FIX LỖI Ở ĐÂY: Quét cả 2 key 'user_role' và 'role' để không bị sót dữ liệu từ Python
    String role = data['user_role']?.toString() ?? data['role']?.toString() ?? "SinhVien";

    await prefs.setString('user_code', sid);
    await prefs.setString('full_name', data['full_name'] ?? "Người dùng");
    await prefs.setString('user_role', role);
    await prefs.setBool('is_logged_in', true);
    
    debugPrint("✅ AuthService đã lưu Role thành công: $role");
  }
}