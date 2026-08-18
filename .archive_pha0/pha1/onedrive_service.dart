import 'dart:convert';
import 'package:flutter/material.dart'; 
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:vinhuni_app/views/ms_login_screen.dart'; 
import 'package:vinhuni_app/services/vinhuni_api_client.dart';

class OneDriveService {
  final String _baseUrl = "https://graph.microsoft.com/v1.0";

  // --- PHẦN 1: QUẢN LÝ TOKEN & DUY TRÌ KẾT NỐI ---

  /// Hàm gác cổng: Tự động kiểm tra, gia hạn ngầm
  Future<String?> getValidToken(BuildContext context, {bool showLoginUI = true}) async {
    final prefs = await SharedPreferences.getInstance();
    
    String? token = prefs.getString('ms_access_token');
    int? expiry = prefs.getInt('ms_token_expiry');

    // Kiểm tra xem Token còn hạn không
    bool isExpired = expiry == null || DateTime.now().millisecondsSinceEpoch > expiry;

    if (token == null || isExpired) {
      debugPrint("🔄 Token 365 hết hạn, đang thử lấy lại ngầm...");
      
      // Lấy user_code chắc chắn đã được lưu ở Bước 1
      String? userCode = prefs.getString('user_code') ?? prefs.getString('student_id');
      
      if (userCode != null && userCode.isNotEmpty) {
        try {
          final response = await VinhUniClient.instance.post(
            '/api/auth/refresh-ms-token',
            data: {"user_code": userCode},
          );

          if (response.statusCode == 200 && response.data['status'] == 'success') {
            token = response.data['access_token'];
            await prefs.setString('ms_access_token', token!);
            await prefs.setInt('ms_token_expiry', DateTime.now().millisecondsSinceEpoch + 3500000); 
            debugPrint("✅ Đã đồng bộ Token 365 ngầm thành công!");
            return token; // Có chìa khóa, đi tiếp!
          }
        } catch (e) {
          debugPrint("⚠️ Lỗi đồng bộ ngầm: $e.");
        }
      }

      // Nếu KHÔNG THỂ gia hạn ngầm (API lỗi, hoặc user hủy kết nối O365):
      if (showLoginUI) {
        debugPrint("🚀 Bắt buộc kích hoạt Microsoft 365 UI...");
        final authResult = await _triggerMicrosoftLogin(context); 

        if (authResult != null && authResult.containsKey('access_token')) {
          token = authResult['access_token'];
          await prefs.setString('ms_access_token', token!);
          await prefs.setInt('ms_token_expiry', DateTime.now().millisecondsSinceEpoch + 3500000); 
          return token;
        }
      }
      
      return null; 
    }

    debugPrint("🚀 Sử dụng Token 365 hiện có (Vẫn còn hạn)");
    return token;
  }

  Future<Map<String, dynamic>?> _triggerMicrosoftLogin(BuildContext context) async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MSLoginScreen()), 
      );

      if (result != null && result is Map && result.containsKey('session_token')) {
        final String sessionToken = result['session_token'];
        
        final response = await VinhUniClient.instance.post(
          '/api/auth/verify-session',
          data: {"session_token": sessionToken},
        );

        if (response.statusCode == 200 && response.data['status'] == 'success') {
          final String msAccessToken = response.data['data']['ms_access_token'] ?? "";
          if (msAccessToken.isNotEmpty) {
            return {"access_token": msAccessToken};
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi kích hoạt Navigator: $e");
      return null;
    }
  }

  // --- PHẦN 2: THAO TÁC DỮ LIỆU ONEDRIVE (MICROSOFT GRAPH API) ---

  Map<String, String> _getHeaders(String token) {
    return {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };
  }

  Future<List<dynamic>> fetchItems(String token, {String folderId = "root"}) async {
    final url = Uri.parse("$_baseUrl/me/drive/items/$folderId/children");
    final response = await http.get(url, headers: _getHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body)['value'];
    throw Exception("Lỗi lấy dữ liệu từ OneDrive: ${response.body}");
  }

  Future<bool> uploadFileBytes(String token, String fileName, List<int> bytes, String folderId) async {
    String urlStr = folderId == "root" 
        ? "$_baseUrl/me/drive/root:/$fileName:/content"
        : "$_baseUrl/me/drive/items/$folderId:/$fileName:/content";

    final response = await http.put(
      Uri.parse(urlStr),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/octet-stream", 
      },
      body: bytes,
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  Future<bool> createNewFolder(String token, String parentId, String folderName) async {
    final url = Uri.parse("$_baseUrl/me/drive/items/$parentId/children");
    final response = await http.post(
      url,
      headers: _getHeaders(token),
      body: jsonEncode({
        "name": folderName,
        "folder": {},
        "@microsoft.graph.conflictBehavior": "rename"
      }),
    );
    return response.statusCode == 201;
  }

  Future<bool> deleteItem(String token, String itemId) async {
    final url = Uri.parse("$_baseUrl/me/drive/items/$itemId");
    final response = await http.delete(url, headers: _getHeaders(token));
    return response.statusCode == 204;
  }
  /// 🔥 HÀM MỚI: Đồng bộ mã OneDrive ngầm ngay khi đăng nhập App hoặc khởi động App
  /// 🔥 HÀM MỚI: Đồng bộ mã OneDrive ngầm ngay khi đăng nhập App hoặc khởi động App
  Future<bool> syncTokenOnAppLaunch(String userCode) async {
    if (userCode.isEmpty) return false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      String cleanUserCode = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
      
      debugPrint("🔄 [O365] Đang âm thầm nạp sẵn liên kết OneDrive cho: $cleanUserCode");
      
      final response = await VinhUniClient.instance.post(
        '/api/auth/refresh-ms-token',
        data: {"user_code": cleanUserCode},
      );

      if (response.statusCode == 200) {
        if (response.data['status'] == 'success') {
          String? token = response.data['access_token'];
          if (token != null && token.isNotEmpty) {
            await prefs.setString('ms_access_token', token);
            await prefs.setInt('ms_token_expiry', DateTime.now().millisecondsSinceEpoch + 3500000);
            debugPrint("✅ [O365] Đã kích hoạt và nạp sẵn liên kết OneDrive thành công!");
            return true;
          }
        } else {
        
          debugPrint("❌ [PYTHON TỪ CHỐI]: ${response.data['message']}");
          if (response.data['ms_error'] != null) {
             debugPrint("❌ [LỖI TỪ MICROSOFT]: ${response.data['ms_error']}");
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ [O365] Lỗi sập API nạp ngầm mã OneDrive: $e");
    }
    return false;
  }
  Future<void> initializeVinhUniStructure(String token) async {
    final folders = ['Nhat_Ky_AI', 'Bai_Tap_Lon', 'Tai_Lieu_Hoc_Tap'];
    for (var folder in folders) {
      final url = Uri.parse("$_baseUrl/me/drive/root:/$folder");
      await http.patch(
        url, 
        headers: _getHeaders(token), 
        body: jsonEncode({
          "name": folder, 
          "folder": {}, 
          "@microsoft.graph.conflictBehavior": "replace" 
        })
      );
    }
  }
}