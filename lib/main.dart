import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'firebase_options.dart'; 
import 'services/notification_service.dart';

// Import các màn hình
import 'views/manhinhcho_screeen.dart';
import 'screens/login_screen.dart';
import 'views/home_screen.dart';
import 'views/thoikhoabieu_screen.dart';
import 'views/thongbao_screen.dart';
import 'views/lichthi_screen.dart';
import 'views/diemthi_screen.dart';
import 'views/chat_screen.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) HttpOverrides.global = MyHttpOverrides();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("✅ [System] Firebase đã sẵn sàng");
  } catch (e) {
    debugPrint("❌ [System] Lỗi Firebase: $e");
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("⚠️ Lỗi Notification Service: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vinh Uni Student',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF0054A6),
        fontFamily: 'Inter',
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const ManHinhChoScreen(),
        // 🚀 SỬA LỖI: Xóa chữ 'const' ở đây
        '/': (context) => LogInWidget(), 
        '/home': (context) => const HomeScreen(),
        '/thoikhoabieu': (context) => const ThoiKhoaBieuScreen(),
        '/thongbao': (context) => const ThongBaoScreen(),
        '/lichthi': (context) => const LichThiScreen(),
        '/diemthi': (context) => const DiemThiScreen(),
        '/chatscreen': (context) => const ChatScreen(),
      },
    );
  }
}