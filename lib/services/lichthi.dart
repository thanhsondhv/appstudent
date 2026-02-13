import 'dart:convert';
import 'package:http/http.dart' as http;

class LichThiService {
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn/api';

  // Lấy dữ liệu filter thô để xử lý lọc realtime ở View
  Future<List<dynamic>> getRawFilters(String userId) async {
    final uri = Uri.parse('$baseUrl/get-filters/$userId');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Lỗi API getRawFilters Lịch thi: $e");
    }
    return [];
  }

  Future<List<dynamic>> getExams({
    required String userId,
    required String namHoc,
    required String hocKy
  }) async {
    Map<String, String> queryParams = {
      'nam_hoc': namHoc,
      'hoc_ky': hocKy,
    };

    final uri = Uri.parse('$baseUrl/get-exams/$userId').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Lỗi Service getExams: $e");
    }
    return [];
  }
}