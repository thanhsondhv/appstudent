import 'package:flutter/material.dart';
import '../core/api/may_chu.dart';
import '../core/auth/session.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/notification_service.dart';

class LoginHandler {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 🔥 BẮT TAY BẢO MẬT: Nhận token từ Deep Link -> Lấy thông tin & Chìa khóa OneDrive
  static Future<void> verifySessionAndLogin(BuildContext context, String sessionToken) async {
    try {
      final response = await http.post(
        Uri.parse('${MayChu.diaChi}/api/auth/verify-session'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"session_token": sessionToken}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
          final userData = result['data'];

          // Kiểm tra xem người dùng ĐÃ đăng nhập App chưa
          final bool alreadyLoggedIn = await Session.isLoggedIn;

          if (alreadyLoggedIn) {
            // TRƯỜNG HỢP 1: Chỉ cập nhật Token (Dành cho việc Re-connect OneDrive)
            if (userData['ms_access_token'] != null) {
              // Qua Session để token vào kho mã hoá, cùng nơi VinhUniClient đọc
              await Session.saveMicrosoftToken(
                userData['ms_access_token'].toString(),
                expiresInSeconds: userData['ms_expires_in'] as int?,
              );
              debugPrint("🔄 [Handler] Đã làm mới Microsoft Token thành công!");
              
              // Thông báo cho người dùng
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Đã kết nối lại OneDrive!"), backgroundColor: Colors.green)
                );
              }
            }
          } else {
            // TRƯỜNG HỢP 2: Đăng nhập mới hoàn toàn (Vào trang Home)
            await executeSuccessfulLogin(
              context,
              userData['user_id'].toString(),
              userData['full_name'] ?? "Thành viên",
              role: userData['role'] ?? userData['user_role'],
              accessToken: userData['access_token'],
              msAccessToken: userData['ms_access_token'],
            );
          }
        }
      }
    } catch (e) { debugPrint("❌ Lỗi Handshake: $e"); }
  }

  /// Hàm lưu dữ liệu tổng thể vào máy
  static Future<void> executeSuccessfulLogin(
      BuildContext context, String userId, String fullName, 
      {String? role, String? accessToken, String? msAccessToken}) async { 
    try {
      // ⚠️ SỬA 18/08/2026: trước đây khối này tự ghi thẳng vào SharedPreferences,
      // gần giống nhưng không hoàn toàn trùng với AuthService._saveUserSession —
      // hai luồng đăng nhập tạo ra hai kiểu phiên hơi khác nhau. Và từ khi token
      // chuyển sang kho mã hoá, ghi kiểu cũ khiến VinhUniClient không tìm thấy
      // token, mọi lời gọi API sau đó đi ra không xác thực.
      // Nay uỷ quyền cho Session — nơi duy nhất ghi thông tin phiên.
      await Session.save({
        'user_id': userId,
        'full_name': fullName,
        'user_role': role,
        'access_token': accessToken,
        'ms_access_token': msAccessToken,
      });

      final cleanId = await Session.userCode;
      debugPrint("✅ [Handler] Đã lưu phiên cho $cleanId — vai trò ${role ?? 'SinhVien'}");

      // Đồng bộ thông báo
      NotificationService.syncTokenToServer(cleanId);
      
      try {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_users");
      } catch (e) { debugPrint("⚠️ Firebase Error: $e"); }

      await Future.delayed(const Duration(milliseconds: 200));

      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      debugPrint("❌ Lỗi LoginHandler: $e");
    }
  }

  static Future<bool> isFaceRegistered(String numericId, String loginUserName) async {
    try {
      String? savedUser = await _storage.read(key: 'bio_user');
      return (savedUser == loginUserName || savedUser == numericId);
    } catch (e) { return false; }
  }
}