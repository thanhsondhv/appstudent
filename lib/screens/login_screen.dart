import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'face_scan_pro_screen.dart';
import '../services/login.dart';
import '../handlers/login_handler.dart'; 
import '../services/face_auth_service.dart';

class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key}); 

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _appLinks = AppLinks();
  final _faceService = FaceAuthService();

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscureText = true;

  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color accentBlue = const Color(0xFF0078D4);

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount(); // Tải dữ liệu đã lưu từ máy
    _initDeepLinkListener();

    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- GIỮ NGUYÊN CÁC BIẾN VÀ LOGIC CŨ ---
  void _initDeepLinkListener() {
    _appLinks.uriLinkStream.listen((uri) => _processLoginUri(uri));
    _appLinks.getInitialLink().then((uri) { if (uri != null) _processLoginUri(uri); });
  }

  void _processLoginUri(Uri uri) async {
    if (uri.scheme == 'vinhuni-app' && uri.host == 'login_success') {
      final userId = uri.queryParameters['user_id'];
      final name = uri.queryParameters['name'];
      if (userId != null) {
        await LoginHandler.executeSuccessfulLogin(context, userId, name ?? "Sinh viên");
      }
    }
  }

  Future<void> _handleMicrosoftLogin() async {
    setState(() => _isLoading = true);
    try {
      final loginUrl = Uri.parse("https://mobi.vinhuni.edu.vn/login/microsoft");
      if (await canLaunchUrl(loginUrl)) {
        await launchUrl(loginUrl, mode: LaunchMode.externalApplication);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập đầy đủ thông tin!");
      return;
    }
    setState(() => _isLoading = true);
    final userData = await AuthService().login(emailController.text.trim(), passwordController.text.trim());
    if (mounted) setState(() => _isLoading = false);

    if (userData != null) {
      await _saveAccountInfo(); // Lưu vào máy ngay khi thành công
      await LoginHandler.executeSuccessfulLogin(context, userData['student_id'].toString(), userData['full_name']);
    } else {
      _showErrorSnackBar("Tài khoản hoặc mật khẩu không chính xác!");
    }
  }

  void _handleFaceIDLogin() async {
    final studentId = emailController.text.trim();
    if (studentId.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập Mã sinh viên trước khi quét Face ID!");
      return;
    }

    final isDeviceOwner = await _faceService.authenticateWithDevice();
    if (!isDeviceOwner) {
      _showErrorSnackBar("Xác thực thiết bị thất bại.");
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FaceScanProScreen()), 
    );

    if (result != null && result['front'] != null && result['pose'] != null) {
      setState(() => _isLoading = true);
      
      final aiResult = await _faceService.verify3D(
        studentId: studentId,
        frontFile: result['front'],
        poseFile: result['pose'],
      );

      if (aiResult['status'] == 'SUCCESS') {
        await LoginHandler.executeSuccessfulLogin(
          context, 
          aiResult['student_id'].toString(), 
          aiResult['full_name'] ?? "Sinh viên"
        );
      } else {
        _showErrorSnackBar(aiResult['message'] ?? "Khuôn mặt không khớp!");
      }
      
      if (mounted) setState(() => _isLoading = false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: const Color(0xFFE53935), behavior: SnackBarBehavior.floating));
    }
  }

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
                _buildCopyright(), // Copyright ở đáy màn hình
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI WIDGETS ĐÃ SỬA GIAO DIỆN ---

  // Cải tiến 1: Logo và Tiêu đề thu gọn về 1/4 màn hình (Height ~ 0.30)
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
            const Text("CỔNG SINH VIÊN", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }

  // Cải tiến 2: Thu gọn hộp nhập liệu (Form) và tăng khoảng cách "Ghi nhớ"
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
            const SizedBox(height: 15), // Tạo khoảng cách thông thoáng cho "Ghi nhớ"
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
            child: Checkbox(value: _rememberMe, activeColor: vinhUniBlue, onChanged: (v) => setState(() => _rememberMe = v!)),
          ),
          const SizedBox(width: 8),
          const Text("Ghi nhớ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        const Text("Quên mật khẩu?", style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)),
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

  // Cải tiến 3: Đẩy Footer lên cao (bottom: 110) và thêm nút Face ID Pro
  Widget _buildFooterOptions() {
    return Positioned(
      bottom: 110, 
      left: 0, right: 0,
      child: Column(children: [
        Text("Hoặc đăng nhập bằng", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 25),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildFaceIDBtnPro(onTap: _handleFaceIDLogin), // Nút Pro mới
          const SizedBox(width: 20),
          _buildSocialBtn(icon: Icons.cloud_done_outlined, label: "Office 365", color: const Color(0xFFEA3E23), onTap: _handleMicrosoftLogin),
        ]),
      ]),
    );
  }

  // Thêm Copyright ở dưới cùng
  Widget _buildCopyright() {
    return const Positioned(
      bottom: 30, left: 0, right: 0,
      child: Text("@ CNTT - Vinh University", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  // Ô nhập liệu nhỏ gọn (Height: 48)
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

  // Nút Face ID thiết kế cao cấp (Gradient & Shadow)
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