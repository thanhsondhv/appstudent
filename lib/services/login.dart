import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  // Domain Backend chính của bạn
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn'; 

  // =========================================================
  // 1. ĐĂNG NHẬP BẰNG MÃ SINH VIÊN & MẬT KHẨU
  // =========================================================
  Future<Map<String, dynamic>?> login(String user, String pass) async {
    final loginUri = Uri.parse('$baseUrl/api/login');
    
    try {
      final response = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user.trim(),
          'password': pass.trim()
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
          // Trả về Map chứa: student_id và full_name đã ghép
          return jsonResponse['data']; 
        }
      }
      return null;
    } catch (e) {
      debugPrint("🔥 Lỗi đăng nhập truyền thống: $e");
      return null;
    }
  }

  // =========================================================
  // 2. ĐĂNG NHẬP BẰNG FACE ID (3D LIVENESS)
  // =========================================================
  Future<Map<String, dynamic>?> loginByFace({
    required File photoFront, 
    required File photoPose
  }) async {
    final faceLoginUri = Uri.parse('$baseUrl/api/login_by_face');

    try {
      debugPrint("📡 Đang gửi ảnh FaceID lên hệ thống AI...");
      
      // Sử dụng MultipartRequest để gửi file ảnh
      var request = http.MultipartRequest('POST', faceLoginUri);
      
      // Thêm 2 file ảnh: nhìn thẳng và quay đầu
      request.files.add(await http.MultipartFile.fromPath(
        'photo_front', 
        photoFront.path
      ));
      request.files.add(await http.MultipartFile.fromPath(
        'photo_pose', 
        photoPose.path
      ));

      // Thực hiện gửi dữ liệu
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint("📩 AI Worker Response: ${response.body}");

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        
        // Kiểm tra kết quả từ AI Worker thông qua Backend
        if (jsonResponse['status'] == 'SUCCESS') {
          return jsonResponse['data']; 
        } else {
          debugPrint("⚠️ AI Từ chối: ${jsonResponse['message']}");
        }
      }
      return null;
    } catch (e) {
      debugPrint("🔥 Lỗi kết nối FaceID: $e");
      return null;
    }
  }
}