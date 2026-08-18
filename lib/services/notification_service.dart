import 'dart:convert';
import '../core/api/may_chu.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import '../views/chatgroup/chat_room_page.dart';
import 'database_helper.dart';
import '../main.dart'; // Chứa navigatorKey toàn cục
import '../views/thongbao_chitiet_screen.dart';
import '../views/thongbao_screen.dart';
import '../views/chatgroup/chat_group_list_page.dart';
import '../core/api/api.dart';
class NotificationService {
  // Không dùng `const` được vì địa chỉ máy chủ đọc từ MayChu lúc chạy
  static String get domainApi => "${MayChu.diaChi}/api";
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Callback để làm mới UI khi có thông báo tới
  static Function? onRefreshBadge;
  
  // Dữ liệu tạm khi mở App từ trạng thái tắt hoàn toàn
  static Map<String, dynamic>? _terminatedNotificationData;

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // --- 1. KHỞI TẠO DỊCH VỤ (FIREBASE + LOCAL) ---
  Future<void> initialize() async {
    // A. Kiểm tra thiết bị thật trên iOS
    if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      if (!iosInfo.isPhysicalDevice) {
        debugPrint("⚠️ iOS Simulator: Bỏ qua Firebase.");
        return;
      }
    }

    // B. Cấu hình Local Notifications
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
      // Xin quyền thông báo
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Cấu hình hiển thị Foreground (Khi đang mở app)
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      // 1. Nhận tin nhắn khi App đang mở
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
       // debugPrint("📩 Nhận tin Foreground: ${message.notification?.title}");
        _showLocalNotification(message);
        refreshAppIconBadge(); // Cập nhật ngay con số ngoài Icon
        if (onRefreshBadge != null) onRefreshBadge!(); 
      });

      // 2. Nhận tin khi nhấn vào thông báo (App chạy nền)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
       // debugPrint("🚀 Nhấn vào thông báo (Background)");
        _handleNavigation(message.data);
      });

      // 3. Nhận tin khi App tắt hoàn toàn (Cold Start)
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          _terminatedNotificationData = message.data;
          Future.delayed(const Duration(milliseconds: 1200), () {
            _handleNavigation(message.data);
          });
        }
      });

      // Cập nhật Badge ngay khi khởi động
      refreshAppIconBadge();

    } catch (e) {
      //debugPrint("❌ Lỗi Firebase: $e");
    }
  }

  // --- 2. HIỂN THỊ THÔNG BÁO LOCAL ---
  void _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'vinhuni_channel_id', 'Thông báo VinhUni',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      
      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails, 
        iOS: DarwinNotificationDetails()
      );

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
        payload: jsonEncode(message.data),
      );
    }
  }



  // --- 3. ĐIỀU HƯỚNG CHI TIẾT ---
  static Future<void> _handleNavigation(Map<String, dynamic> data) async {
    // Bật in log để xem dữ liệu Firebase trả về có đúng không
    debugPrint("🧭 [ĐIỀU HƯỚNG PUSH] Nhận được Data: $data");

    final String? idStr = data['nid']?.toString() ?? data['notif_id']?.toString();
    final String? type = data['category']?.toString() ?? data['type']?.toString();
    final String? groupId = data['group_id']?.toString();

    // 🔥 XỬ LÝ RIÊNG NẾU ĐÓ LÀ THÔNG BÁO CHAT
    if (type == 'CHAT' || type == 'CHAT_GROUP') {
      final prefs = await SharedPreferences.getInstance();
      String userCode = prefs.getString('user_code') ?? "";
      
      // 🔥 BẢO VỆ CHỐNG NULL: Tránh lỗi Firebase nuốt mất biến rỗng
      String safeGroupId = groupId ?? ""; 

      debugPrint("🧭 [ĐIỀU HƯỚNG CHAT] Chuẩn bị mở phòng: '$safeGroupId' cho User: $userCode");

      // 🔥 BÍ QUYẾT: Đợi 0.5s để đảm bảo MaterialApp đã load xong 100%
      await Future.delayed(const Duration(milliseconds: 500));

      // Kiểm tra bằng safeGroupId
      if (userCode.isNotEmpty && safeGroupId.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(groupId: safeGroupId, userCode: userCode)
          )
        );
      } else {
        // 🔥 SỬA LỖI VĂNG APP TẠI ĐÂY: Dùng MaterialPageRoute về danh sách nhóm
        debugPrint("⚠️ Không tìm thấy GroupId, an toàn hạ cánh về danh sách nhóm.");
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ChatGroupListPage(userCode: userCode)
          )
        );
      }
      return; // Kết thúc điều hướng chat
    }

    // NẾU LÀ THÔNG BÁO BÌNH THƯỜNG CỦA TRƯỜNG
    //
    // 🔥 SỬA 18/08/2026: bản cũ dùng `int.parse(idStr)` không bọc bảo vệ. Chỉ
    // cần máy chủ gửi thiếu trường `nid`, gửi chuỗi rỗng, hay gửi `0` (mã
    // không có thật) là ứng dụng văng ngay khi người dùng bấm vào thông báo —
    // đúng lúc không có cách nào chẩn đoán. Đã gặp thật khi gửi tin thử với
    // nid = 0: màn chi tiết mở ra trắng trơn.
    //
    // Nay: mã không hợp lệ thì đưa về danh sách thông báo, người dùng vẫn tới
    // được nội dung thay vì mất cả ứng dụng.
    final int maTin = int.tryParse(idStr ?? '') ?? 0;
    await Future.delayed(const Duration(milliseconds: 500));

    if (maTin <= 0) {
      debugPrint("⚠️ Thông báo không kèm mã tin hợp lệ (nid='$idStr'), "
          "mở danh sách thông báo thay thế.");
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const ThongBaoScreen()),
      ).then((_) => refreshAppIconBadge());
      return;
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ChiTietThongBaoScreen(
          notification: {
            'ID': maTin,
            'TieuDe': 'Đang tải...', 
            'LoaiTin': type ?? 'GENERAL'
          },
        ),
      ),
    ).then((_) => refreshAppIconBadge()); 
  }

  // --- 4. CẬP NHẬT BADGE NGOÀI ICON APP (BẢN FIX CHUẨN) ---
  static Future<void> refreshAppIconBadge() async {
    final db = DatabaseHelper.instance;
    final String? userId = await db.getLoggedInUserId();
    
    if (userId != null) {
      final database = await db.database;
      // Truy vấn trực tiếp vào DB để đếm chính xác số 0/1
      final List<Map<String, dynamic>> result = await database.rawQuery(
        'SELECT id FROM notifications WHERE UserCode = ? AND IsRead = 0',
        [userId]
      );

      int unreadCount = result.length;
      if (unreadCount > 0) {
        FlutterAppBadger.updateBadgeCount(unreadCount);
      } else {
        FlutterAppBadger.removeBadge();
      }
    }
  }

  // --- 5. ĐỒNG BỘ FCM TOKEN LÊN SQL SERVER ---
  static Future<void> syncTokenToServer(String userId) async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) return;

      String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      
      // Chuyển sang Api ngày 18/08/2026 (Pha 1): tự kèm token và mã thiết bị,
      // và không còn viết cứng địa chỉ máy chủ trong tệp này.
      final res = await Api.post(
        "/api/save-fcm-token",
        duLieu: {
          "student_id": userId,
          "token": token,
          "platform": Platform.isAndroid ? "Android" : "iOS",
          "device_name": Platform.isIOS ? "iPhone" : "Android Device"
        },
      );

      if (res.thanhCong) {
        debugPrint("✅ [ThôngBáo] Đã đồng bộ mã thiết bị lên máy chủ");
      } else {
        debugPrint("⚠️ [ThôngBáo] Không đồng bộ được mã thiết bị: ${res.thongDiepLoi}");
      }
    } catch (e) {
      debugPrint("🔥 [ThôngBáo] Lỗi đồng bộ mã thiết bị: $e");
    }
  }

  // --- 6. ĐỒNG BỘ TIN NHẮN TỪ SERVER VỀ SQLITE ---
  static Future<List<dynamic>> fetchAndSyncNotifs(String userId) async {
    // 1. Lấy dữ liệu cũ từ SQLite
    List<dynamic> localData = await DatabaseHelper.instance.getOfflineNotifs(userId);

    try {
      final res = await Api.get(
        "/api/get-notifs/$userId",
        thamSo: {"page": "1"},
        hanCho: const Duration(seconds: 10),
      );

      if (res.thanhCong) {
        final duLieu = res.data;
        final List<dynamic> serverData =
            duLieu is List ? duLieu : (duLieu is Map ? (duLieu['data'] as List? ?? []) : []);
        for (var n in serverData) {
          // Lưu vào SQLite
          await DatabaseHelper.instance.insertNotification(n, userId);
        }
        // Trả về dữ liệu mới nhất sau khi đồng bộ
        List<dynamic> updatedLocal = await DatabaseHelper.instance.getOfflineNotifs(userId);
        
        // Cập nhật Badge sau khi đồng bộ
        refreshAppIconBadge();
        
        return updatedLocal;
      }
    } catch (e) {
      debugPrint("🔥 [ThôngBáo] Lỗi đồng bộ danh sách: $e");
    }
    return localData;
  }

  // Lấy Route ban đầu cho Splash Screen
  static Future<String?> getInitialRoute() async {
    try {
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _terminatedNotificationData = initialMessage.data;
        return 'SCREEN_THONG_BAO_CHI_TIET'; 
      }
    } catch (e) {
     // debugPrint("⚠️ Lỗi InitialRoute: $e");
    }
    return null;
  }
}