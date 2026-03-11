import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/notification_service.dart';

class LoginHandler {
  /// Đăng ký hoặc hủy đăng ký nhận thông báo theo Topic chung
  static Future<void> handleNotificationTopic(bool isSubscribing) async {
    try {
      if (isSubscribing) {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic("vinhuni_all_students");
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi xử lý Topic thông báo: $e");
    }
  }

  /// Xử lý logic sau khi đăng nhập thành công
  static Future<void> executeSuccessfulLogin(
      BuildContext context, String userId, String fullName, {String? role}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Lưu thông tin cơ bản vào máy
      await prefs.setString('user_id', userId);
      await prefs.setString('user_code', userId); // Đồng bộ mã sinh viên/giảng viên
      
      String finalName = (fullName.trim().isEmpty) ? "Thành viên VinhUni" : fullName;
      await prefs.setString('full_name', finalName);
      
      // 2. Lưu vai trò người dùng (Sinh viên/Cán bộ)
      // 🔥 Ưu tiên role truyền vào, nếu không có thì đọc lại từ prefs (do AuthService đã lưu trước đó)
      if (role != null && role.isNotEmpty) {
        await prefs.setString('user_role', role);
      } else {
        final savedRole = prefs.getString('user_role');
        if (savedRole == null || savedRole.isEmpty) {
          await prefs.setString('user_role', 'SinhVien');
        }
      }

      // 3. Kích hoạt thông báo và đồng bộ Token FCM lên Server
      await handleNotificationTopic(true);
      await NotificationService().syncTokenToServer(userId); 

      // 4. ĐIỀU HƯỚNG VÀ XÓA STACK (Giải quyết lỗi nút Back)
      if (context.mounted) {
        // Sử dụng pushNamedAndRemoveUntil để xóa sạch các màn hình cũ (như màn hình Login)
        // Sau lệnh này, nút Back ở màn hình chính sẽ không thể quay lại màn hình Login nữa.
        Navigator.pushNamedAndRemoveUntil(
          context, 
          '/home', 
          (route) => false, 
        );
      }
    } catch (e) {
      debugPrint("❌ Lỗi nghiêm trọng khi lưu phiên đăng nhập: $e");
    }
  }
}