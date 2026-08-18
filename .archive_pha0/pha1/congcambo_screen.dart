//congcanbo.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class XepLoaiScreen extends StatefulWidget {
  final String hsid;
  final String chucNang;
  final String title;


  const XepLoaiScreen({
    super.key,
    required this.hsid,
    required this.chucNang,
    this.title = "Chi tiết"
  });

  @override
  State<XepLoaiScreen> createState() => _XepLoaiScreenState();
}

class _XepLoaiScreenState extends State<XepLoaiScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isControllerInitialized = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _initController();
    _fetchTokenAndLoadWeb();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) => setState(() => _isLoading = false),
          onWebResourceError: (error) => debugPrint("WebView Error: ${error.description}"),
        ),
      );
  }

  Future<void> _fetchTokenAndLoadWeb() async {
    try {
      // 1. Lấy Token dựa trên hsid động
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/get-token?hsid=${widget.hsid}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['token'] != null) {
          final String token = data['token'];

          // 2. Load Request với URL động dựa trên widget.chucNang
       final String targetUrl = 'http://canbo.vinhuni.edu.vn/mobile-call-url/${widget.chucNang}';
        print("🚀 Đang gọi URL: $targetUrl"); // Kiểm tra log xem nó có ra đúng .../xep-loai không
          
          await _controller.loadRequest(
            Uri.parse(targetUrl),
            headers: {
              'token': token, // Key 'token' như bạn đã test trên Postman
              'Accept': 'application/json',
            },
          );

          setState(() => _isControllerInitialized = true);
        } else {
          setState(() => _errorMessage = "Không lấy được token hợp lệ");
        }
      } else {
        setState(() => _errorMessage = "Lỗi Server: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _errorMessage = "Lỗi kết nối: $e");
    } finally {
      if (mounted && _errorMessage.isNotEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: vinhUniBlue,

        // 1. Sửa màu chữ tiêu đề
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),

        // 2. Sửa màu cho các Icon (nút Back, các nút chức năng bên phải)
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),

        // 3. Đảm bảo màu thanh trạng thái (Pin, Sóng) hiển thị đúng trên iOS/Android
        foregroundColor: Colors.white,

        elevation: 0,
      ),
      body: Stack(
        children: [
          if (_isControllerInitialized && _errorMessage.isEmpty)
            WebViewWidget(controller: _controller),

          if (_errorMessage.isNotEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            )),

          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}