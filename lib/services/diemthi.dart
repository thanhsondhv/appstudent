import 'dart:convert';
import 'package:http/http.dart' as http;

class DiemThiService {
  // Base URL của API
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn/api';

  /// 1. Lấy dữ liệu bộ lọc (Năm học, Học kỳ, Tuần)
  /// Trả về danh sách thô để View tự xử lý logic lọc Realtime
  Future<List<dynamic>> getRawFilters(String userId) async {
    final uri = Uri.parse('$baseUrl/get-filters/$userId');
    
    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 20),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print("Lỗi Server Filters: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("❌ Lỗi kết nối getRawFilters: $e");
      return [];
    }
  }

  /// 2. Lấy danh sách điểm số theo Năm học và Học kỳ
  /// Các tham số namHoc và hocKy sẽ được gửi dưới dạng Query Parameters
  Future<List<dynamic>> getGrades({
    required String userId, 
    required String namHoc, 
    required String hocKy
  }) async {
    // Tạo URI với các tham số lọc
    final uri = Uri.parse('$baseUrl/get-grades/$userId').replace(
      queryParameters: {
        'nam_hoc': namHoc, // Ví dụ: "2025-2026"
        'hoc_ky': hocKy,   // Ví dụ: "Học kỳ 1"
      }
    );

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 20), // Đợi tối đa 20s để SQL Server xử lý
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print("Lỗi Server Grades: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("❌ Lỗi kết nối getGrades: $e");
      return [];
    }
  }
}