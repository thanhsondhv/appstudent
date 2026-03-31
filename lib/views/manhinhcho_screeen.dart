import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// 🔥 IMPORT Service để khởi tạo tại đây
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

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Sử dụng Curves.easeOutBack để tạo hiệu ứng nảy nhẹ khi logo hiện ra
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.8, curve: Curves.easeIn)),
    );

    _logoController.forward();
    _handleRouting();
  }

  // ===========================================================================
  // 🔥 HÀM ĐIỀU HƯỚNG THÔNG MINH (ĐÃ CẬP NHẬT)
  // ===========================================================================
  Future<void> _handleRouting() async {
    String? initialRoute; // Biến lưu trữ trang cần nhảy vào từ thông báo

    try {
      // 1. Khởi tạo dịch vụ thông báo
      await NotificationService().initialize();
      debugPrint("🔔 [System] Notification Service đã sẵn sàng");

      // 2. Kiểm tra xem có thông báo nào đang "chờ" xử lý không (App mở từ Terminated)
      // Lưu ý: Bạn cần khai báo hàm static getInitialRoute trong NotificationService
      initialRoute = await NotificationService.getInitialRoute();
      
    } catch (e) {
      debugPrint("⚠️ [System] Lỗi khởi tạo hệ thống: $e");
    }

    // Duy trì màn hình chờ đủ lâu để logo chạy xong animation (2.5 giây)
    await Future.delayed(const Duration(milliseconds: 2500));

    final prefs = await SharedPreferences.getInstance();
    final String? savedId = prefs.getString('user_code') ?? prefs.getString('user_id');

    if (!mounted) return;

    // --- KIỂM TRA ĐĂNG NHẬP VÀ ĐIỀU HƯỚNG ---
    if (savedId != null && savedId.isNotEmpty) {
      // Đăng ký nhận thông báo chung của toàn trường
      try {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      } catch (_) {}

      // 🔥 LOGIC QUAN TRỌNG: 
      // Nếu có trang từ thông báo (initialRoute) thì nhảy vào đó, 
      // nếu không có thì mới vào trang chủ (/home) như bình thường.
      if (initialRoute != null) {
        debugPrint("🚀 [Routing] Chuyển hướng sâu vào: $initialRoute");
        Navigator.of(context).pushReplacementNamed(initialRoute);
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
      
    } else {
      // Nếu chưa đăng nhập, đưa về màn hình Login
      Navigator.of(context).pushReplacementNamed('/');
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
          // Nền Gradient 3 tầng chuyên nghiệp thương hiệu VinhUni
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0078D4), 
                  Color(0xFF0054A6), 
                  Color(0xFF003366),
                ],
              ),
            ),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      // LOGO TRƯỜNG ĐẠI HỌC VINH
                      Container(
                        width: 160,
                        height: 160,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 35,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.school_rounded, size: 80, color: Colors.white);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 35),
                      const Text(
                        "VINH UNIVERSITY",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          shadows: [
                            Shadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 10)
                          ]
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "STUDENT ECOSYSTEM",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
                // Thanh progress bar mỏng tinh tế
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 2,
                  ),
                ),
              ],
            ),
          ),

          // Thông tin bản quyền chân trang
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  "Version 1.3.0",
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  "© VIỆN NC&ĐTTT - VINH UNIVERSITY",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}