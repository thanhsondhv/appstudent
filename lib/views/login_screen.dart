import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

import '../services/login.dart';
import '../services/notification_service.dart';

class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key});

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  // --- CONTROLLERS & STATES ---
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _appLinks = AppLinks(); // Lắng nghe Deep Link từ trình duyệt

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscureText = true;

  // Màu thương hiệu VinhUni
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color accentBlue = const Color(0xFF0078D4);

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    
    // 1. Khởi tạo lắng nghe Deep Link (Office 365 Callback)
    _initDeepLinkListener();

    // 2. Khởi tạo hiệu ứng chuyển động (Animation)
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    // Giải phóng bộ nhớ khi thoát màn hình
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
  // =========================================================
  // LAYER 1: LOGIC ĐĂNG NHẬP FACE ID
  // =========================================================
  Future<void> _onFaceIDPressed() async {
  final ImagePicker picker = ImagePicker();
  
  try {
    // -------------------------------------------------------
    // BƯỚC 1: CHỤP ẢNH NHÌN THẲNG
    // -------------------------------------------------------
    _showStatusSnackBar("BƯỚC 1: Hãy nhìn thẳng vào camera và chụp ảnh", isError: false);
    
    final XFile? photoF = await picker.pickImage(
      source: ImageSource.camera, 
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85, // Nén nhẹ để gửi ảnh nhanh hơn
    );
    
    if (photoF == null) return; // Sinh viên hủy chụp

    // -------------------------------------------------------
    // BƯỚC 2: CHỤP ẢNH NGHIÊNG ĐẦU (ĐỂ CHECK 3D)
    // -------------------------------------------------------
    // Đợi 1 chút để sinh viên đọc hướng dẫn
    await Future.delayed(const Duration(milliseconds: 500));
    
    _showStatusSnackBar("BƯỚC 2: Hãy QUAY ĐẦU nhẹ sang bên và chụp ảnh", isError: false);
    
    final XFile? photoP = await picker.pickImage(
      source: ImageSource.camera, 
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
    
    if (photoP == null) return;

    // -------------------------------------------------------
    // BƯỚC 3: GỬI LÊN SERVER XỬ LÝ AI
    // -------------------------------------------------------
    setState(() => _isLoading = true);

    // Gọi đến AuthService đã tích hợp phương thức loginByFace
    final userData = await AuthService().loginByFace(
      photoFront: File(photoF.path),
      photoPose: File(photoP.path),
    );

    if (userData != null) {
      // THÀNH CÔNG: Lấy student_id và full_name đã được Backend ghép Họ + Tên
      final String userId = userData['student_id'].toString();
      final String fullName = userData['full_name'] ?? "Sinh viên VinhUni";

      debugPrint("✅ Face ID thành công: $fullName");

      // Gọi hàm lưu session và vào trang Home
      await _executeSuccessfulLogin(userId, fullName);
      
    } else {
      // THẤT BẠI: AI báo không khớp hoặc ảnh giả mạo (2D)
      _showStatusSnackBar("Face ID không khớp hoặc phát hiện ảnh giả mạo. Vui lòng thử lại dứt khoát hơn!", isError: true);
    }

  } catch (e) {
    debugPrint("🔥 Lỗi FaceID: $e");
    _showStatusSnackBar("Không thể khởi động Camera hoặc lỗi kết nối hệ thống.", isError: true);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

// --- HÀM HỖ TRỢ HIỂN THỊ THÔNG BÁO ---
void _showStatusSnackBar(String message, {bool isError = true}) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).clearSnackBars(); // Xóa các thông báo cũ
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: isError ? Colors.red.shade700 : Colors.blue.shade700,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 4 : 2),
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
  // =========================================================
  // LAYER 1: LOGIC ĐĂNG NHẬP OFFICE 365 (DEEP LINK)
  // =========================================================

  void _initDeepLinkListener() {
    // TRƯỜNG HỢP 1: Lắng nghe khi App đang chạy (Background/Foreground)
    _appLinks.uriLinkStream.listen((uri) {
      debugPrint("🔗 Nhận link khi App đang chạy: $uri");
      _processLoginUri(uri);
    }, onError: (err) {
      debugPrint("⚠️ Lỗi Stream Deep Link: $err");
    });

    // TRƯỜNG HỢP 2: Xử lý khi App bị đóng hoàn toàn (Cold Start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint("🚀 Nhận link khi khởi động App: $uri");
        _processLoginUri(uri);
      }
    }).catchError((err) {
      debugPrint("⚠️ Lỗi khởi tạo Deep Link: $err");
    });
  }

  void _processLoginUri(Uri uri) async {
    // Kiểm tra scheme và host khớp với cấu hình trong AndroidManifest/Info.plist
    if (uri.scheme == 'vinhuni-app' && uri.host == 'login_success') {
      final userId = uri.queryParameters['user_id'];
      final name = uri.queryParameters['name'];

      if (userId != null) {
        debugPrint("✅ Office 365 Login Success: ID=$userId, Name=$name");
        
        // Gọi hàm thực thi đăng nhập thành công (Lưu session, chuyển trang Home)
        await _executeSuccessfulLogin(userId, name ?? "Sinh viên1");
      }
    }
  }

  Future<void> _handleMicrosoftLogin() async {
    setState(() => _isLoading = true);
    try {
      // URL này trỏ đến Backend Python đã cấu hình Azure AD của bạn
      final loginUrl = Uri.parse("https://mobi.vinhuni.edu.vn/login/microsoft");
      
      if (await canLaunchUrl(loginUrl)) {
        await launchUrl(loginUrl, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar("Không thể mở trình duyệt đăng nhập!");
      }
    } catch (e) {
      _showErrorSnackBar("Lỗi kết nối hệ thống Office 365");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hàm dùng chung để xử lý sau khi đăng nhập thành công (cho cả 2 phương thức)
  Future<void> _executeSuccessfulLogin(String userId, String fullName) async {
    // Kiểm tra dữ liệu đầu vào trước khi lưu
    debugPrint("🚀 --- TIẾN TRÌNH LƯU ĐĂNG NHẬP ---");
    debugPrint("📍 Mã SV: $userId");
    debugPrint("📍 Họ tên: $fullName");

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Lưu ID sinh viên
      await prefs.setString('user_id', userId);

      // 2. Lưu Họ tên sinh viên (Dùng khóa 'full_name' để khớp với HomeScreen)
      // Nếu fullName bị rỗng hoặc null, sẽ dự phòng bằng "Sinh viên VinhUni"
      String finalName = (fullName.trim().isEmpty) ? "Sinh viên VinhUni" : fullName;
      await prefs.setString('full_name', finalName);

      debugPrint("✅ Đã ghi vào máy: ID=$userId, Name=$finalName");

      // 3. Thiết lập thông báo (Firebase Cloud Messaging)
      await _handleNotificationTopic(true);
      await NotificationService().syncTokenToServer(userId);

      // 4. Chuyển hướng vào trang Home
      if (mounted) {
        debugPrint("➡️ Đang chuyển hướng vào trang chủ...");
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      debugPrint("❌ Lỗi khi thực hiện lưu đăng nhập: $e");
      _showErrorSnackBar("Không thể lưu thông tin phiên đăng nhập.");
    }
  }

  // =========================================================
  // LAYER 2: LOGIC ĐĂNG NHẬP TRUYỀN THỐNG & FCM
  // =========================================================

  Future<void> _handleNotificationTopic(bool isSubscribing) async {
    try {
      if (isSubscribing) {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic("vinhuni_all_students");
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi Topic: $e");
    }
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      emailController.text = prefs.getString('saved_user') ?? "";
      passwordController.text = prefs.getString('saved_pwd') ?? "";
      _rememberMe = prefs.getBool('remember_me') ?? false;
    });
  }

  Future<void> _saveAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_user', emailController.text);
      await prefs.setString('saved_pwd', passwordController.text);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_user');
      await prefs.remove('saved_pwd');
      await prefs.setBool('remember_me', false);
    }
  }

  // Trong màn hình login_screen.dart, tại hàm _handleLogin:

