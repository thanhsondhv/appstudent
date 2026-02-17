import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AuthService {
  static const String baseUrl = 'https://mobi.vinhuni.edu.vn'; 

  Future<Map<String, dynamic>?> login(String user, String pass) async {
    final loginUri = Uri.parse('$baseUrl/api/login');
    try {
      final response = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user.trim(),
          'password': pass.trim()
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
          return jsonResponse['data']; 
        }
      }
      return null;
    } catch (e) {
      debugPrint("🔥 Lỗi kết nối: $e");
      return null;
    }
  }
}