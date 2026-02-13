import 'dart:convert';
import 'package:flutter/material.dart'; // Import này rất quan trọng để dùng Color
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// 1. Cấu hình kênh thông báo cho Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Thông báo Sinh viên VinhUni',
  description: 'Channel dùng cho thông báo quan trọng.',
  importance: Importance.max,
  playSound: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// 2. Hàm xử lý nền (Background Handler)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🌙 Nhận thông báo ngầm: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final String domainApi = "https://mobi.vinhuni.edu.vn/api"; 

  // --- KHỞI TẠO DỊCH VỤ ---
  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: "AIzaSyDXTIJfevodiYzPDjLeyRl8zxMLwOqoRa4",
            authDomain: "vinhuni-portal-student.firebaseapp.com",
            projectId: "vinhuni-portal-student",
            storageBucket: "vinhuni-portal-student.firebasestorage.app",
            messagingSenderId: "306901265797",
            appId: "1:306901265797:web:8082983e0b0bf5462268ec",
            measurementId: "G-3V0DQPY80W",
          ),
        );
      } else {
        await Firebase.initializeApp();
      }

      // Đăng ký hàm xử lý nền
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Cấu hình Local Notification
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Xin quyền
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );

      // Lắng nghe tin nhắn khi App đang mở
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          // HIỆN THÔNG BÁO (ĐÃ SỬA LỖI CONST)
          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.max,
                priority: Priority.high,
                // ĐÃ SỬA: Bỏ từ khóa 'const' ở đây vì ngữ cảnh không cho phép
                color: const Color(0xFF0056b3), 
              ),
            ),
          );
        }
      });

      print("✅ Notification Service initialized");
    } catch (e) {
      print("❌ Lỗi khởi tạo Notification: $e");
    }
  }

  // --- ĐỒNG BỘ TOKEN LÊN SERVER ---
  Future<void> syncTokenToServer(String studentId) async {
    try {
      String? currentToken;
      if (kIsWeb) {
        currentToken = await FirebaseMessaging.instance.getToken(
            vapidKey: "BNr8bNA8UwaqQkr236uM7Wgvo8RDbL-mBG-rOPz5pS2T5Qq-kD27GtALBQqhf3q52B0zUnSr-DuTU8bHLOuxhKA"
        );
      } else {
        currentToken = await FirebaseMessaging.instance.getToken();
      }

      if (currentToken == null) return;

      final prefs = await SharedPreferences.getInstance();
      String? lastToken = prefs.getString('last_fcm_token');

      if (lastToken == currentToken) {
        print("ℹ️ Token chưa đổi, không cần gửi lại.");
        return;
      }

      print("📡 Đang gửi Token mới lên Server...");
      
      String deviceName = kIsWeb ? "Web Browser" : (defaultTargetPlatform == TargetPlatform.android ? "Android Device" : "iOS Device");

      final response = await http.post(
        Uri.parse("$domainApi/save-fcm-token"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": studentId,
          "token": currentToken,
          "platform": kIsWeb ? "Web" : (defaultTargetPlatform == TargetPlatform.android ? "Android" : "iOS"),
          "device_name": deviceName
        }),
      );

      if (response.statusCode == 200) {
        await prefs.setString('last_fcm_token', currentToken);
        print("✅ Đã lưu Token thành công!");
      } else {
        print("⚠️ Lỗi Server lưu token: ${response.statusCode}");
      }
    } catch (e) {
      print("💥 Lỗi syncToken: $e");
    }
  }
}