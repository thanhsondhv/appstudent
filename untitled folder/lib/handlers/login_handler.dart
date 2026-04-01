import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; 
import '../services/notification_service.dart';

class LoginHandler {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Kiểm tra xem User này đã có Face ID trong máy chưa
  static Future<bool> isFaceRegistered(String numericId, String loginUserName) async {
    try {
      // 1. Kiểm tra trong két sắt bảo mật
      String? savedUser = await _storage.read(key: 'bio_user');
      
      // 2. Nếu két sắt đang giữ đúng username (ntson) hoặc mã số (1679)
      // thì báo true để không hiện Dialog nữa
      return (savedUser == loginUserName || savedUser == numericId);
    } catch (e) {
      return false;
    }
  }

  static Future<void> executeSuccessfulLogin(
      BuildContext context, String userId, String fullName, {String? role}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Làm sạch ID lần cuối (CB1679 -> 1679)
      String cleanId = userId.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanId.isEmpty) cleanId = userId;

      // 2. 🔥 LƯU CỰC KỲ CHẮC CHẮN (Dùng await cho từng dòng)
      await prefs.setString('user_id', cleanId);
      await prefs.setString('user_code', cleanId);
      await prefs.setString('full_name', fullName);
      await prefs.setString('user_role', role ?? 'CanBo'); // Quan trọng để banner hiện đúng
      await prefs.setBool('is_logged_in', true);

      // 3. Đồng bộ Notify (Có thể không cần await quá lâu để tránh delay)
      NotificationService.syncTokenToServer(cleanId);
      FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");

      debugPrint("✅ [Handler] Đã lưu xong dữ liệu cho $role: $cleanId");

      // 4. CHỜ 1 CHÚT (Khoảng 200ms) để hệ thống kịp cập nhật bộ nhớ rồi mới nhảy Home
      await Future.delayed(const Duration(milliseconds: 200));

      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context, 
          '/home', 
          (route) => false
        );
      }
    } catch (e) {
      debugPrint("❌ Lỗi LoginHandler: $e");
    }
  }
}