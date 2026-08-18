import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/vinhuni_api_client.dart';

/// Kết quả một lời gọi API.
///
/// Cố ý giữ đúng hình dạng của `http.Response` — có [statusCode], [body],
/// [bodyBytes] — để chuyển mã cũ sang lớp này gần như chỉ đổi dòng gọi, không
/// phải viết lại logic xử lý bên dưới. Nhờ vậy việc chuyển 93 lời gọi mạng
/// không kèm theo rủi ro đổi hành vi.
class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.bodyBytes,
    this.data,
    this.loiMang = false,
    this.thongDiepLoi = '',
  });

  final int statusCode;

  /// Nội dung trả về dạng chuỗi. `json.decode(res.body)` dùng được như cũ.
  final String body;

  /// Nội dung dạng byte, cho mã đang dùng `utf8.decode(res.bodyBytes)`.
  final Uint8List bodyBytes;

  /// Dữ liệu đã được Dio giải mã sẵn — dùng cái này thì khỏi `json.decode`.
  final dynamic data;

  /// Đúng khi không kết nối được máy chủ (mất mạng, quá hạn chờ), phân biệt
  /// với trường hợp máy chủ có trả lời nhưng báo lỗi.
  final bool loiMang;

  /// Câu giải thích cho người dùng, đã diễn giải sẵn.
  final String thongDiepLoi;

  bool get thanhCong => statusCode >= 200 && statusCode < 300;
}

/// Lớp gọi API dùng chung cho toàn ứng dụng.
///
/// Mọi lời gọi mạng phải đi qua đây. Đổi lại so với việc tự gọi `package:http`:
///
///   • Tự gắn token, mã thiết bị, mã người dùng vào mọi yêu cầu
///   • Hết phiên (401) tự đưa về màn đăng nhập, không cần mỗi màn tự kiểm tra
///   • Bị khoá (403, 429) tự hiện thông báo giải thích
///   • Địa chỉ máy chủ khai báo một chỗ, không lặp lại chuỗi
///     "https://mobi.vinhuni.edu.vn/api" trong từng tệp
///
/// KHÔNG ném ngoại lệ khi máy chủ trả 404 hay 500 — trả về [ApiResponse] có
/// [ApiResponse.statusCode] tương ứng, giống hệt cách `package:http` hành xử.
/// Đây là điểm mấu chốt: Dio mặc định ném ngoại lệ với mọi mã lỗi, nếu chuyển
/// thẳng thì các nhánh `else` xử lý lỗi trong mã cũ sẽ không bao giờ chạy tới.
///
/// Bộ chặn 401/403 của [VinhUniClient] vẫn hoạt động bình thường: nó chạy trước
/// khi ngoại lệ được ném ra, lớp này chỉ bắt lại ở bước cuối.
///
/// Thêm ngày 18/08/2026 — Pha 1 lộ trình nâng cấp.
class Api {
  Api._();

  static Future<ApiResponse> get(
    String duongDan, {
    Map<String, dynamic>? thamSo,
    Duration? hanCho,
  }) =>
      _goi(() => VinhUniClient.instance.get(
            duongDan,
            queryParameters: thamSo,
            options: _tuyChon(hanCho),
          ));

  static Future<ApiResponse> post(
    String duongDan, {
    Object? duLieu,
    Map<String, dynamic>? thamSo,
    Duration? hanCho,
  }) =>
      _goi(() => VinhUniClient.instance.post(
            duongDan,
            data: duLieu,
            queryParameters: thamSo,
            options: _tuyChon(hanCho),
          ));

  static Future<ApiResponse> put(
    String duongDan, {
    Object? duLieu,
    Duration? hanCho,
  }) =>
      _goi(() => VinhUniClient.instance.put(
            duongDan,
            data: duLieu,
            options: _tuyChon(hanCho),
          ));

  static Future<ApiResponse> delete(
    String duongDan, {
    Object? duLieu,
    Duration? hanCho,
  }) =>
      _goi(() => VinhUniClient.instance.delete(
            duongDan,
            data: duLieu,
            options: _tuyChon(hanCho),
          ));

  /// Tải tệp lên (ảnh điểm danh, tệp đính kèm thông báo, văn bản cần ký).
  static Future<ApiResponse> tepLen(
    String duongDan, {
    required FormData duLieu,
    void Function(int daGui, int tong)? tienDo,
    Duration? hanCho,
  }) =>
      _goi(() => VinhUniClient.instance.post(
            duongDan,
            data: duLieu,
            onSendProgress: tienDo,
            options: _tuyChon(hanCho),
          ));

