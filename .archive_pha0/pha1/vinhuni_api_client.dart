import 'package:flutter/material.dart'; // 🔥 DÒNG QUAN TRỌNG NHẤT SƠN ĐANG THIẾU
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../core/auth/session.dart';
import '../main.dart';

class VinhUniClient {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://mobi.vinhuni.edu.vn',
      connectTimeout: const Duration(seconds: 30), 
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  static String? _cachedDeviceId;

  // Hàm lấy ID thiết bị (Cache lại để không phải gọi nhiều lần)
  static Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _cachedDeviceId = androidInfo.id; // Mã ID duy nhất Android
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _cachedDeviceId = iosInfo.identifierForVendor; // Mã ID duy nhất iOS
    }
    return _cachedDeviceId ?? "Unknown_Device";
  }

  static void setup() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // ⚠️ SỬA 18/08/2026: trước đây đọc token bằng
        //     prefs.getString('access_token')
        // Từ khi Session chuyển token sang kho mã hoá (Keychain trên iOS,
        // EncryptedSharedPreferences trên Android) và xoá bản trong
        // SharedPreferences, dòng cũ luôn trả về null — mọi yêu cầu đi ra
        // KHÔNG còn kèm token. Nay đọc qua Session, nguồn duy nhất.
        final token = await Session.accessToken;
        final studentCode = await Session.userCode;
        final deviceId = await _getDeviceId();

        // 🔥 Gắn "Bộ 3 Quyền Lực" vào Header để Backend xử lý Blacklist
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['X-Device-ID'] = deviceId;       // Chặn theo thiết bị
        if (studentCode.isNotEmpty) {
          options.headers['X-Student-Code'] = studentCode; // Chặn theo mã cá nhân
        }

        print("📡 [SENT] API: ${options.path} | Device: $deviceId | User: $studentCode");
        return handler.next(options);
      },
      
      onError: (DioException e, handler) {
        // 1. Xử lý khi hết hạn Token (401)
        if (e.response?.statusCode == 401) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
        }
        
        // 2. 🔥 Xử lý khi bị Backend "Nhốt" vào Blacklist (403 hoặc 429)
        if (e.response?.statusCode == 403 || e.response?.statusCode == 429) {
          final msg = e.response?.data['message'] ?? "Tài khoản bị tạm khóa do hành vi bất thường.";
          // Hiển thị thông báo cho Sinh viên biết lý do và thời gian được thả
          _showBlockedDialog(msg);
        }
        
        return handler.next(e);
      },
    ));
  }

  // Hàm hiển thị thông báo khóa (Sơn có thể tùy biến giao diện)
  static void _showBlockedDialog(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Thông báo bảo mật"),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ĐÃ HIỂU"),
            ),
          ],
        ),
      );
    }
  }

  static Dio get instance => _dio;
}