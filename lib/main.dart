import 'package:flutter/material.dart';
import 'dart:io'; // 👈 THÊM DÒNG NÀY: Để dùng HttpOverrides
import 'package:flutter/foundation.dart'; // 👈 THÊM DÒNG NÀY: Để kiểm tra kIsWeb

// Import Service xử lý thông báo
import 'services/notification_service.dart';

// Import các màn hình (Views)
import 'views/manhinhcho_screeen.dart';
import 'views/login_screen.dart';
import 'views/home_screen.dart';
import 'views/thoikhoabieu_screen.dart';
import 'views/thongbao_screen.dart';
import 'views/lichthi_screen.dart';
import 'views/diemthi_screen.dart';
import 'views/chat_screen.dart';

// 👈 THÊM CLASS NÀY: Giải quyết lỗi "HandshakeException" trên Android 
// Giúp App chấp nhận chứng chỉ HTTPS từ https://mobi.vinhuni.edu.vn
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 👈 THÊM DÒNG NÀY: Chỉ áp dụng bỏ qua SSL trên Mobile (Android/iOS)
  // Trên Web trình duyệt tự xử lý nên không cần/không dùng được lệnh này.
  if (!kIsWeb) {
    HttpOverrides.global = MyHttpOverrides();
  }

  // 1. Khởi tạo Notification Service (Bao gồm Firebase)
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("⚠️ Lỗi khởi tạo Notification: $e");
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
        primaryColor: const Color(0xFF0054A6), // Đổi về đúng màu VinhUni Blue
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0054A6),
          primary: const Color(0xFF0054A6),
        ),
        fontFamily: 'Inter',
      ),
      // Màn hình khởi động đầu tiên
      initialRoute: '/splash',
      
      // Bản đồ định tuyến (Routing)
      routes: {
        '/splash': (context) => const ManHinhChoScreen(),
        '/': (context) => const LogInWidget(),
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