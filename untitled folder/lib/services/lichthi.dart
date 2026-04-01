import 'dart:convert';
import 'package:http/http.dart' as http;

class LichThiService {
  // Địa chỉ API của hệ thống
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn/api';

  /// 1. Lấy dữ liệu bộ lọc (Năm học, Học kỳ)
  /// Giúp hiển thị danh sách chọn ở màn hình Lịch thi
  Future<List<dynamic>> getRawFilters(String userId) async {
    final uri = Uri.parse('$baseUrl/get-filters/$userId');
    
    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 20), // Đợi tối đa 20 giây
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print("Lỗi Server Filters Lịch thi: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("❌ Lỗi kết nối getRawFilters Lịch thi: $e");
      return [];
    }
  }

  /// 2. Lấy danh sách Lịch thi chi tiết
  /// Đã tối ưu để nhận diện đúng Năm học (2025-2026) và Học kỳ (1, 2.1, 2.2)
  Future<List<dynamic>> getExams({
    required String userId,
    required String namHoc,
    required String hocKy,
  }) async {
    // Xây dựng URI với các tham số lọc gửi về Backend
    final uri = Uri.parse('$baseUrl/get-exams/$userId').replace(
      queryParameters: {
        'nam_hoc': namHoc, // Gửi chuỗi: "2025-2026"
        'hoc_ky': hocKy,   // Gửi chuỗi: "Học kỳ 1" hoặc "Học kỳ 2.1"
      },
    );

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 20),
      );

      if (response.statusCode == 200) {
        // Trả về danh sách gồm các field: TenHocPhan, NgayThi, Phong, Gio, SBD
        return json.decode(response.body);
      } else {
        print("Lỗi Server getExams: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("❌ Lỗi Service getExams: $e");
      return [];
    }
  }
}