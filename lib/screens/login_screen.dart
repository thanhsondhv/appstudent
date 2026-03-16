import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'dart:convert';
import 'package:vinhuni_app/screens/forgot_password_screen.dart';
import 'face_scan_pro_screen.dart';
import '../handlers/login_handler.dart'; 
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key}); 

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  // 1. Cấu hình Két sắt bảo mật
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  
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
    _initDeepLinkListener(); // Khởi tạo lắng nghe link từ Microsoft/Web
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

  // --- 1. XỬ LÝ ĐĂNG NHẬP THÔNG THƯỜNG ---
  void _handleLogin() async {
    // 1. Kiểm tra đầu vào
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập đầy đủ thông tin!");
      return;
    }

    setState(() => _isLoading = true);
    
    // 2. Gọi API Login (Username/Password)
    final userData = await _authService.login(
      emailController.text.trim(), 
      passwordController.text.trim()
    );
    
    if (mounted) setState(() => _isLoading = false);

    if (userData != null) {
      // Lưu thông tin đăng nhập (Ghi nhớ tài khoản)
      await _saveAccountInfo();

      // 3. Xử lý ID định danh
      // Lấy mã số từ Server (VD: CB1679 hoặc 1679)
      String rawUserCode = userData['user_code']?.toString() ?? userData['student_id']?.toString() ?? "";
      
      // 🔥 ÉP THÀNH SỐ: Chuyển CB1679 thành 1679 để load Avatar chuẩn
      String numericId = rawUserCode.replaceAll(RegExp(r'[^0-9]'), '');
      if (numericId.isEmpty) numericId = rawUserCode; 

      // Tên đăng nhập dùng để đối chiếu trong Két sắt (VD: ntson)
      String loginUserName = emailController.text.trim();

      // 4. KIỂM TRA FACE ID ĐÃ ĐĂNG KÝ CHƯA (Kiểm tra Két sắt)
      // Chúng ta truyền cả numericId và loginUserName để Handler check trong SecureStorage
      bool registered = await LoginHandler.isFaceRegistered(numericId, loginUserName);

      debugPrint("🔍 [Login] User: $loginUserName | ID: $numericId | Registered: $registered");

      if (!registered) {
        // TRƯỜNG HỢP A: Két sắt trống rỗng (Chưa đăng ký bao giờ hoặc đã xóa trắng Face ID)
        if (mounted) {
          _showBiometricEnrollmentDialog(
            numericId,             // Truyền 1679
            loginUserName,         // Truyền ntson
            passwordController.text.trim(), 
            userData['full_name'] ?? "Người dùng",
            userData['user_role'] ?? userData['role']
          );
        }
      } else {
        // TRƯỜNG HỢP B: Đã có dữ liệu trong Két sắt -> Vào thẳng Home, không hỏi lại
        if (mounted) {
          await LoginHandler.executeSuccessfulLogin(
            context, 
            numericId, 
            userData['full_name'], 
            role: userData['user_role'] ?? userData['role']
          );
        }
      }
    } else {
      // Sai tài khoản hoặc mật khẩu
      _showErrorSnackBar("Tài khoản hoặc mật khẩu không chính xác!");
    }
  }

  // --- 2. HÀM ĐĂNG KÝ FACE ID (AI CAMERA) ---
  // 🔥 CẬP NHẬT: Nhận đủ 5 tham số để không còn lỗi "Too many positional arguments"
  void _showBiometricEnrollmentDialog(String numericId, String userName, String pass, String name, String? role) {
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.face_unlock_outlined, color: vinhUniBlue, size: 28),
            const SizedBox(width: 10),
            const Text("Kích hoạt Face ID", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "Bạn có muốn sử dụng khuôn mặt để đăng nhập nhanh cho những lần sau không? Dữ liệu sẽ được lưu an toàn trong két sắt bảo mật.",
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          // --- NÚT ĐỂ SAU ---
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Chỉ vào Home, không lưu gì vào két sắt
              await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role);
            }, 
            child: Text("ĐỂ SAU", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
          
          // --- NÚT ĐỒNG Ý ---
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: vinhUniBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx); // Đóng Dialog
              
              // A. Mở Camera quét AI
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FaceScanProScreen()), 
              );

              if (result != null && result['front'] != null) {
                if (mounted) setState(() => _isLoading = true);
                
                try {
                  // B. Gửi ảnh lên AI xác thực
                  final aiResult = await _authService.loginByFacePro(frontFile: result['front']);

                  if (aiResult['status'] == 'SUCCESS') {
                    // ✅ CẤT DỮ LIỆU VÀO KÉT SẮT
                    // 1. Lưu username (ntson) và password vào két sắt bảo mật
                    await _storage.write(key: 'bio_user', value: userName);
                    await _storage.write(key: 'bio_pwd', value: pass);
                    
                    // 2. Lưu "Cờ" vào SharedPreferences để máy biết đã đăng ký FaceID
                    // Dùng numericId (1679) để làm khóa định danh
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('face_registered_$numericId', true);

                    debugPrint("🔐 [Auth] Đã đăng ký Face ID cho $userName (ID: $numericId)");
                    _showSnackBar("✅ Đã kích hoạt Face ID thành công!", Colors.green);

                    // 3. Tiến vào Home
                    if (mounted) {
                      await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role);
                    }
                  } else {
                    _showErrorSnackBar("Không khớp khuôn mặt: ${aiResult['message']}");
                    if (mounted) await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role);
                  }
                } catch (e) {
                  _showErrorSnackBar("Lỗi hệ thống AI!");
                  if (mounted) await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              } else {
                // Thoát ngang camera
                await LoginHandler.executeSuccessfulLogin(context, numericId, name, role: role);
              }
            },
            child: const Text("ĐỒNG Ý", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- 3. ĐĂNG NHẬP NHANH BẰNG FACE ID (NÚT TÍM) ---
  void _handleFaceIDLoginPro() async {
  String? savedUser = await _storage.read(key: 'bio_user'); // Sẽ là "ntson"
  String? savedPwd = await _storage.read(key: 'bio_pwd');

  if (savedUser == null || savedPwd == null) {
    _showErrorSnackBar("Chưa đăng ký Face ID!");
    return;
  }

  bool auth = await _authService.authenticateWithDevice();
  if (auth) {
    setState(() => _isLoading = true);
    // Gửi ntson và pass lên Server
    final userData = await _authService.login(savedUser, savedPwd);
    
    if (userData != null) {
      String numericId = userData['user_code'].toString().replaceAll(RegExp(r'[^0-9]'), '');
      await LoginHandler.executeSuccessfulLogin(context, numericId, userData['full_name'], role: userData['role']);
    } else {
      _showErrorSnackBar("Face ID hết hạn hoặc mật khẩu đã đổi!");
    }
    setState(() => _isLoading = false);
  }
}

  // --- 4. XỬ LÝ DEEP LINK (MICROSOFT LOGIN) ---
  void _initDeepLinkListener() {
    _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _processLoginUri(uri);
    });
  }

  void _processLoginUri(Uri uri) async {
    if (!mounted) return;

    // 1. Kiểm tra xem link có đúng định dạng đăng nhập thành công không
    // Chấp nhận cả: vinhuni-app://login_success hoặc link có chứa 'login-success'
    bool isSuccess = (uri.scheme == 'vinhuni-app' && uri.host == 'login_success') || 
                     (uri.path.contains('login-success'));

    if (isSuccess) {
      // 2. Trích xuất thông tin từ các tham số (Parameters) trên URL
      final String? rawUserId = uri.queryParameters['user_id']; // VD: CB1679 hoặc ntson
      final String name = uri.queryParameters['name'] ?? "Thành viên VinhUni";
      final String? role = uri.queryParameters['role'];

      if (rawUserId != null && rawUserId.isNotEmpty) {
        // 🔥 3. ÉP LẤY MÃ SỐ: Chuyển CB1679 -> 1679 để load Avatar và Thông báo chuẩn
        String numericId = rawUserId.replaceAll(RegExp(r'[^0-9]'), '');
        
        // Nếu kết quả lọc số bị rỗng (trường hợp userId toàn chữ), thì dùng lại mã gốc
        final String finalId = numericId.isEmpty ? rawUserId : numericId;

        debugPrint("🔗 [DeepLink] Xử lý thành công: $rawUserId -> ID chuẩn: $finalId");

        // 4. Hiển thị thông báo trạng thái cho người dùng
        _showSnackBar("Đang đồng bộ tài khoản liên kết...", vinhUniBlue);

        // 🔥 5. TIẾN VÀO HOME
        // Lưu ý: Đăng nhập qua Link (Microsoft) thường không có mật khẩu (Password),
        // nên chúng ta sẽ cho người dùng vào thẳng Home mà không hiện Dialog đăng ký Face ID.
        // (Face ID sẽ được yêu cầu đăng ký ở lần Đăng nhập bằng Mật khẩu tiếp theo).
        await LoginHandler.executeSuccessfulLogin(
          context, 
          finalId, 
          name, 
          role: role
        );
      } else {
        _showErrorSnackBar("Dữ liệu định danh từ hệ thống liên kết không hợp lệ!");
      }
    }
  }

  // --- 5. TIỆN ÍCH HỆ THỐNG ---
  Future<void> _handleMicrosoftLogin() async {
    String baseUrl = "https://mobi.vinhuni.edu.vn/login/microsoft?prompt=select_account";
    if (emailController.text.isNotEmpty) {
      baseUrl += "&login_hint=${emailController.text.trim()}@vinhuni.edu.vn";
    }
    final Uri url = Uri.parse(baseUrl);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
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

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
    }
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, const Color(0xFFE53935));
  }

  // --- 6. GIAO DIỆN (BUILD) ---
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
      top: 0, left: 0, right: 0, height: size.height * 0.30,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [vinhUniBlue, accentBlue]), 
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50))
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(12), 
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), 
            child: Image.asset('assets/images/logo.png', height: 65, errorBuilder: (_,__,___) => const Icon(Icons.school, size: 60, color: Color(0xFF0054A6)))
          ),
          const SizedBox(height: 10),
          const Text("VINH UNIVERSITY", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ]),
      ),
    );
  }

  Widget _buildLoginForm(Size size) {
    return Positioned(
      top: size.height * 0.25, left: 25, right: 25,
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))]),
        child: Column(children: [
          _buildModernInput(controller: emailController, label: "Mã SV/Tên cán bộ", icon: Icons.person_outline),
          const SizedBox(height: 15),
          _buildModernInput(controller: passwordController, label: "Mật khẩu", icon: Icons.lock_outline, isPassword: true),
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
        SizedBox(height: 24, width: 24, child: Checkbox(value: _rememberMe, activeColor: vinhUniBlue, onChanged: (v) => setState(() => _rememberMe = v!))),
        const SizedBox(width: 8),
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
      bottom: 100, left: 0, right: 0,
      child: Column(children: [
        Text("Hoặc đăng nhập bằng", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildFaceIDBtnPro(onTap: _handleFaceIDLoginPro), 
          const SizedBox(width: 20),
          _buildSocialBtn(icon: Icons.cloud_done_outlined, label: "Office 365", color: const Color(0xFFEA3E23), onTap: _handleMicrosoftLogin),
        ]),
      ]),
    );
  }

  Widget _buildCopyright() => const Positioned(bottom: 30, left: 0, right: 0, child: Text("@ Viện NC&ĐTTT - Vinh University", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)));

  Widget _buildModernInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Container(
      height: 48, decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(12)),
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

  Widget _buildFaceIDBtnPro({required VoidCallback onTap}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple.shade700, Colors.purple.shade400]), borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: const Row(children: [Icon(Icons.face_unlock_outlined, color: Colors.white, size: 22), SizedBox(width: 8), Text("Face ID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))])));

  Widget _buildSocialBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.2))), child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 8), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))])));
}