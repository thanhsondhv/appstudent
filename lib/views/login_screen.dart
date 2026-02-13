import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/login.dart';
import '../services/notification_service.dart';


class LogInWidget extends StatefulWidget {
  const LogInWidget({super.key});

  @override
  State<LogInWidget> createState() => _LogInWidgetState();
}

class _LogInWidgetState extends State<LogInWidget> with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscureText = true;

  // Màu thương hiệu VinhUni (Xanh đậm)
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color accentBlue = const Color(0xFF0078D4);

  // Animation controller cho hiệu ứng xuất hiện
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    
    // Khởi tạo hiệu ứng fade-in nhẹ nhàng
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
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

  // --- LOGIC GIỮ NGUYÊN ---
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

  void _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorSnackBar("Vui lòng nhập đầy đủ tài khoản và mật khẩu!");
      return;
    }

    setState(() => _isLoading = true);

    bool isSuccess = await AuthService().login(
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    if (mounted) setState(() => _isLoading = false);

    if (isSuccess) {
      final userId = emailController.text.trim();
      await _saveAccountInfo();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      
      await _handleNotificationTopic(true);
      await NotificationService().syncTokenToServer(userId);

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
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

  // --- GIAO DIỆN MỚI HIỆN ĐẠI (PRO UI) ---
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
                Positioned(
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
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))],
                            ),
                            child: Image.asset('assets/images/logo.png', height: 80, errorBuilder: (_,__,___) => Icon(Icons.school, size: 80, color: vinhUniBlue)),
                          ),
                          const SizedBox(height: 15),
                          const Text("CỔNG SINH VIÊN", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 5),
                          Text("Đại học Vinh - Vinh University", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                          const SizedBox(height: 40), // Đẩy nội dung lên trên
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. LOGIN FORM CARD (Nổi lên trên Header)
                Positioned(
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
                          
                          // Input User
                          _buildModernInput(controller: emailController, label: "Mã sinh viên / Email", icon: Icons.person_rounded),
                          const SizedBox(height: 20),
                          
                          // Input Password
                          _buildModernInput(
                            controller: passwordController, 
                            label: "Mật khẩu", 
                            icon: Icons.lock_rounded, 
                            isPassword: true
                          ),
                          
                          const SizedBox(height: 15),
                          
                          // Remember Me & Forgot Pass
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    height: 24, width: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: vinhUniBlue,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      onChanged: (v) => setState(() => _rememberMe = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text("Ghi nhớ", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                              ),
                              TextButton(onPressed: (){}, child: Text("Quên mật khẩu?", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.w600, fontSize: 13))),
                            ],
                          ),
                          
                          const SizedBox(height: 25),
                          
                          // BUTTON LOGIN
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: vinhUniBlue,
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: vinhUniBlue.withOpacity(0.4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isLoading 
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                : const Text("ĐĂNG NHẬP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. FOOTER OPTIONS (FaceID / Email)
                Positioned(
                  bottom: 30, left: 0, right: 0,
                  child: Column(
                    children: [
                      Text("Hoặc đăng nhập bằng", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSocialBtn(icon: Icons.face_rounded, label: "Face ID", color: Colors.purple, onTap: (){
                            _showErrorSnackBar("Tính năng FaceID đang phát triển");
                          }),
                          const SizedBox(width: 20),
                          _buildSocialBtn(icon: Icons.email_rounded, label: "Google", color: Colors.red, onTap: (){
                            _showErrorSnackBar("Tính năng Google Login đang phát triển");
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget Input hiện đại
  Widget _buildModernInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscureText : false,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(icon, color: vinhUniBlue.withOpacity(0.6), size: 22),
          suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(_obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey[400], size: 20),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          floatingLabelStyle: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // Widget Button phụ (FaceID, Email)
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