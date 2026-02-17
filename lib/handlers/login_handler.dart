import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/notification_service.dart';

class LoginHandler {
  static Future<void> handleNotificationTopic(bool isSubscribing) async {
    try {
      if (isSubscribing) {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic("vinhuni_all_students");
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi Topic: $e");
    }
  }

  static Future<void> executeSuccessfulLogin(
      BuildContext context, String userId, String fullName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      
      String finalName = (fullName.trim().isEmpty) ? "Sinh viên VinhUni" : fullName;
      await prefs.setString('full_name', finalName);

      await handleNotificationTopic(true);
      await NotificationService().syncTokenToServer(userId); 

      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      debugPrint("❌ Lỗi lưu phiên đăng nhập: $e");
    }
  }
}