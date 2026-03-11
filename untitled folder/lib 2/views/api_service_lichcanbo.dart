import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'schedule_canbo.dart';

class ApiServiceLichCanbo {
  // URL sản xuất Sơn cung cấp
  static const String baseUrl = "https://mobi.vinhuni.edu.vn/api/admin/schedule";
  
  // Khóa định danh để lưu trữ dữ liệu vào bộ nhớ máy
  static const String _cacheKey = "cache_weekly_schedule";

  /// Lấy danh sách lịch công tác (Ưu tiên Network, lỗi sẽ dùng Cache)
  Future<List<WeeklySchedule>> fetchSchedules() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    try {
      // 1. Gửi yêu cầu lấy dữ liệu mới nhất từ Server
      final response = await http.get(Uri.parse('$baseUrl/view-data'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final String rawBody = response.body;
        
        // 2. Lưu phản hồi vào bộ nhớ đệm để dùng cho lần sau hoặc khi mất mạng
        await prefs.setString(_cacheKey, rawBody);
        
        return _parseData(rawBody);
      }
    } catch (e) {
      print("⚠️ Lỗi kết nối hoặc timeout: $e. Đang cố gắng đọc từ bộ nhớ đệm...");
    }

    // 3. Nếu mạng lỗi, kiểm tra xem trong máy có dữ liệu cũ không
    final String? cachedData = prefs.getString(_cacheKey);
    if (cachedData != null) {
      print("✅ Đã lấy dữ liệu từ bộ nhớ đệm thành công.");
      return _parseData(cachedData);
    }

    // Nếu cả mạng và máy đều không có dữ liệu
    return [];
  }

  /// Lệnh cưỡng bức đồng bộ dữ liệu mới từ Web nguồn
  Future<String> syncSchedule(String week) async {
    try {
      // Tham số week nhận giá trị 'current' hoặc 'next'
      final response = await http.get(Uri.parse('$baseUrl/sync-weekly?week=$week'));
      
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        return data['message'] ?? "Đồng bộ thành công";
      } else {
        return "Lỗi server: ${response.statusCode}";
      }
    } catch (e) {
      return "Lỗi kết nối khi đồng bộ: $e";
    }
  }

  /// Hàm hỗ trợ phân tích chuỗi JSON sang danh sách Model
  List<WeeklySchedule> _parseData(String jsonString) {
    final Map<String, dynamic> decoded = json.decode(jsonString);
    final List<dynamic> dataList = decoded['data'] ?? [];
    
    // Ánh xạ các trường từ SQL Server sang đối tượng Dart
    return dataList.map((item) => WeeklySchedule.fromJson(item)).toList();
  }
}