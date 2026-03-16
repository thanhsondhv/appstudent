import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'dart:convert'; // Thêm để dùng jsonEncode/decode
import 'package:vinhuni_app/screens/forgot_password_screen.dart';
import 'face_scan_pro_screen.dart';
import '../handlers/login_handler.dart'; 
import '../services/auth_service.dart';
import '../services/notification_service.dart'; // Đảm bảo import này đúng đường dẫn
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Mới
import 'package:local_auth/local_auth.dart'; // Mới
class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key}); 

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  // --- KHAI BÁO BIẾN ---
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _appLinks = AppLinks();
  final _authService = AuthService(); 

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscureText = true;

  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color accentBlue = const Color(0xFF0078D4);

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _initDeepLinkListener();

    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- LOGIC XỬ LÝ ---

  void _initDeepLinkListener() {
    _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _processLoginUri(uri);
    });
  }

bool _isProcessingLogin = false;

void _processLoginUri(Uri uri) async {
  if (!mounted || _isProcessingLogin) return; 
  
  if ((uri.scheme == 'vinhuni-app' && uri.host == 'login_success') || 
      (uri.path.contains('login-success'))) {
    
    _isProcessingLogin = true; 
    
    final userId = uri.queryParameters['user_id'];
    final name = uri.queryParameters['name'];
    final role = uri.queryParameters['role'];

    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role ?? 'SinhVien'); 
      await prefs.setString('user_code', userId); 
      await prefs.setBool('is_logged_in', true);

      if (!mounted) return;
      
      await LoginHandler.executeSuccessfulLogin(context, userId, name ?? "Người dùng", role: role);
      _isProcessingLogin = false; 
    }
  }
}

  // 🔥 CẬP NHẬT LOGIC OFFICE 365: Hỗ trợ chọn Email và thoát session
  Future<void> _handleMicrosoftLogin() async {
    // 1. Base URL login
    String baseUrl = "https://mobi.vinhuni.edu.vn/login/microsoft";
    
    // 2. Thêm prompt=select_account để người dùng luôn được chọn Email
    String finalUrl = "$baseUrl?prompt=select_account";
    
    // 3. Gợi ý Email nếu người dùng đã gõ vào ô "Mã sinh viên"
    if (emailController.text.isNotEmpty) {
      finalUrl += "&login_hint=${emailController.text.trim()}@vinhuni.edu.vn";
    }

    final Uri url = Uri.parse(finalUrl);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(
        url, 
        mode: LaunchMode.externalApplication, // Mở Safari để dùng Auto-fill mật khẩu hệ thống
      );
    }
  }

  void _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập đầy đủ thông tin!");
      return;
    }
    setState(() => _isLoading = true);
    
    final userData = await _authService.login(emailController.text.trim(), passwordController.text.trim());
    
    if (mounted) setState(() => _isLoading = false);

    if (userData != null) {
      await _saveAccountInfo();
      if (!mounted) return; 
      await LoginHandler.executeSuccessfulLogin(context, userData['student_id'].toString(), userData['full_name']);
    } else {
      _showErrorSnackBar("Tài khoản hoặc mật khẩu không chính xác!");
    }
  }

  void _handleFaceIDLoginPro() async {
  // 1. Đọc thông tin "két sắt" xem máy đã lưu tài khoản nào chưa
  String? savedUser = await _storage.read(key: 'bio_user');
  String? savedPwd = await _storage.read(key: 'bio_pwd');
  String currentInput = emailController.text.trim();

  // 2. Kiểm tra logic: Chỉ cho phép Face ID nếu:
  // - Máy đã có dữ liệu lưu (savedUser != null)
  // - VÀ (Người dùng chưa gõ gì HOẶC gõ đúng cái mã đã lưu)
  if (savedUser != null && savedPwd != null && (currentInput.isEmpty || currentInput == savedUser)) {
    
    // 🔥 TRƯỜNG HỢP 1: DÙNG FACE ID MÁY CÁ NHÂN (Cực nhanh)
    try {
      bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Xác thực để đăng nhập VinhUni',
        options: const AuthenticationOptions(
          biometricOnly: true, // Chỉ dùng FaceID/Vân tay chính chủ máy
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        if (!mounted) return;
        setState(() => _isLoading = true);

        // Gọi API login thông thường bằng ID/Pass đã lưu (không cần quét AI nữa)
        final userData = await _authService.login(savedUser, savedPwd);
        
        if (userData != null) {
          if (!mounted) return;
          await LoginHandler.executeSuccessfulLogin(
            context, 
            userData['student_id'].toString(), 
            userData['full_name']
          );
        } else {
          _showErrorSnackBar("Thông tin xác thực đã hết hạn hoặc mật khẩu đã đổi!");
        }
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      _showErrorSnackBar("Lỗi Face ID máy: $e");
    }
  } else {
    // 🔥 TRƯỜNG HỢP 2: LẦN ĐẦU ĐĂNG KÝ HOẶC ĐỔI TÀI KHUÔN MẶT MỚI
    // (Vẫn quét mặt AI để so khớp Vector với Server nhà trường)

    // A. Xác thực quyền sở hữu thiết bị
    final isDeviceOwner = await _authService.authenticateWithDevice();
    if (!isDeviceOwner) return;

    // B. Kiểm tra quyền Camera (đã tích hợp PermissionHandler)
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isPermanentlyDenied || status.isDenied) {
      _showErrorSnackBar("Bạn cần cấp quyền Camera để thực hiện nhận diện khuôn mặt!");
      return;
    }

    if (!mounted) return;
    
    // C. Mở màn hình quét AI (FaceScanProScreen)
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FaceScanProScreen()), 
    );

    // D. Xử lý kết quả từ Server AI sau khi quét
    if (result != null && result['front'] != null) {
      setState(() => _isLoading = true);
      final aiResult = await _authService.loginByFacePro(frontFile: result['front']);

      if (aiResult['status'] == 'SUCCESS') {
        if (mounted) {
          // AI xác nhận đúng chủ nhân -> Hỏi xem có muốn lưu Face ID vào máy này không
          _showBiometricEnrollmentDialog(
            aiResult['student_id'].toString(), 
            aiResult['password'] ?? passwordController.text, // Ưu tiên pass từ server hoặc ô nhập
            aiResult['full_name'] ?? "Người dùng",
            aiResult['role']
          );
        }
      } else {
        _showErrorSnackBar(aiResult['message'] ?? "Không nhận diện được khuôn mặt trên hệ thống!");
      }
      
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
void _showBiometricEnrollmentDialog(String user, String pass, String name, String? role) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Text("Kích hoạt Face ID cá nhân?"),
      content: const Text("Xác thực AI thành công! Bạn có muốn lưu Face ID vào máy này để lần sau đăng nhập nhanh hơn không?"),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await LoginHandler.executeSuccessfulLogin(context, user, name, role: role);
          }, 
          child: const Text("ĐỂ SAU")
        ),
        ElevatedButton(
          onPressed: () async {
            // Lưu mật khẩu mã hóa vào két sắt Secure Storage
            await _storage.write(key: 'bio_user', value: user);
            await _storage.write(key: 'bio_pwd', value: pass);
            Navigator.pop(ctx);
            _showSnackBar("Đã kích hoạt Face ID cá nhân thành công!", Colors.green);
            await LoginHandler.executeSuccessfulLogin(context, user, name, role: role);
          },
          style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue),
          child: const Text("ĐỒNG Ý", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
// Hàm này giúp hiện thông báo với màu sắc tùy chọn (Xanh/Đỏ)
void _showSnackBar(String message, Color color) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message), 
        backgroundColor: color, 
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      )
    );
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

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message), 
          backgroundColor: const Color(0xFFE53935), 
          behavior: SnackBarBehavior.floating
        )
      );
    }
  }

  // --- GIAO DIỆN (GIỮ NGUYÊN BẢN GỐC CỦA BẠN) ---

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
                _buildHeader(size),
                _buildLoginForm(size),
                _buildFooterOptions(),
                _buildCopyright(),
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
      height: size.height * 0.30, 
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [vinhUniBlue, accentBlue]),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Image.asset('assets/images/logo.png', height: 65, errorBuilder: (_,__,___) => const Icon(Icons.school, size: 60)),
            ),
            const SizedBox(height: 10),
            const Text("VINH UNIVERSITY", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(Size size) {
    return Positioned(
      top: size.height * 0.25, 
      left: 25, right: 25,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Column(
          children: [
            _buildModernInput(controller: emailController, label: "Mã sinh viên", icon: Icons.person_outline),
            const SizedBox(height: 15),
            _buildModernInput(controller: passwordController, label: "Mật khẩu", icon: Icons.lock_outline, isPassword: true),
            const SizedBox(height: 15),
            _buildRememberMeRow(),
            const SizedBox(height: 20),
            _buildLoginButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          SizedBox(
            height: 24, width: 24,
            child: Checkbox(
              value: _rememberMe, 
              activeColor: vinhUniBlue, 
              onChanged: (v) => setState(() => _rememberMe = v!)
            ),
          ),
          const SizedBox(width: 8),
          const Text("Ghi nhớ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
            );
          },
          child: const Text(
            "Quên mật khẩu?", 
            style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity, height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("ĐĂNG NHẬP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFooterOptions() {
    return Positioned(
      bottom: 110, 
      left: 0, right: 0,
      child: Column(children: [
        Text("Hoặc đăng nhập bằng", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 25),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildFaceIDBtnPro(onTap: _handleFaceIDLoginPro), 
          const SizedBox(width: 20),
          _buildSocialBtn(icon: Icons.cloud_done_outlined, label: "Office 365", color: const Color(0xFFEA3E23), onTap: _handleMicrosoftLogin),
        ]),
      ]),
    );
  }

  Widget _buildCopyright() {
    return const Positioned(
      bottom: 30, left: 0, right: 0,
      child: Text("@ Viện NC&ĐTTT - Vinh University", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildModernInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Container(
      height: 48, 
      decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller, obscureText: isPassword ? _obscureText : false,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(fontSize: 13),
          prefixIcon: Icon(icon, color: vinhUniBlue.withOpacity(0.7), size: 20),
          suffixIcon: isPassword ? IconButton(icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _obscureText = !_obscureText)) : null,
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildFaceIDBtnPro({required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.purple.shade700, Colors.purple.shade400]),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: const Row(children: [
          Icon(Icons.face_unlock_outlined, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text("Face ID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _buildSocialBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08), 
          borderRadius: BorderRadius.circular(15), 
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 8), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))]),
      ),
    );
  }
}