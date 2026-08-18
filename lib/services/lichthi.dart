import 'package:flutter/foundation.dart';

import '../core/api/api.dart';

/// Tra cứu lịch thi.
///
/// Chuyển sang [Api] ngày 18/08/2026 (Pha 1) — xem ghi chú ở
/// `lib/services/diemthi.dart` về lý do.
class LichThiService {
  /// 1. Lấy dữ liệu bộ lọc (Năm học, Học kỳ)
  /// Giúp hiển thị danh sách chọn ở màn hình Lịch thi
  Future<List<dynamic>> getRawFilters(String userId) async {
    final res = await Api.get(
      '/api/get-filters/$userId',
      hanCho: const Duration(seconds: 20),
    );

    if (!res.thanhCong) {
      debugPrint('❌ [LịchThi] Không lấy được bộ lọc: ${res.thongDiepLoi}');
      return [];
    }
    return _danhSach(res, 'getRawFilters');
  }

  /// 2. Lấy danh sách Lịch thi chi tiết
  /// Nhận diện đúng Năm học (2025-2026) và Học kỳ (1, 2.1, 2.2)
  Future<List<dynamic>> getExams({
    required String userId,
    required String namHoc,
    required String hocKy,
  }) async {
    final res = await Api.get(
      '/api/get-exams/$userId',
      thamSo: {
        'nam_hoc': namHoc, // Gửi chuỗi: "2025-2026"
        'hoc_ky': hocKy,   // Gửi chuỗi: "Học kỳ 1" hoặc "Học kỳ 2.1"
      },
      hanCho: const Duration(seconds: 20),
    );

    if (!res.thanhCong) {
      debugPrint('❌ [LịchThi] Không lấy được lịch thi: ${res.thongDiepLoi}');
      return [];
    }
    // Mỗi phần tử gồm: TenHocPhan, NgayThi, Phong, Gio, SBD
    return _danhSach(res, 'getExams');
  }

  List<dynamic> _danhSach(ApiResponse res, String ten) {
    final duLieu = res.data;
    if (duLieu is List) return duLieu;
    if (duLieu is Map && duLieu['data'] is List) return duLieu['data'] as List;

    debugPrint('⚠️ [LịchThi] $ten trả về kiểu dữ liệu lạ: ${duLieu.runtimeType}');
    return [];
  }
}
