import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class FaceAuthService {
  // Domain đã NAT qua cổng 8080 (Main.py đóng vai trò Gateway)
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn';
  final LocalAuthentication _auth = LocalAuthentication();

  /// 1. XÁC THỰC BIOMETRIC CỤC BỘ (iPhone/Android)
  /// Kiểm tra vân tay hoặc khuôn mặt của máy để "mở khóa" quyền sử dụng App
  Future<bool> authenticateWithDevice() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) return false;

      return await _auth.authenticate(
        localizedReason: 'Vui lòng xác thực để truy cập ứng dụng VinhUni',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Chỉ dùng sinh trắc học, không dùng mật khẩu máy
        ),
      );
    } catch (e) {
      debugPrint("❌ Lỗi xác thực cục bộ: $e");
      return false;
    }
  }

  /// 2. XÁC THỰC 3D & ĐỐI KHỚP VECTOR TẠI SERVER
  /// Gửi ảnh qua Gateway 8080 để đẩy sang Student AI 8011 nội bộ
  Future<Map<String, dynamic>> verify3D({
    required String studentId,
    required File frontFile,
    required File poseFile,
  }) async {
    try {
      // Endpoint này đã được sửa lại trong Main.py để gọi sang cổng 8011
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/login_by_face'));
      
      // Thêm mã sinh viên để Server thực hiện đối khớp 1:1 với SQL
      request.fields['student_id'] = studentId;

      // Gửi 2 ảnh để thực hiện kiểm tra 3D (Xa - Gần hoặc Chính diện - Nghiêng)
      request.files.add(await http.MultipartFile.fromPath('photo_front', frontFile.path));
      request.files.add(await http.MultipartFile.fromPath('photo_pose', poseFile.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      
      return {
        "status": "ERROR", 
        "message": "Cổng kết nối AI bận (${response.statusCode})"
      };
    } catch (e) {
      debugPrint("🔥 Lỗi FaceAuthService: $e");
      return {
        "status": "ERROR", 
        "message": "Không thể kết nối hệ thống xác thực"
      };
    }
  }
}