void _handleLogin() async {
  if (emailController.text.isEmpty || passwordController.text.isEmpty) {
    _showErrorSnackBar("Vui lòng nhập đầy đủ tài khoản và mật khẩu!");
    return;
  }

  setState(() => _isLoading = true);

  // userData bây giờ sẽ là một Map (chứa thông tin) hoặc null
  final userData = await AuthService().login(
    emailController.text.trim(),
    passwordController.text.trim(),
  );

  if (mounted) setState(() => _isLoading = false);

  if (userData != null) {
    // ĐÃ HẾT LỖI: Vì userData bây giờ là Map nên dùng được dấu []
    final userId = userData['student_id'].toString();
    final fullName = userData['full_name'] ?? "Sinh viên VinhUni";

    await _saveAccountInfo();
    
    // Gửi tên thật vào hàm lưu để không bị hiện chữ "SINH VIÊN"
    await _executeSuccessfulLogin(userId, fullName); 
  } else {
    _showErrorSnackBar("Thông tin đăng nhập không chính xác!");
  }
}

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(message))]),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  // =========================================================
  // LAYER 3: GIAO DIỆN (UI MODERN PRO)
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: SizedBox(
            height: size.height,
            child: Stack(
              children: [
                // 1. BACKGROUND GRADIENT HEADER
                _buildHeader(size),

                // 2. LOGIN FORM CARD
                _buildLoginForm(size),

                // 3. FOOTER OPTIONS
                _buildFooterOptions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Size size) {
    return Positioned(
      top: 0, left: 0, right: 0,
      height: size.height * 0.45,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [vinhUniBlue, accentBlue],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(60), bottomRight: Radius.circular(60)),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Image.asset('assets/images/logo.png', height: 80, errorBuilder: (_,__,___) => Icon(Icons.school, size: 80, color: vinhUniBlue)),
              ),
              const SizedBox(height: 15),
              const Text("CỔNG SINH VIÊN", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Text("Đại học Vinh - Vinh University", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(Size size) {
    return Positioned(
      top: size.height * 0.35,
      left: 20, right: 20,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 15))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Đăng nhập", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: vinhUniBlue)),
              const SizedBox(height: 25),
              _buildModernInput(controller: emailController, label: "Mã sinh viên", icon: Icons.person_rounded),
              const SizedBox(height: 20),
              _buildModernInput(controller: passwordController, label: "Mật khẩu", icon: Icons.lock_rounded, isPassword: true),
              const SizedBox(height: 15),
              _buildRememberMeRow(),
              const SizedBox(height: 25),
              _buildLoginButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              height: 24, width: 24,
              child: Checkbox(
                value: _rememberMe,
                activeColor: vinhUniBlue,
                onChanged: (v) => setState(() => _rememberMe = v!),
              ),
            ),
            const SizedBox(width: 8),
            const Text("Ghi nhớ", style: TextStyle(fontSize: 13)),
          ],
        ),
        TextButton(onPressed: (){}, child: const Text("Quên mật khẩu?", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: vinhUniBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: _isLoading 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("ĐĂNG NHẬP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildFooterOptions() {
    return Positioned(
      bottom: 30, left: 0, right: 0,
      child: Column(
        children: [
          const Text("Hoặc đăng nhập bằng", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialBtn(
                icon: Icons.face_rounded, 
                label: "Face ID", 
                color: Colors.purple, 
                onTap: _onFaceIDPressed, // 👈 Gán lệnh gọi hàm Tính năng Face ID 
               ),
              const SizedBox(width: 20),
              _buildSocialBtn(
                icon: Icons.account_balance_rounded, 
                label: "Office 365", 
                color: const Color(0xFFEA3E23), 
                onTap: _handleMicrosoftLogin
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscureText : false,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: vinhUniBlue.withOpacity(0.6)),
          suffixIcon: isPassword ? IconButton(
            icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscureText = !_obscureText),
          ) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSocialBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}