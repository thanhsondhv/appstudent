import 'package:flutter/foundation.dart';

import '../core/api/api.dart';

/// Tra cứu điểm thi.
///
/// Chuyển sang [Api] ngày 18/08/2026 (Pha 1). Trước đây gọi thẳng
/// `package:http` nên mọi yêu cầu đi ra không kèm token, không có mã thiết bị,
/// và khi phiên hết hạn thì màn hình chỉ hiện danh sách rỗng thay vì đưa người
/// dùng về đăng nhập.
class DiemThiService {
  /// 1. Lấy dữ liệu bộ lọc (Năm học, Học kỳ, Tuần)
  /// Trả về danh sách thô để View tự xử lý logic lọc Realtime
  Future<List<dynamic>> getRawFilters(String userId) async {
    final res = await Api.get(
      '/api/get-filters/$userId',
      // SQL Server có thể mất vài giây cho truy vấn này
      hanCho: const Duration(seconds: 20),
    );

    if (!res.thanhCong) {
      debugPrint('❌ [ĐiểmThi] Không lấy được bộ lọc: ${res.thongDiepLoi}');
      return [];
    }
    return _danhSach(res, 'getRawFilters');
  }

  /// 2. Lấy danh sách điểm số theo Năm học và Học kỳ
  Future<List<dynamic>> getGrades({
    required String userId,
    required String namHoc,
    required String hocKy,
  }) async {
    final res = await Api.get(
      '/api/get-grades/$userId',
      thamSo: {
        'nam_hoc': namHoc, // Ví dụ: "2025-2026"
        'hoc_ky': hocKy,   // Ví dụ: "Học kỳ 1"
      },
      hanCho: const Duration(seconds: 20),
    );

    if (!res.thanhCong) {
      debugPrint('❌ [ĐiểmThi] Không lấy được điểm: ${res.thongDiepLoi}');
      return [];
    }
    return _danhSach(res, 'getGrades');
  }

  /// Đọc danh sách từ phản hồi.
  ///
  /// Máy chủ trả về mảng thuần ở các endpoint này, nhưng vẫn kiểm tra kiểu:
  /// nếu một ngày nào đó đổi sang dạng `{"data": [...]}` thì lỗi hiện ra trong
  /// nhật ký chứ không phải một ngoại lệ ép kiểu giữa lúc dựng giao diện.
  List<dynamic> _danhSach(ApiResponse res, String ten) {
    final duLieu = res.data;
    if (duLieu is List) return duLieu;
    if (duLieu is Map && duLieu['data'] is List) return duLieu['data'] as List;

    debugPrint('⚠️ [ĐiểmThi] $ten trả về kiểu dữ liệu lạ: ${duLieu.runtimeType}');
    return [];
  }
}
