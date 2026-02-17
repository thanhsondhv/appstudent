import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  // Domain API kết nối đến Backend FastAPI của bạn
  static const String domainApi = "https://mobi.vinhuni.edu.vn/api";

  // 1. Khởi tạo và xin quyền thông báo
  Future<void> initialize() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Yêu cầu quyền thông báo
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('🔔 [System] Quyền thông báo đã được cấp.');
      
      // QUAN TRỌNG CHO IOS: Đăng ký nhận thông báo từ Apple ngay lập tức
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    }
  }

  // 2. Đồng bộ Token lên Server (Dùng chung cho Android/iOS)
  Future<void> syncTokenToServer(String studentId) async {
    try {
      String? currentToken;

      // --- LOGIC RIÊNG CHO IOS ---
      if (!kIsWeb && Platform.isIOS) {
        debugPrint("⏳ iOS: Đang kiểm tra trạng thái APNs...");
        String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        
        int retry = 0;
        // Chờ tối đa 10s để Apple cấp APNs Token
        while (apnsToken == null && retry < 5) {
          await Future.delayed(const Duration(seconds: 2));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          retry++;
          debugPrint("⏳ iOS: Đang chờ APNs lần $retry...");
        }

        if (apnsToken == null) {
          debugPrint("❌ iOS Error: Không lấy được APNs Token. Kiểm tra cấu hình .p8 trên Firebase.");
          return;
        }
      }

      // --- LẤY FCM TOKEN ---
      if (kIsWeb) {
        currentToken = await FirebaseMessaging.instance.getToken(
          vapidKey: "BNr8bNA8UwaqQkr236uM7Wgvo8RDbL-mBG-rOPz5pS2T5Qq-kD27GtALBQqhf3q52B0zUnSr-DuTU8bHLOuxhKA"
        );
      } else {
        currentToken = await FirebaseMessaging.instance.getToken();
      }

      if (currentToken == null) {
        debugPrint("⚠️ Không thể lấy FCM Token từ Firebase.");
        return;
      }

      // --- KIỂM TRA TRÙNG LẶP ---
      final prefs = await SharedPreferences.getInstance();
      String? lastToken = prefs.getString('last_fcm_token');

      if (lastToken == currentToken) {
        debugPrint("ℹ️ Token không đổi cho SV: $studentId. Bỏ qua gửi Server.");
        return;
      }

      // --- GỬI LÊN BACKEND PYTHON (FastAPI) ---
      debugPrint("📡 Đang đồng bộ Token lên Server VinhUni...");
      
      String platformName = kIsWeb ? "Web" : (Platform.isAndroid ? "Android" : "iOS");
      String deviceName = kIsWeb ? "Browser" : (Platform.isAndroid ? "Android Device" : "iPhone 16e");

      final response = await http.post(
        Uri.parse("$domainApi/save-fcm-token"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": studentId, // Ví dụ: 205714023110061
          "token": currentToken,
          "platform": platformName,
          "device_name": deviceName
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await prefs.setString('last_fcm_token', currentToken);
        debugPrint("✅ Đã lưu Token thành công cho SV: $studentId ($platformName)");
      } else {
        debugPrint("⚠️ Lỗi Backend (${response.statusCode}): ${response.body}");
      }

    } catch (e) {
      debugPrint("💥 Lỗi hệ thống syncToken: $e");
    }
  }
} // Kết thúc class NotificationService