  static Options _tuyChon(Duration? hanCho) => Options(
        receiveTimeout: hanCho,
        sendTimeout: hanCho,
        // Dio mặc định ném ngoại lệ với mã ngoài 2xx. Vẫn để nguyên mặc định
        // đó, vì bộ chặn 401/403 cần ngoại lệ mới kích hoạt được. Việc chuyển
        // ngoại lệ thành ApiResponse do _goi() lo, sau khi bộ chặn đã chạy.
      );

  static Future<ApiResponse> _goi(Future<Response> Function() ham) async {
    try {
      final res = await ham();
      return _tuPhanHoi(res);
    } on DioException catch (e) {
      // Bộ chặn của VinhUniClient đã chạy xong ở đây (đưa về màn đăng nhập nếu
      // 401, hiện hộp thoại nếu 403). Việc còn lại là trả kết quả cho bên gọi.
      if (e.response != null) return _tuPhanHoi(e.response!);

      final loiKetNoi = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Máy chủ phản hồi chậm. Vui lòng thử lại.',
        DioExceptionType.connectionError =>
          'Không có kết nối mạng. Kiểm tra Wi-Fi hoặc dữ liệu di động.',
        DioExceptionType.cancel => 'Yêu cầu đã bị huỷ.',
        _ => 'Không kết nối được máy chủ.',
      };
      debugPrint('❌ [Api] ${e.requestOptions.path}: ${e.type} — ${e.message}');

      return ApiResponse(
        statusCode: 0,
        body: '',
        bodyBytes: Uint8List(0),
        loiMang: true,
        thongDiepLoi: loiKetNoi,
      );
    } catch (e) {
      debugPrint('❌ [Api] Lỗi không xác định: $e');
      return ApiResponse(
        statusCode: 0,
        body: '',
        bodyBytes: Uint8List(0),
        loiMang: true,
        thongDiepLoi: 'Đã xảy ra lỗi không mong muốn.',
      );
    }
  }

  static ApiResponse _tuPhanHoi(Response res) {
    var duLieu = res.data;

    // ⚠️ SỬA 18/08/2026 — nguyên nhân làm danh sách thông báo trống trơn.
    //
    // Dio chỉ tự giải mã JSON khi máy chủ trả đúng `Content-Type:
    // application/json`. Một số endpoint của trường trả JSON nhưng khai báo
    // content-type khác (hoặc không khai báo), nên Dio để nguyên chuỗi. Mã gọi
    // thì kiểm tra `duLieu is List` — không khớp — và trả về danh sách rỗng.
    //
    // Bản cũ dùng `json.decode(utf8.decode(bodyBytes))`, giải mã bất kể
    // content-type, nên không gặp vấn đề này. Nay khôi phục đúng hành vi đó.
    if (duLieu is String) {
      final rut = duLieu.trimLeft();
      if (rut.startsWith('{') || rut.startsWith('[')) {
        try {
          duLieu = jsonDecode(duLieu);
        } catch (_) {
          // Không phải JSON thật thì giữ nguyên chuỗi — bên gọi tự xử lý
        }
      }
    }

    final chuoi = duLieu == null
        ? ''
        : duLieu is String
            ? duLieu
            : jsonEncode(duLieu);

    return ApiResponse(
      statusCode: res.statusCode ?? 0,
      body: chuoi,
      bodyBytes: Uint8List.fromList(utf8.encode(chuoi)),
      data: duLieu,
      thongDiepLoi: res.statusCode != null && res.statusCode! >= 400
          ? _thongDiepTheoMa(res.statusCode!, duLieu)
          : '',
    );
  }

  /// Diễn giải mã lỗi thành câu người dùng hiểu được và biết phải làm gì.
  static String _thongDiepTheoMa(int ma, dynamic duLieu) {
    final chiTiet = duLieu is Map
        ? (duLieu['detail'] ?? duLieu['message'])?.toString()
        : null;

    return switch (ma) {
      400 => chiTiet ?? 'Dữ liệu gửi lên không hợp lệ.',
      401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      403 => chiTiet ?? 'Bạn không có quyền dùng chức năng này.',
      404 => 'Không tìm thấy dữ liệu.',
      408 => 'Máy chủ phản hồi chậm. Vui lòng thử lại.',
      413 => 'Tệp quá lớn.',
      429 => 'Bạn thao tác quá nhanh. Vui lòng đợi một lát.',
      >= 500 => 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
      _ => chiTiet ?? 'Đã xảy ra lỗi (mã $ma).',
    };
  }
}
