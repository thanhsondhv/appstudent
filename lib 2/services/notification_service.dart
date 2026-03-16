//NotificationService.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'database_helper.dart';

// Import key điều hướng toàn cục từ main.dart
import '../main.dart'; 
import '../views/thongbao_chitiet_screen.dart';

class NotificationService {
  static const String domainApi = "https://mobi.vinhuni.edu.vn/api";
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Callback để làm mới UI khi có thông báo tới
  static Function? onRefreshBadge;

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  static Map<String, dynamic>? _terminatedNotificationData;
  // --- 1. KHỞI TẠO DỊCH VỤ ---
  Future<void> initialize() async {
    // Kiểm tra thiết bị thật trên iOS
    if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      if (!iosInfo.isPhysicalDevice) {
        debugPrint("⚠️ iOS Simulator: Bỏ qua Firebase.");
        return;
      }
    }

    // Cấu hình Local Notifications (Để hiện tin nhắn khi đang mở App)
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          final Map<String, dynamic> data = jsonDecode(details.payload!);
          _handleNavigation(data);
        }
      },
    );

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    try {
      // Yêu cầu quyền
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Cấu hình hiển thị thông báo khi App đang mở (Foreground)
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      // A. Lắng nghe tin nhắn tới khi App đang mở
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("📩 Nhận tin nhắn mới (Foreground): ${message.notification?.title}");
        _showLocalNotification(message);
        updateBadgeCount(); 
      });

      // B. Lắng nghe khi nhấn vào thông báo (App đang chạy nền)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("🚀 Người dùng nhấn vào thông báo (Background)");
        _handleNavigation(message.data);
      });

      // C. Lắng nghe khi App bị tắt hoàn toàn và mở lại từ thông báo
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          debugPrint("🚀 App mở từ trạng thái tắt hoàn toàn");
          Future.delayed(const Duration(milliseconds: 800), () {
            _handleNavigation(message.data);
          });
        }
      });

      // Cập nhật số badge khi vừa vào App
      updateBadgeCount();

    } catch (e) {
      debugPrint("❌ Lỗi khởi tạo Firebase: $e");
    }
  }
  // --- HÀM KIỂM TRA THÔNG BÁO KHI KHỞI ĐỘNG (FIX LỖI MEMBER NOT FOUND) ---
static Future<String?> getInitialRoute() async {
  try {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    
    if (initialMessage != null && initialMessage.data.containsKey('notif_id')) {
      // Lưu lại data để tí nữa vào Home hoặc Splash xong ta gọi điều hướng
      _terminatedNotificationData = initialMessage.data;
      
      // Trả về một chuỗi đại diện (Route) để Splash Screen nhận diện
      // Lưu ý: Chuỗi này phải khớp với logic xử lý ở Splash Screen của bạn
      return 'SCREEN_THONG_BAO_CHI_TIET'; 
    }
  } catch (e) {
    debugPrint("⚠️ Lỗi getInitialMessage: $e");
  }
  return null;
}
  // --- 2. HÀM HIỂN THỊ THÔNG BÁO NỘI BỘ (LOCAL) ---
  void _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'vinhuni_channel_id', 'Thông báo VinhUni',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      
      const NotificationDetails platformDetails = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

      // Gói dữ liệu vào payload để khi nhấn vào Local Notif vẫn điều hướng được
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
        payload: jsonEncode(message.data),
      );
    }
  }

  // --- 3. HÀM ĐIỀU HƯỚNG CHI TIẾT (QUAN TRỌNG) ---
  // --- CẬP NHẬT HÀM ĐIỀU HƯỚNG ---
static void _handleNavigation(Map<String, dynamic> data) {
  // 🔥 DÒNG QUAN TRỌNG: In ra để xem Firebase gửi gì về
  debugPrint("📩 Click Notification Data: $data");

  // Khớp với Worker: lấy 'nid' nếu có, không thì thử 'notif_id'
  final String? idStr = data['nid']?.toString() ?? data['notif_id']?.toString();
  // Khớp với Worker: lấy 'category' nếu có
  final String? type = data['category']?.toString() ?? data['type']?.toString();

  if (idStr == null) {
    debugPrint("❌ Lỗi: Không tìm thấy ID tin nhắn trong payload!");
    return;
  }

  // Điều hướng sang màn hình chi tiết
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (context) => ChiTietThongBaoScreen(
        notification: {
          'ID': int.parse(idStr),
          'TieuDe': 'Đang tải...', 
          'LoaiTin': type ?? 'PERSONAL'
        },
      ),
    ),
  );
}

  // --- 4. ĐỒNG BỘ TOKEN LÊN SERVER (DÙNG CLEAN ID) ---
  static Future<void> syncTokenToServer(String userId) async {
  try {
    debugPrint("📡 [System] Khởi chạy sync Token cho: $userId");

    // 1. Xin quyền (Bắt buộc cho Firebase 11.x trên iOS/Android 13+)
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint("❌ [System] Quyền thông báo bị từ chối.");
      return;
    }

    // 2. Lấy Token từ Firebase
    String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    
    debugPrint("🔑 [System] FCM Token lấy được: $token");

    // 3. Gọi API lưu vào SQL (Khớp với router.py)
    final response = await http.post(
      Uri.parse("https://mobi.vinhuni.edu.vn/api/save-fcm-token"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "student_id": userId, // Gửi nguyên mã CB1679
        "token": token,
        "platform": Platform.isAndroid ? "Android" : "iOS",
        "device_name": "iPhone NTS"
      }),
    );

    if (response.statusCode == 200) {
      debugPrint("✅ [System] ĐÃ ĐỒNG BỘ TOKEN VÀO SQL THÀNH CÔNG!");
    } else {
      debugPrint("⚠️ [System] Server phản hồi lỗi: ${response.body}");
    }
  } catch (e) {
    debugPrint("🔥 [System] Lỗi khi sync Token: $e");
  }
}

  // --- 5. CẬP NHẬT BADGE (SỐ TIN CHƯA ĐỌC) ---
  Future<void> updateBadgeCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');
      
      if (userId == null) return;

      final response = await http.get(Uri.parse("$domainApi/count-unread/$userId"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        int unreadCount = data['unread_count'] ?? 0;

        if (await FlutterAppBadger.isAppBadgeSupported()) {
          unreadCount > 0 ? FlutterAppBadger.updateBadgeCount(unreadCount) : FlutterAppBadger.removeBadge();
        }
        
        await prefs.setInt('unread_notif_count', unreadCount);
        if (onRefreshBadge != null) onRefreshBadge!();
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi updateBadge: $e");
    }
  }

  // --- 6. ĐỒNG BỘ TIN NHẮN OFFLINE ---
  // NotificationService.dart

  // --- 6. ĐỒNG BỘ TIN NHẮN OFFLINE (Cải tiến) ---
  static Future<List<dynamic>> fetchAndSyncNotifs(String userId) async {
    // 1. Lấy local của đúng người dùng
    List<dynamic> localData = await DatabaseHelper.instance.getOfflineNotifs(userId);

    try {
      final response = await http.get(Uri.parse("$domainApi/get-notifs/$userId?page=1"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> serverData = json.decode(utf8.decode(response.bodyBytes));
        for (var n in serverData) {
          // 2. Lưu kèm UserCode
          await DatabaseHelper.instance.insertNotification(n, userId);
        }
        return await DatabaseHelper.instance.getOfflineNotifs(userId);
      }
    } catch (e) { debugPrint("🔥 Lỗi đồng bộ: $e"); }
    return localData;
  }
}