import 'package:flutter/material.dart';
import '../core/api/may_chu.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MSLoginScreen extends StatefulWidget {
  const MSLoginScreen({super.key});

  @override
  State<MSLoginScreen> createState() => _MSLoginScreenState();
}

class _MSLoginScreenState extends State<MSLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  // 🔥 URL API CỦA SERVER SƠN: Để Server tự điều hướng sang Microsoft
  final String serverAuthUrl = "${MayChu.diaChi}/login/microsoft";
  final String deepLinkScheme = "vinhuni-app://login_success";

  @override
  void initState() {
    super.initState();
    
    // 1. Xóa sạch Cookie để đảm bảo Thầy/Cô có thể chọn tài khoản khác nếu muốn
    WebViewCookieManager().clearCookies();

    // 2. Khởi tạo Controller với luồng bắt Deep Link từ Server
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Giả lập trình duyệt Safari trên iPhone để Microsoft không chặn
      ..setUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            // 🎯 BẮT DEEP LINK TỪ SERVER GỬI VỀ SAU KHI ĐĂNG NHẬP XONG
            if (request.url.contains(deepLinkScheme)) {
              debugPrint("🎯 [O365] Đã bắt được kết quả từ Server VinhUni: ${request.url}");
              _handleServerResponse(request.url);
              return NavigationDecision.prevent; // Ngăn chặn tải tiếp để tránh lỗi -999
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            // 🔥 CHỐNG LỖI "GIÁN ĐOẠN": Bỏ qua mã lỗi -999 đặc thù của iOS
            if (error.errorCode == -999 || error.description.contains("interrupted")) {
              return;
            }
            debugPrint("❌ WebView Error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(serverAuthUrl));
  }

  // 🔥 HÀM XỬ LÝ KẾT QUẢ TỪ SERVER
  void _handleServerResponse(String url) {
    final uri = Uri.parse(url);
    // Lấy session_token (Handshake) mà Server đã tạo và lưu vào SQL
    final sessionToken = uri.queryParameters['session_token'];

    if (sessionToken != null) {
      debugPrint("✅ Đã lấy được Session Token từ Server!");
      
      // Trả session_token về cho màn hình OneDriveManager để gọi API verify-session
      if (mounted) {
        Navigator.pop(context, {
          'session_token': sessionToken,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Kết nối Microsoft 365", 
          style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4))),
        ],
      ),
    );
  }
}