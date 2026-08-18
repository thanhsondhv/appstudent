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
import 'views/chatgroup/chat_group_list_page.dart'; // Đảm bảo đường dẫn này đúng với máy của bạn
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
import 'services/vinhuni_api_client.dart';
import 'core/auth/session.dart';
import 'views/ky_so/ky_so_screen.dart';
// 🔥 QUAN TRỌNG: Khai báo Navigator Key toàn cục
// Biến này cực kỳ quan trọng để NotificationService có thể nhảy thẳng vào 
// màn hình chi tiết tin nhắn kể cả khi App đang chạy ngầm hoặc bị tắt.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Bỏ qua lỗi chứng chỉ SSL khi gọi API trên máy cục bộ.
///
/// ⚠️ CHỈ ĐƯỢC DÙNG KHI LẬP TRÌNH. Nếu bật ở bản phát hành, ứng dụng sẽ chấp nhận
/// mọi chứng chỉ giả mạo — kẻ tấn công đứng giữa có thể đọc và sửa toàn bộ dữ liệu
/// sinh viên, kể cả mật khẩu và token. Đã giới hạn lại ngày 18/08/2026 (Pha 0).
///
/// Nếu máy chủ nội bộ dùng chứng chỉ tự ký, hãy nhúng chứng chỉ đó vào ứng dụng
/// bằng `SecurityContext.setTrustedCertificates()` thay vì tắt kiểm tra.
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (kDebugMode) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        debugPrint("⚠️ [Debug] Bỏ qua lỗi chứng chỉ của $host:$port — chỉ có tác dụng khi gỡ lỗi");
        return true;
      };
    }
    return client;
  }
}

Future<void> main() async {
  // 1. Đảm bảo các dịch vụ hệ thống được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Khởi tạo kho phiên đăng nhập (và chuyển token cũ sang kho mã hoá)
  await Session.init();

  // 3. KÍCH HOẠT VINHUNI API CLIENT (INTERCEPTOR)
  // Việc này giúp mọi API sau đó tự động có Token
  VinhUniClient.setup();

  // 3. Bỏ qua lỗi SSL — CHỈ khi đang gỡ lỗi, không bao giờ ở bản phát hành
  if (!kIsWeb && kDebugMode) HttpOverrides.global = MyHttpOverrides();

  try {
    // 4. Khởi tạo Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("✅ [System] Firebase và API Client đã sẵn sàng");
  } catch (e) {
    debugPrint("❌ [System] Lỗi khởi tạo: $e");
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
        '/login': (context) => const LogInWidget(),
        // --- CÁC ROUTE CHỨC NĂNG HỌC TẬP ---
        '/thoikhoabieu': (context) => const ThoiKhoaBieuScreen(), 
        '/thongbao': (context) => const ThongBaoScreen(),
        '/lichthi': (context) => const LichThiScreen(),
        '/diemthi': (context) => const DiemThiScreen(),
        '/chatscreen': (context) => const ChatScreen(),
        '/chat_group_list': (context) {
           // Lấy mã người dùng tạm thời (Sẽ được truyền đầy đủ nếu chạy từ Push)
           return const ChatGroupListPage(userCode: ""); 
        },
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

        // Ký số văn bản và hồ sơ dịch vụ công (Pha 4)
        '/kyso': (context) => const KySoScreen(),
        
      },
    );
  }
}