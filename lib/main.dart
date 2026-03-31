import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'firebase_options.dart'; 

// ==========================================
// 1. IMPORT CÁC MÀN HÌNH CŨ
// ==========================================
import 'views/manhinhcho_screeen.dart'; 
import 'screens/login_screen.dart'; 
import 'views/home_screen.dart';
import 'views/thoikhoabieu_screen.dart';
import 'views/thongbao_screen.dart';
import 'views/lichthi_screen.dart';
import 'views/diemthi_screen.dart';
import 'views/chat_screen.dart';
import 'views/tkb_giangvien_screen.dart';
// ==========================================
// 2. IMPORT CÁC MÀN HÌNH MỚI (TỪ SQL)
// ==========================================
import 'views/khung_ct_screen.dart';
import 'views/bang_diem_tong_hop_screen.dart';
import 'views/tai_chinh_screen.dart';
import 'views/bhyt_screen.dart';
import 'views/feature_building_screen.dart';
//import 'views/gui_thong_bao_screen.dart';
import 'views/notification/notification_portal_screen.dart';

// 🔥 QUAN TRỌNG: Khai báo Navigator Key toàn cục
// Biến này cực kỳ quan trọng để NotificationService có thể nhảy thẳng vào 
// màn hình chi tiết tin nhắn kể cả khi App đang chạy ngầm hoặc bị tắt.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Class này giúp bỏ qua lỗi chứng chỉ SSL (Handshake Exception) khi gọi API cục bộ
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  // Đảm bảo các dịch vụ hệ thống được khởi tạo trước khi chạy App
  WidgetsFlutterBinding.ensureInitialized();
  
  // Bỏ qua lỗi SSL trên Android/iOS (Trừ Web) để gọi API ổn định
  if (!kIsWeb) HttpOverrides.global = MyHttpOverrides();

  try {
    // Khởi tạo Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("✅ [System] Firebase đã sẵn sàng");
  } catch (e) {
    debugPrint("❌ [System] Lỗi Firebase: $e");
  }

  // ⚠️ LƯU Ý: NotificationService.initialize() sẽ được gọi trong 'manhinhcho_screeen.dart'
  // để đảm bảo navigatorKey đã sẵn sàng nhận lệnh điều hướng.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vinh Uni Student',
      debugShowCheckedModeBanner: false,
      
      // 🔥 Gán navigatorKey để dịch vụ thông báo có thể điều khiển App
      navigatorKey: navigatorKey, 
      
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF0054A6), // Màu xanh thương hiệu VinhUni
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0054A6),
          primary: const Color(0xFF0054A6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF0054A6),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Color(0xFF0054A6)),
        ),
      ),
      
      // Màn hình khởi đầu là Splash Screen
      initialRoute: '/splash',
      
      routes: {
        // --- CÁC ROUTE HỆ THỐNG ---
        '/splash': (context) => const ManHinhChoScreen(),
        '/': (context) => const LogInWidget(), 
        '/home': (context) => const HomeScreen(),
        
        // --- CÁC ROUTE CHỨC NĂNG HỌC TẬP ---
        '/thoikhoabieu': (context) => const ThoiKhoaBieuScreen(), 
        '/thongbao': (context) => const ThongBaoScreen(),
        '/lichthi': (context) => const LichThiScreen(),
        '/diemthi': (context) => const DiemThiScreen(),
        '/chatscreen': (context) => const ChatScreen(),

        // --- CÁC ROUTE MỚI DỮ LIỆU SQL ---
        '/khungct': (context) => KhungCTScreen(),
        '/tongket': (context) => BangDiemTongHopScreen(),
        '/taichinh': (context) => TaiChinhScreen(),
        '/bhyt': (context) => BHYTScreen(),
        
        // Các tính năng đang phát triển
        '/diemrenluyen': (context) => FeatureBuildingScreen(title: "ĐIỂM RÈN LUYỆN"),
        '/hocbong': (context) => FeatureBuildingScreen(title: "KẾT QUẢ HỌC BỔNG"),
        '/canhbaoht': (context) => FeatureBuildingScreen(title: "CẢNH BÁO HỌC TẬP"),
        
        // Route dành cho Giảng viên/Cán bộ gửi tin
        '/guitin': (context) => const NotificationPortalScreen(),
        '/tkb_giangvien': (context) => const TkbGiangVienScreen(),
      },
    );
  }
}