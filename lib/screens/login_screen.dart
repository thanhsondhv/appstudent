//login_screen.dart
import 'package:flutter/material.dart';
import '../core/api/may_chu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:vinhuni_app/screens/forgot_password_screen.dart';
import 'face_scan_pro_screen.dart';
import '../handlers/login_handler.dart'; 
import '../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vinhuni_app/services/onedrive_service.dart';
class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key}); 

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocusNode = FocusNode(); 
  final passwordFocusNode = FocusNode();
  
  final _appLinks = AppLinks();
  final _authService = AuthService(); 

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscureText = true;
  String? _displayName; 
  String? _displayId; 
  int _avatarVersion = 0; 

  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color accentBlue = const Color(0xFF0078D4);

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _initDeepLinkListener();
    
    emailFocusNode.addListener(() {
      if (!emailFocusNode.hasFocus && emailController.text.isNotEmpty) {
        _fetchUserDisplayName();
      }
    });
  }

  void _fetchUserDisplayName() async {
    if (emailController.text.isEmpty) return;
    final info = await _authService.getUserPublicInfo(emailController.text.trim());
    if (mounted && info != null) {
      setState(() {
        _displayName = info['full_name'];
        _displayId = info['numeric_id']; 
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_display_name', info['full_name']!);
      await prefs.setString('last_display_id', info['numeric_id']!);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  // --- [SỬA LẠI HÀM LOGIN MẬT KHẨU] ---
  // --- [SỬA LẠI HÀM LOGIN MẬT KHẨU] ---
  // --- [SỬA LẠI HÀM LOGIN MẬT KHẨU - ĐỢI ĐỒNG BỘ TOKEN] ---
  void _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập đầy đủ thông tin!");
      return;
    }

    setState(() => _isLoading = true);
    final userData = await _authService.login(emailController.text.trim(), passwordController.text.trim());
    
    if (userData != null) {
      await _saveAccountInfo();
      String rawUserCode = userData['user_code']?.toString() ?? userData['student_id']?.toString() ?? "";
      String numericId = rawUserCode.replaceAll(RegExp(r'[^0-9]'), '');
      String loginUserName = emailController.text.trim();
      
      // 🔥 CHÌA KHÓA FIX LỖI: Thêm await để ép App chờ nạp xong mã OneDrive từ Server Python về máy
      // Đảm bảo khi vào đến màn hình bên trong, máy đã có sẵn Token và Hạn dùng
      await OneDriveService().syncTokenOnAppLaunch(numericId);

      if (mounted) setState(() => _isLoading = false);

      bool registered = await LoginHandler.isFaceRegistered(numericId, loginUserName);

      if (!registered) {
        if (mounted) {
          _showBiometricEnrollmentDialog(
            numericId, 
            loginUserName, 
            passwordController.text.trim(), 
            userData['full_name'], 
            userData['user_role'] ?? userData['role'],
            userData['access_token'],
          );
        }
      } else {
        if (mounted) {
          await LoginHandler.executeSuccessfulLogin(
            context, 
            numericId, 
            userData['full_name'], 
            role: userData['user_role'] ?? userData['role'],
            accessToken: userData['access_token'],
          );
        }
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
      // Nói đúng nguyên nhân thay vì mặc định đổ cho mật khẩu — xem
      // AuthService.thongDiepLoiCuoi.
      _showErrorSnackBar(AuthService.thongDiepLoiCuoi.isNotEmpty
          ? AuthService.thongDiepLoiCuoi
          : "Tài khoản hoặc mật khẩu không chính xác!");
      passwordController.clear();
      passwordFocusNode.requestFocus();
    }
  }

  // --- [SỬA LẠI HÀM ĐĂNG KÝ FACE ID] ---
  void _showBiometricEnrollmentDialog(String numericId, String userName, String pass, String name, String? role, String? accessToken) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Kích hoạt Face ID"),
        content: const Text("Bạn có muốn sử dụng khuôn mặt để đăng nhập nhanh cho những lần sau không?"),
        actions: [
          TextButton(
            onPressed: () { 
              Navigator.pop(ctx); 
              LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role, accessToken: accessToken); 
            }, 
            child: const Text("ĐỂ SAU")
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); 
              final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const FaceScanProScreen()));
              if (result != null && result['front'] != null) {
                final aiResult = await _authService.loginByFacePro(frontFile: result['front']);
                if (aiResult['status'] == 'SUCCESS') {
                  await _storage.write(key: 'bio_user', value: userName);
                  await _storage.write(key: 'bio_pwd', value: pass);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('face_registered_$numericId', true);
                  
                  // Lấy token từ kết quả quét mặt thành công
                  String? faceToken = aiResult['user_data'] != null ? aiResult['user_data']['access_token'] : accessToken;
                  
                  if (mounted) await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role, accessToken: faceToken);
                }
              }
            },
            child: const Text("ĐỒNG Ý"),
          ),
        ],
      ),
    );
  }

  // --- [SỬA LẠI HÀM LOGIN FACE ID] ---
  
  // --- [SỬA LẠI HÀM LOGIN FACE ID - ĐỢI ĐỒNG BỘ TOKEN] ---
  void _handleFaceIDLoginPro() async {
    String? savedUser = await _storage.read(key: 'bio_user');
    String? savedPwd = await _storage.read(key: 'bio_pwd');
    if (savedUser == null || savedPwd == null) {
      _showErrorSnackBar("Chưa đăng ký Face ID!");
      return;
    }
    bool auth = await _authService.authenticateWithDevice();
    if (auth) {
      setState(() => _isLoading = true);
      final userData = await _authService.login(savedUser, savedPwd);
      if (userData != null) {
        String numericId = userData['user_code'].toString().replaceAll(RegExp(r'[^0-9]'), '');
        String finalRole = userData['user_role'] ?? userData['role'] ?? "SinhVien";
        
        // 🔥 CHÌA KHÓA FIX LỖI: Ép luồng quét mặt đợi nạp xong Token OneDrive rồi mới thực hiện nhảy trang
        await OneDriveService().syncTokenOnAppLaunch(numericId);

        if (mounted) {
          setState(() => _isLoading = false);
          await LoginHandler.executeSuccessfulLogin(
            context, 
            numericId, 
            userData['full_name'], 
            role: finalRole,
            accessToken: userData['access_token'],
          );
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _initDeepLinkListener() {
    _appLinks.uriLinkStream.listen((uri) { if (mounted) _processLoginUri(uri); });
  }

  void _processLoginUri(Uri uri) async {
    if (uri.scheme == 'vinhuni-app' && uri.host == 'login_success') {
      final String? token = uri.queryParameters['session_token'];
      debugPrint("🔗 [DEBUG] App đã bắt được Deep Link!");
      if (token != null) {
        // Hàm verifySessionAndLogin trong Handler đã được cập nhật để tự lấy và lưu token
        await LoginHandler.verifySessionAndLogin(context, token);
      }
    }
  }

  Future<void> _handleMicrosoftLogin() async {
    String url = "${MayChu.diaChi}/login/microsoft?prompt=select_account";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      emailController.text = prefs.getString('saved_user') ?? "";
      passwordController.text = prefs.getString('saved_pwd') ?? "";
      _rememberMe = prefs.getBool('remember_me') ?? false;
      _displayName = prefs.getString('last_display_name');
      _displayId = prefs.getString('last_display_id');
      _avatarVersion = prefs.getInt('avatar_version') ?? 0; 
    });
    if (emailController.text.isNotEmpty) _fetchUserDisplayName();
  }

  Future<void> _saveAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_user', emailController.text);
      await prefs.setString('saved_pwd', passwordController.text);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_user'); await prefs.remove('saved_pwd');
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
  void _showErrorSnackBar(String message) => _showSnackBar(message, Colors.redAccent);

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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Size size) {
    String avatarUrl = "${MayChu.diaChi}/api/get-avatar/?student_id=$_displayId&v=$_avatarVersion";

    return Positioned(
      top: 0, left: 0, right: 0, height: size.height * 0.38,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [vinhUniBlue, accentBlue]), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 30),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]),
            child: ClipOval(
              child: (_displayId != null && _displayId != "") 
                ? CachedNetworkImage(
                    imageUrl: avatarUrl,
                    cacheKey: _displayId, 
                    fadeInDuration: Duration.zero, 
                    useOldImageOnUrlChange: true, 
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    errorWidget: (context, url, error) => Container(color: Colors.white, child: Icon(Icons.person, size: 60, color: vinhUniBlue)),
                  )
                : Container(color: Colors.white, child: Image.asset('assets/images/logo.png', scale: 2)),
            ),
          ),
          const SizedBox(height: 15),
          if (_displayName != null) ...[
            const Text("Xin chào,", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(_displayName!.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          ] else ...[
            const Text("VINH UNIVERSITY", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ]),
      ),
    );
  }

  Widget _buildLoginForm(Size size) {
    return Positioned(
      top: size.height * 0.30, left: 25, right: 25,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)]),
        child: Column(children: [
          _buildModernInput(controller: emailController, focusNode: emailFocusNode, hint: "Mã SV/Tên cán bộ", icon: Icons.person_outline),
          const SizedBox(height: 15),
          _buildModernInput(controller: passwordController, focusNode: passwordFocusNode, hint: "Mật khẩu", icon: Icons.lock_outline, isPassword: true),
          const SizedBox(height: 15),
          _buildRememberMeRow(),
          const SizedBox(height: 20),
          _buildLoginButton(),
        ]),
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        Checkbox(value: _rememberMe, activeColor: vinhUniBlue, onChanged: (v) => setState(() => _rememberMe = v!)),
        const Text("Ghi nhớ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
      InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordScreen())), child: const Text("Quên mật khẩu?", style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600))),
    ]);
  }

  Widget _buildLoginButton() {
    return SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _isLoading ? null : _handleLogin, style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("ĐĂNG NHẬP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))));
  }

  Widget _buildFooterOptions() {
    return Positioned(
      bottom: 80, left: 0, right: 0,
      child: Column(children: [
        Text("Hoặc đăng nhập bằng", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildFaceIDBtnPro(onTap: _handleFaceIDLoginPro), 
          const SizedBox(width: 20),
          _buildSocialBtn(icon: Icons.cloud_done_outlined, label: "Office 365", color: const Color(0xFFEA3E23), onTap: _handleMicrosoftLogin),
        ]),
        const SizedBox(height: 30),
        const Text("@ Viện NC&ĐTTT - Vinh University", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500))
      ]),
    );
  }

  Widget _buildModernInput({required TextEditingController controller, FocusNode? focusNode, required String hint, required IconData icon, bool isPassword = false}) {
    return Container(
      height: 52, decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller, focusNode: focusNode, obscureText: isPassword ? _obscureText : false,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: vinhUniBlue.withOpacity(0.7), size: 20),
          suffixIcon: isPassword ? IconButton(icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _obscureText = !_obscureText)) : null,
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFaceIDBtnPro({required VoidCallback onTap}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple.shade700, Colors.purple.shade400]), borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: const Row(children: [Icon(Icons.face_unlock_outlined, color: Colors.white, size: 22), SizedBox(width: 8), Text("Face ID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))])));
  Widget _buildSocialBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.2))), child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 8), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))])));
}