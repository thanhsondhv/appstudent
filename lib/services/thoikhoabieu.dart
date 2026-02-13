import 'dart:convert';
import 'package:http/http.dart' as http;

class ScheduleService {
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn/api';

  // Lấy dữ liệu thô để UI tự xử lý lọc realtime
  Future<List<dynamic>> getRawFilters(String userId) async {
    final uri = Uri.parse('$baseUrl/get-filters/$userId');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return json.decode(response.body); // Trả về List các Object {nam, ky, tuan}
      }
    } catch (e) {
      print("Lỗi API getRawFilters: $e");
    }
    return [];
  }

  // Lấy thời khóa biểu chi tiết
  Future<List<dynamic>> getSchedule({
    required String userId,
    required String namHoc,
    required String hocKy,
    required String tuan,
  }) async {
    final uri = Uri.parse('$baseUrl/get-schedule/$userId').replace(
        queryParameters: {
          'nam_hoc': namHoc,
          'hoc_ky': hocKy,
          'tuan': tuan,
        }
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Lỗi API getSchedule: $e");
    }
    return [];
  }
}