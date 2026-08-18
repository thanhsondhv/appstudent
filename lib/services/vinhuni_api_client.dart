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
        
        // 2. Xử lý 403 và 429.
        //
        // Sửa 18/08/2026: bản cũ coi MỌI mã 403 là "tài khoản bị tạm khóa do
        // hành vi bất thường". Nhưng 403 còn phát sinh khi sinh viên chạm vào
        // một chức năng chỉ dành cho cán bộ — trường hợp hoàn toàn bình thường.
        // Báo nhầm khiến người dùng tưởng mình bị kỷ luật.
        //
        // Phân biệt bằng chính dữ liệu máy chủ trả về:
        //   • Bị chặn thật:  {"status": "blocked", "message": "...đến 09:30"}
        //   • Thiếu quyền:   {"detail": "Chức năng này chỉ dành cho cán bộ..."}
        final maLoi = e.response?.statusCode;
        if (maLoi == 403 || maLoi == 429) {
          final duLieu = e.response?.data;
          final Map thongTin = duLieu is Map ? duLieu : const {};
          final biChanThat = thongTin['status'] == 'blocked' || maLoi == 429;

          if (biChanThat) {
            _hienHopThoai(
              tieuDe: "Tạm khóa truy cập",
              noiDung: thongTin['message']?.toString() ??
                  "Hệ thống tạm khóa truy cập do phát hiện hành vi bất thường. "
                      "Vui lòng thử lại sau ít phút.",
              lyDo: thongTin['reason']?.toString(),
            );
          } else {
            _hienHopThoai(
              tieuDe: "Không có quyền",
              noiDung: thongTin['detail']?.toString() ??
                  thongTin['message']?.toString() ??
                  "Bạn không có quyền dùng chức năng này.",
            );
          }
        }
        
        return handler.next(e);
      },
    ));
  }

  /// Đang có hộp thoại nào mở không — tránh chồng nhiều hộp thoại khi một màn
  /// hình gọi vài API cùng lúc và tất cả đều bị từ chối.
  static bool _dangMoHopThoai = false;

  static void _hienHopThoai({
    required String tieuDe,
    required String noiDung,
    String? lyDo,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null || _dangMoHopThoai) return;

    _dangMoHopThoai = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(tieuDe, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(noiDung),
            if (lyDo != null && lyDo.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text("Lý do: $lyDo",
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ĐÃ HIỂU"),
          ),
        ],
      ),
    ).then((_) => _dangMoHopThoai = false);
  }

  static Dio get instance => _dio;
}