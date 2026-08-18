import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../services/notification_service.dart';

class ManHinhChoScreen extends StatefulWidget {
  const ManHinhChoScreen({super.key});

  @override
  State<ManHinhChoScreen> createState() => _ManHinhChoScreenState();
}

class _ManHinhChoScreenState extends State<ManHinhChoScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.8, curve: Curves.easeIn)));
    _logoController.forward();
    _handleRouting();
  }

  Future<void> _handleRouting() async {
    final DateTime startTime = DateTime.now();

    // 1. Chạy song song: Init thông báo & Đọc bộ nhớ máy
    final initializationResults = await Future.wait([
      SharedPreferences.getInstance(),
      NotificationService().initialize().timeout(const Duration(seconds: 2)).catchError((e) => null),
    ]);

    final SharedPreferences prefs = initializationResults[0] as SharedPreferences;
    
    // 2. Lấy thông tin đăng nhập
    final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final String? savedId = prefs.getString('user_code');
    final String role = prefs.getString('user_role') ?? "SinhVien";
    
    // 3. TẢI TRƯỚC MENU TỪ CACHE (Mấu chốt tốc độ)
    if (isLoggedIn) {
      String roleLower = role.toLowerCase().trim();
      String roleForApi = (roleLower == 'admin' || roleLower == 'ad' || roleLower == 'covan' || roleLower == 'canbo' || roleLower == 'cb') ? "CB" : "SV";
      final cacheKey = 'cache_app_menu_$roleForApi';
      final cachedStr = prefs.getString(cacheKey);
      
      if (cachedStr != null) {
        debugPrint("🚚 Pre-loaded Menu Cache: $roleForApi");
      }
    }

    String? initialRoute;
    try { 
      initialRoute = await NotificationService.getInitialRoute(); 
    } catch (_) {}

    // 4. Đảm bảo hiện logo đủ lâu để không bị giật
    final int elapsed = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsed < 1200) await Future.delayed(Duration(milliseconds: 1200 - elapsed));

    if (!mounted) return;

    // 5. ĐIỀU HƯỚNG BẢO MẬT (ĐÃ FIX LỖI LOOP)
    if (isLoggedIn && savedId != null && savedId.isNotEmpty) {
      // Đăng ký nhận thông báo chung
      FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students").catchError((e) {});
      
      // Vào Home hoặc màn hình chi tiết tin nhắn
      Navigator.of(context).pushReplacementNamed(initialRoute ?? '/home');
    } else {
      // 🔥 SỬA TẠI ĐÂY: Phải chuyển sang '/login' thay vì '/'
      // Nếu Sơn để '/' nó sẽ quay lại chính trang Splash này tạo thành vòng lặp.
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() { 
    _logoController.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity, height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF0078D4), Color(0xFF0054A6), Color(0xFF003366)]
              )
            )
          ),
          Center(
            child: AnimatedBuilder(
              animation: _logoController,
              builder: (context, child) => Opacity(opacity: _logoOpacity.value, child: Transform.scale(scale: _logoScale.value, child: child)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140, height: 140, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.12)),
                    child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain))
                  ),
                  const SizedBox(height: 25),
                  const Text("VINH UNIVERSITY", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text("STUDENT ECOSYSTEM", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 60),
                  SizedBox(width: 100, child: LinearProgressIndicator(backgroundColor: Colors.white.withOpacity(0.1), valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 1.5)),
                ],
              ),
            ),
          ),
          // Cập nhật text Version lên 1.3.1 cho đồng bộ với App Store Connect
          Positioned(bottom: 30, left: 0, right: 0, child: Text("Version 1.3.1 | Powered by Viện NC&ĐTTT", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10))),
        ],
      ),
    );
  }
}