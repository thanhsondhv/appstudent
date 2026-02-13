import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManHinhChoScreen extends StatefulWidget {
  const ManHinhChoScreen({super.key});

  @override
  State<ManHinhChoScreen> createState() => _ManHinhChoScreenState();
}

class _ManHinhChoScreenState extends State<ManHinhChoScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _handleRouting();
  }

  Future<void> _handleRouting() async {
    // Chờ 3 giây để hiển thị thương hiệu
    await Future.delayed(const Duration(milliseconds: 3000));

    final prefs = await SharedPreferences.getInstance();
    final String? savedId = prefs.getString('user_id');

    if (savedId != null && savedId.isNotEmpty) {
      try {
        // Tự động đăng ký lại topic khi mở app nếu đã login
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
      } catch (e) {
        debugPrint("Firebase chưa sẵn sàng: $e");
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0066CC), Color(0xFF0054A6)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _animation,
                child: const Text(
                  "VINH UNIVERSITY",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}