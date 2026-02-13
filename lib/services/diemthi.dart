import 'dart:convert';
import 'package:http/http.dart' as http;

class DiemThiService {
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn/api';

  // Lấy dữ liệu lọc thô để xử lý realtime ở View
  Future<List<dynamic>> getRawFilters(String userId) async {
    final uri = Uri.parse('$baseUrl/get-filters/$userId');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return json.decode(response.body); // Trả về List các object {nam, ky, ...}
      }
    } catch (e) {
      print("Lỗi API getRawFilters: $e");
    }
    return [];
  }

  Future<List<dynamic>> getGrades({required String userId, required String namHoc, required String hocKy}) async {
    final uri = Uri.parse('$baseUrl/get-grades/$userId').replace(
        queryParameters: {'nam_hoc': namHoc, 'hoc_ky': hocKy}
    );
    try {
      final response = await http.get(uri);
      return response.statusCode == 200 ? json.decode(response.body) : [];
    } catch (e) {
      return [];
    }
  }
}