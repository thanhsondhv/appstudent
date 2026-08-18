//homehome_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'dart:async';
import 'search_screen.dart';
import 'chungchi_tracuu.dart';
import 'chat_screen.dart';
import 'thongbao_screen.dart';
import 'profile_screen.dart';
import 'certificate_page.dart';
import 'schedule__canbo_screen.dart';
import 'vanban_screen.dart';
import 'quan_ly_xin_phep_screen.dart';
import 'duyet_vang_hoc_screen.dart';
import 'mo_diem_danh_screen.dart';
import 'diem_danh_sv_screen.dart';
import 'qr_scanner_screen.dart';
import 'congcambo_screen.dart';
import '../services/database_helper.dart'; 
import 'package:vinhuni_app/views/chatgroup/chat_group_list_page.dart';
import 'package:vinhuni_app/views/notification/student_send_to_staff_screen.dart';
import 'package:vinhuni_app/views/secretary/meeting_recorder_screen.dart';
import 'package:vinhuni_app/services/voice_control_service.dart';
import 'package:flutter/services.dart';
import 'package:vinhuni_app/views/onedrive_manager_screen.dart';
import 'package:vinhuni_app/views/secretary/document_scanner_screen.dart';
import 'package:vinhuni_app/views/secretary/student_secretary_screen.dart';
import '../core/auth/user_role.dart';
import '../core/auth/session.dart';
import '../core/api/api.dart';
import '../core/repositories/notification_repository.dart';


final GlobalKey<ChatScreenState> chatScreenKey = GlobalKey<ChatScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _voiceService = VoiceControlService(); 
  String? fbToken; 
  String? sysToken;
  bool _isVoiceLoading = false;
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color activeColor = const Color(0xFF0078D4);
  bool _isLoading = false;
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _voiceInstruction = "Tìm kiếm dịch vụ..."; // Mặc định
  String studentName = "Đang tải...";
  String studentId = ""; 
  String userRole = "SinhVien"; 
  String userFaculty = ""; 
  String userDept = "";    

  List<dynamic> studentProfilesList = [];
  int _avatarVersion = 0; 
  int _unreadCount = 0; 
  List<dynamic> appMenu = [];
  
  @override
  void initState() {
    super.initState();

    // Nối dây làm mới huy hiệu.
    //
    // Sửa 18/08/2026: `NotificationService.onRefreshBadge` được khai báo và
    // được gọi ở ba nơi (khi có tin đẩy tới, khi đọc một tin, khi đánh dấu tất
    // cả đã đọc) nhưng chưa bao giờ được GÁN. Mọi lời gọi đều rơi vào nhánh
    // null, nên con số trên huy hiệu đứng yên cho tới lần mở lại ứng dụng.
    NotificationService.onRefreshBadge = () {
      if (mounted) _fetchUnreadCount();
    };

    _initAppData();
    WidgetsBinding.instance.addPostFrameCallback((_) { _checkVersion(); });
  }

  @override
  void dispose() {
    // Gỡ dây khi màn hình bị huỷ (đăng xuất rồi đăng nhập lại), tránh gọi
    // setState trên State đã chết.
    NotificationService.onRefreshBadge = null;
    super.dispose();
  }

  Future<void> _initAppData() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance; // Khởi tạo CSDL SQLite
    
    // 1. Lấy và làm sạch dữ liệu người dùng từ bộ nhớ đệm
    String rawId = prefs.getString('user_code') ?? "";
    String cleanId = rawId.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    String role = prefs.getString('user_role') ?? "SinhVien";
    
    // 🔥 Lấy cặp Token để phục vụ Chat WebView.
    // Đọc qua Session vì token nay nằm trong kho mã hoá (Pha 1).
    String? fbt = await Session.firebaseChatToken;
    String? st = await Session.accessToken;
    
    if (mounted) {
      setState(() {
        studentId = cleanId;
        studentName = prefs.getString('full_name') ?? prefs.getString('user_name') ?? "Người dùng";
        userRole = role;
        userFaculty = prefs.getString('user_faculty') ?? ""; 
        _avatarVersion = prefs.getInt('avatar_version') ?? 0;
        
        // 🔥 Gán Token vào biến trạng thái để HomeScreen truyền sang WebView
        fbToken = fbt; 
        sysToken = st;
      });
    }

    // 2. 🔥 CHIẾN THUẬT OFFLINE: Ưu tiên load Menu từ SQLite
    // Điều này giúp menu hiện lên ngay cả khi không có 5G.
    try {
      final cachedMenu = await db.getAppMenu(); // Lấy từ bảng app_menu trong SQLite
      if (cachedMenu.isNotEmpty && mounted) {
        setState(() => appMenu = cachedMenu);
        debugPrint("🚀 [Offline] Đã nạp Menu từ CSDL SQLite.");
      } else {
        // Nếu SQLite trống, dùng tạm SharedPreferences cũ làm dự phòng
        final backupStr = prefs.getString('cache_app_menu_secure');
        if (backupStr != null && mounted) {
          setState(() => appMenu = json.decode(backupStr));
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi load cache menu: $e");
    }

    // 3. Cập nhật dữ liệu mới nhất từ Server
    _fetchDynamicMenu(prefs); // Hàm này sẽ tự lưu đè vào SQLite khi có mạng thành công.
    
    if (studentId.isNotEmpty) {
      _fetchStudentExtraInfo(studentId); // Tải GPA và thông tin học tập
      _fetchUnreadCount(); // Cập nhật số thông báo chưa đọc
      NotificationService.syncTokenToServer(studentId); // Đồng bộ Firebase Token
    }
  }

  Future<void> _fetchDynamicMenu(SharedPreferences prefs) async {
    final String? token = await Session.accessToken;
    if (token == null || token.isEmpty) return;

    try {
      // Api tự gắn Authorization, không cần dựng header bằng tay nữa
      final response = await Api.get(
        '/api/app-menu',
        hanCho: const Duration(seconds: 10),
      );

      if (response.thanhCong) {
        final List<dynamic> newData =
            response.data is List ? response.data as List : const [];
        if (mounted) {
          setState(() {
            appMenu = newData;
            _isLoading = false;
          });
          // 🔥 BỔ SUNG: Lưu ngay vào SQLite để lần sau load offline
          await DatabaseHelper.instance.saveAppMenu(newData); 
          debugPrint("✅ [Menu] Đã cập nhật và lưu Cache SQLite.");
        }
      }
    } catch (e) {
      debugPrint("🔥 Lỗi lấy menu: $e");
    }
  }
  bool _isNewerVersion(String current, String latest) {
    try {
      List<String> curParts = current.split('+');
      List<String> latParts = latest.split('+');
      if (curParts[0] != latParts[0]) return true;
      int curBuild = int.parse(curParts.length > 1 ? curParts[1] : "0");
      int latBuild = int.parse(latParts.length > 1 ? latParts[1] : "0");
      return latBuild > curBuild;
    } catch (e) { return false; }
  }

  Future<void> _checkVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVer = "${packageInfo.version}+${packageInfo.buildNumber}";
      final response = await Api.get('/api/check-version');
      if (response.thanhCong && response.data is Map) {
        final data = response.data as Map;
        Map<String, dynamic> platformData = Platform.isAndroid ? data['android'] : data['ios'];
        String latestVer = platformData['latest_version'];
        if (_isNewerVersion(currentVer, latestVer)) {
          _showUpdateDialog(currentVer, latestVer, platformData['url'], platformData['is_force']);
        }
      }
    } catch (e) {}
  }

  void _showUpdateDialog(String current, String latest, String url, bool force) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, isDismissible: !force, enableDrag: !force, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(25, 20, 25, 30),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            Icon(Icons.rocket_launch_rounded, size: 50, color: vinhUniBlue),
            const SizedBox(height: 20),
            const Text("Đã có phiên bản mới!!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("VinhUni App đã có bản mới. Vui lòng cập nhật và đăng nhập lại để trải nghiệm tính năng mới nhất.", textAlign: TextAlign.center),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text("CẬP NHẬT NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            if (!force) TextButton(onPressed: () => Navigator.pop(context), child: Text("Để sau", style: TextStyle(color: Colors.grey[500]))),
          ],
        ),
      ),
    );
  }

  void _handleQRScan() async {
    final String? qrResult = await Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen()));
    if (qrResult != null && qrResult.isNotEmpty) {
      final LocalAuthentication auth = LocalAuthentication();
      try {
        bool didAuthenticate = await auth.authenticate(localizedReason: 'Xác thực để hoàn tất điểm danh qua QR', options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
        if (!didAuthenticate) return;
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _submitAttendance(qrResult, lat: position.latitude, lon: position.longitude, isBiometric: true);
      } catch (e) { _showErrorSnackBar("Lỗi xác thực hoặc GPS: $e"); }
    }
  }

  Future<void> _submitAttendance(String code, {double? lat, double? lon, bool isBiometric = false}) async {
    setState(() => _isLoading = true);
    try {
      final response = await Api.post("/api/attendance/submit", duLieu: {
        "student_id": studentId,
        "code": code,
        "lat": lat ?? 0.0,
        "lon": lon ?? 0.0,
        "is_biometric_valid": isBiometric,
      });
      final resData = jsonDecode(response.body);
      if (resData['status'] == 'success') { _showSuccessDialog("✅ Điểm danh thành công!"); }
      else { _showSnackBar(resData['message'] ?? "Lỗi điểm danh", Colors.red); }
    } catch (e) { _showSnackBar("🔥 Lỗi kết nối Server!", Colors.red); }
    finally { setState(() => _isLoading = false); }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
  void _showErrorSnackBar(String msg) => _showSnackBar(msg, Colors.red);
  void _showSuccessDialog(String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), title: const Icon(Icons.check_circle, color: Colors.green, size: 60), content: Text(msg, textAlign: TextAlign.center), actions: [Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("XÁC NHẬN")))]));
  }

  Future<void> _fetchUnreadCount() async {
    if (studentId.isEmpty) return;
    try {
      // Lấy qua kho dữ liệu thông báo để huy hiệu và danh sách luôn cùng một
      // con số. Gọi thẳng /api/count-unread như trước làm hai nơi lệch nhau khi
      // người dùng đã đọc tại máy mà máy chủ chưa ghi nhận.
      final so = await NotificationRepository.instance.soChuaDocChoHuyHieu();
      if (mounted) setState(() => _unreadCount = so);
    } catch (e) {}
  }

  Future<void> _fetchStudentExtraInfo(String id) async {
    final role = userRole.toLowerCase();
    // Chặn không gọi API nếu là Cán bộ hoặc Admin để tránh lỗi 404/500 từ Server
    if (id.isEmpty || role == 'canbo' || role == 'admin' || role == 'covan' || role == 'cb' || role == 'ad') {
      return;
    }

    final db = DatabaseHelper.instance;

    try {
      // 1. CHIẾN THUẬT OFFLINE: Hiển thị ngay dữ liệu từ SQLite (nếu có)
      final cachedStats = await db.getStudentStats(id);
      if (cachedStats != null && mounted) {
        setState(() => studentProfilesList = cachedStats);
      }

      // 2. CẬP NHẬT DỮ LIỆU MỚI: Gọi API với Timeout 15 giây
      // Tăng từ 5s lên 15s giúp tránh lỗi "Future not completed" khi server trường quá tải
      final response = await Api.get(
        '/api/student-info/$id',
        hanCho: const Duration(seconds: 120),
      );

      if (response.thanhCong) {
        final data = response.data is Map ? response.data as Map : const {};
        final List profiles = data['profiles'] ?? [];

        // 3. LƯU TRỮ: Cập nhật lại vào SQLite để dùng cho lần sau
        await db.saveStudentStats(id, profiles);

        // 4. HIỂN THỊ: Cập nhật giao diện nếu Widget vẫn còn "sống"
        if (mounted) {
          setState(() {
            studentProfilesList = profiles;
          });
        }
      }
    } on TimeoutException catch (_) {
      // Xử lý riêng lỗi quá thời gian để không báo lỗi đỏ lòm trên Console
      debugPrint("⏳ [Timeout] Server phản hồi quá lâu (15s). Đang dùng dữ liệu Cache.");
    } catch (e) {
      debugPrint("⚠️ [API Extra Info Error] $e");
    }
  }

  void _refreshAvatar() {
    setState(() {
      _avatarVersion = DateTime.now().millisecondsSinceEpoch;
      _initAppData(); 
    });
  }



@override
  @override
  Widget build(BuildContext context) {
    // 1. Sửa URL Avatar sang đường dẫn trực tiếp /$studentId để khớp Log Server
    String avatarUrl = 'https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId?v=$_avatarVersion';

    // 2. Danh sách các màn hình chính (Tab)
    final List<Widget> screens = [
      // Index 0: Trang chủ
      HomeContent(
        studentName: studentName, 
        studentId: studentId, 
        userRole: userRole, 
        faculty: userFaculty, 
        avatarUrl: avatarUrl, 
        appMenu: appMenu, 
        studentProfilesList: studentProfilesList, 
        // 🔥 TRUYỀN GIÁ TRỊ: Gán token đang có của HomeScreen cho HomeContent
        fbToken: fbToken, 
        sysToken: sysToken,
        onAvatarTap: () => setState(() => _currentIndex = 4), 
        onChatTap: () => setState(() => _currentIndex = 3),
      ),
      
      const ThongBaoScreen(), // Index 1
      const SizedBox(),        // Index 2
      
      // 🔥 INDEX 3: TRỢ LÝ AI (Native ChatScreen của Sơn)
      // Đây là màn hình Chat AI tích hợp sẵn trong App
      ChatScreen(key: chatScreenKey), 
            
      // Index 4: Cá nhân
      ProfileScreen(onAvatarUpdate: _refreshAvatar),
    ];

    // 3. Xử lý nút Back bằng PopScope để không bị văng ra Login
    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        if (_currentIndex != 0) {
          // Nếu đang ở bất kỳ tab nào khác, nhấn Back sẽ quay về Trang chủ
          setState(() => _currentIndex = 0);
        } else {
          // Chỉ thoát App khi đang ở đúng Trang chủ
          await SystemNavigator.pop(); 
        }
      },
      child: Scaffold(
        key: _scaffoldKey, 
        backgroundColor: const Color(0xFFF8FAFC),
        drawer: _buildModernDrawer(context, avatarUrl),
        
        // Sử dụng IndexedStack để giữ trạng thái cho Trợ lý AI
        body: IndexedStack(
          index: _currentIndex, 
          children: screens.asMap().entries.map((entry) {
            // Tất cả các tab dùng SafeArea để hiển thị đều đặn
            return SafeArea(child: entry.value);
          }).toList()
        ),
        
        bottomNavigationBar: _buildModernBottomBar(),
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context, String avatarUrl) {
    return Drawer(
      child: Column(
        children: [
          // --- 1. HEADER DRAWER (Thông tin cá nhân) ---
          Container(
            width: double.infinity, 
            padding: const EdgeInsets.only(top: 60, bottom: 30, left: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [vinhUniBlue, activeColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar sử dụng Cache để load nhanh
                Container(
                  width: 70, height: 70, 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white, width: 2)
                  ),
                  child: ClipOval(
                    child: (studentId != "") 
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl, 
                          cacheKey: studentId, 
                          fadeInDuration: Duration.zero, 
                          useOldImageOnUrlChange: true, 
                          fit: BoxFit.cover, 
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                          ), 
                          errorWidget: (context, url, error) => const Icon(
                            Icons.person, size: 40, color: Colors.white
                          )
                        )
                      : const Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                // Tên người dùng (Viết hoa cho chuyên nghiệp)
                Text(
                  studentName.toUpperCase(), 
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "Mã số: $studentId", 
                  style: const TextStyle(color: Colors.white70, fontSize: 13)
                ), 
                // Hiển thị đơn vị/khoa
                if (userFaculty.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0), 
                    child: Row(
                      children: [
                        const Icon(Icons.business_center_rounded, color: Colors.white70, size: 14),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            userFaculty, 
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        ),
                      ],
                    )
                  ),
              ],
            ),
          ),

          // --- 2. DANH SÁCH TÙY CHỌN ---
          ListTile(
            leading: Icon(Icons.home_rounded, color: vinhUniBlue), 
            title: const Text("Trang chủ", style: TextStyle(fontWeight: FontWeight.w500)), 
            onTap: () => Navigator.pop(context) // Đóng Drawer để quay về Home
          ),
          
          const Spacer(), // Đẩy nút Đăng xuất xuống cuối màn hình
          const Divider(indent: 20, endIndent: 20),

          // --- 3. NÚT ĐĂNG XUẤT (Bản fix lỗi kẹt Route) ---
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red), 
            title: const Text("Đăng xuất"), 
            onTap: () async {
              // 1. Khởi tạo SharedPreferences
              final prefs = await SharedPreferences.getInstance(); 
              
              // 2. Lưu lại thông tin Ghi nhớ (nếu có) trước khi xóa
              bool rememberMe = prefs.getBool('remember_me') ?? false;
              String? user = prefs.getString('saved_user');
              String? pass = prefs.getString('saved_pwd');

              // 3. Xóa sạch Session Token và ID người dùng
              await prefs.clear(); 

              // 4. Khôi phục thông tin Ghi nhớ để màn hình Login vẫn hiện Avatar
              if (rememberMe) {
                await prefs.setBool('remember_me', true);
                await prefs.setString('saved_user', user ?? "");
                await prefs.setString('saved_pwd', pass ?? "");
              }

              // 5. 🔥 CHỐT HẠ: Điều hướng về trang LOGIN (Phải dùng đúng tên '/login')
              if (context.mounted) {
                // Sơn phải dùng '/login' vì trong main.dart bạn đã đặt tên này
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            }
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

Widget _buildModernBottomBar() {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 15,
          offset: const Offset(0, -5),
        ),
      ],
    ),
    child: SafeArea(
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 2) {
            _handleQRScan(); // Luồng quét mã của Sơn
            return;
          }
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: vinhUniBlue, // 🔥 Không lỗi vì cha không có const
        unselectedItemColor: Colors.grey.shade400,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        showUnselectedLabels: true,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded), 
            label: "Trang chủ"
          ),
          BottomNavigationBarItem(
            icon: _unreadCount > 0 
                ? Badge(label: Text('$_unreadCount'), child: const Icon(Icons.notifications_rounded)) 
                : const Icon(Icons.notifications_rounded), 
            label: "Thông báo"
          ),
          // 🔥 CHỖ NÀY PHẢI BỎ CHỮ 'const' Ở ĐẦU
          BottomNavigationBarItem(
            icon: CircleAvatar(
              radius: 22,
              backgroundColor: vinhUniBlue, // 🔵 Dùng màu thoải mái ở đây
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 26),
            ),
            label: "Quét mã"
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded), 
            label: "Trợ lý AI"
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded), 
            label: "Cá nhân"
          ),
        ],
      ),
    ),
  );
}
}

class HomeContent extends StatefulWidget {
  final String studentName, studentId, userRole, faculty;
  final String? avatarUrl; 
  final List<dynamic> appMenu; 
  final List<dynamic> studentProfilesList;
  final VoidCallback? onAvatarTap, onChatTap; 
  
  // 1. Khai báo (Sơn đã làm bước này)
  final String? fbToken; 
  final String? sysToken;

  const HomeContent({
    super.key, 
    required this.studentName, 
    required this.studentId, 
    required this.userRole, 
    required this.faculty, 
    this.avatarUrl, 
    required this.appMenu, 
    required this.studentProfilesList, 
    this.onAvatarTap, 
    this.onChatTap,
    // 🔥 2. PHẢI CÓ DÒNG NÀY: Để nhận giá trị từ HomeScreen truyền vào
    this.fbToken, 
    this.sysToken,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  // --- [KHAI BÁO BIẾN TRẠNG THÁI] ---
  int _selectedTabIndex = 0;
  final Color vinhUniBlue = const Color(0xFF0054A6); //
  final _voiceService = VoiceControlService(); 
  bool _isVoiceLoading = false;

  // --- [HÀM HỖ TRỢ] ---

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), 
        backgroundColor: color, 
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      )
    );
  }

  // Xử lý điều hướng thông minh từ AI Intent
  void _handleVoiceNavigation(String route, String message) {
    if (route.isEmpty) {
      _showSnackBar("🤖 AI: $message", Colors.orange);
      return;
    }
    
    _showSnackBar("🚀 $message", Colors.green);

    // Dùng lớp phân quyền chung — xem lib/core/auth/user_role.dart
    final UserRole role = UserRole.parse(widget.userRole);
    final bool isStaff = role.isStaff;

    switch (route) {
      case '/ai_secretary': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const MeetingRecorderScreen())); 
        break;
      case '/vanban': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const VanBanScreen())); 
        break;
      case '/lichcongtac': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffScheduleScreen())); 
        break;
      case '/mo_diem_danh': 
        if (isStaff) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => MoDiemDanhScreen(lecturerId: widget.studentId))); 
        } else {
          _showSnackBar("Chức năng chỉ dành cho cán bộ", Colors.red);
        }
        break;
      case '/student_feedback':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentSendToStaffScreen()));
        break;
      case '/ket_qua_chung_nhan':
        Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId)));
        break;
      default: 
        try { 
          Navigator.pushNamed(context, route); 
        } catch (e) {
          _showSnackBar("Không tìm thấy chức năng này", Colors.red);
        }
        break;
    }
  }

  IconData _getIcon(String code) {
    switch (code) {
      case 'edit_calendar_rounded': return Icons.edit_calendar_rounded;
      case 'fact_check_rounded': return Icons.fact_check_rounded;
      case 'calendar_today': return Icons.calendar_today;
      case 'verified': return Icons.verified_user_rounded;
      case 'description_rounded': return Icons.description_rounded;  
      case 'card_membership': return Icons.card_membership;
      case 'event_note': return Icons.event_note;
      case 'assignment': return Icons.assignment;
      case 'bar_chart': return Icons.bar_chart;
      case 'schema_rounded': return Icons.schema_rounded;
      case 'grading_rounded': return Icons.grading_rounded;
      case 'account_balance_wallet_rounded': return Icons.account_balance_wallet_rounded;
      case 'health_and_safety_rounded': return Icons.health_and_safety_rounded;
      case 'military_tech_rounded': return Icons.military_tech_rounded;
      case 'card_giftcard_rounded': return Icons.card_giftcard_rounded;
      case 'warning_amber_rounded': return Icons.warning_amber_rounded;
      case 'campaign_rounded': return Icons.campaign_rounded;
      case 'auto_awesome': return Icons.auto_awesome;
      case 'settings': return Icons.settings;
      case 'leaderboard': return Icons.leaderboard_rounded;
      case 'account_box': return Icons.account_box_rounded;
      case 'contact_phone': return Icons.contact_phone_rounded;
      case 'chat_groups': return Icons.chat_rounded;
      case 'history_edu_rounded': return Icons.history_edu_rounded;
      case 'mic_external_on': return Icons.mic_external_on;
      case 'support_agent_rounded': return Icons.support_agent_rounded;
      case 'settings_suggest_rounded': return Icons.settings_suggest_rounded;
      case 'cloud_done_rounded': 
        return Icons.cloud_done_rounded;
      case 'school_rounded':
      return Icons.school_rounded;
      case 'document_scanner_rounded':
      return Icons.document_scanner_rounded;  
      default: return Icons.widgets_rounded; 
    }
  }

  // --- [GIAO DIỆN CHÍNH] ---

  @override
  Widget build(BuildContext context) {
    // Dùng lớp phân quyền chung — xem lib/core/auth/user_role.dart
    final UserRole role = UserRole.parse(widget.userRole);
    final bool isStaff = role.isStaff;
    
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), 
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(children: [
        _buildHeader(),
        if (isStaff) _buildTeacherBanner() else _buildStatisticCard(),
        _buildSearchBar(), 
        const SizedBox(height: 15),
        _buildFeatureGrid(isStaff),
        const SizedBox(height: 25),
        _buildNewsSection(),
      ]),
    );
  }

  // --- [CÁC COMPONENT GIAO DIỆN] ---

  Widget _buildHeader() {
    return Stack(
      children: [
        Container(height: 140, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0054A6), Color(0xFF0078D4)]), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.menu, color: Colors.white, size: 28), onPressed: () => Scaffold.of(context).openDrawer()),
              const SizedBox(width: 5),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.studentName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(widget.faculty.isNotEmpty ? widget.faculty : "Mã số: ${widget.studentId}", style: const TextStyle(color: Colors.white70, fontSize: 12))])),
              GestureDetector(
                onTap: widget.onAvatarTap, 
                child: Container(
                  width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: ClipOval(
                    child: (widget.studentId != "") 
                      ? CachedNetworkImage(imageUrl: widget.avatarUrl ?? "", cacheKey: widget.studentId, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.white))
                      : const Icon(Icons.person, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Trong _HomeContentState của home_screen.dart

String _voiceInstruction = "Tìm kiếm dịch vụ..."; // Mặc định

// --- [Nâng cấp giao diện Search Bar và Mic] ---
 Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())),
        child: Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.blue.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]), child: Row(children: [const Icon(Icons.search_rounded, color: Color(0xFF0054A6), size: 22), const SizedBox(width: 12), Expanded(child: Text("Tìm kiếm dịch vụ...", style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13))), Icon(Icons.mic_none_rounded, color: Colors.blueGrey.shade300, size: 20)])),
      ),
    );
  }

  Widget _buildFeatureGrid(bool isStaff) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(left: 5, bottom: 15), child: Text("Chức năng chính", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        if (widget.appMenu.isNotEmpty) GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9, 
          children: widget.appMenu.map((m) { 
            Color c = Color(int.parse(m['color'])); 
            return GestureDetector(
              onTap: () { 
                final String route = m['route'] ?? ''; 
                switch (route) { 
                  case '/diem_danh_sv': Navigator.push(context, MaterialPageRoute(builder: (context) => DiemDanhSvScreen(studentId: widget.studentId))); break; 
                  case '/mo_diem_danh': Navigator.push(context, MaterialPageRoute(builder: (context) => MoDiemDanhScreen(lecturerId: widget.studentId))); break; 
                  case '/quan_ly_nghi_hoc': Navigator.push(context, MaterialPageRoute(builder: (context) => QuanLyXinPhepScreen(studentId: widget.studentId))); break; 
                  case '/duyet_vang_hoc': Navigator.push(context, MaterialPageRoute(builder: (context) => DuyetVangHocScreen(lecturerId: widget.studentId))); break; 
                  case '/chatscreen': if (widget.onChatTap != null) widget.onChatTap!(); break; 
                  case '/profile': if (widget.onAvatarTap != null) widget.onAvatarTap!(); break; 
                  case '/vanban': Navigator.push(context, MaterialPageRoute(builder: (context) => const VanBanScreen())); break; 
                  case '/certificate_page': Navigator.push(context, MaterialPageRoute(builder: (context) => CertificatePage(studentId: widget.studentId))); break; 
                  case '/lichcongtac': Navigator.push(context, MaterialPageRoute(builder: (context) => StaffScheduleScreen())); break; 
                  case '/xep_loai': Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId, chucNang: 'XepLoai_ThangTheoCaNhan', title: 'Xếp loại cán bộ'))); break; 
                  case '/ho_so': Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId, chucNang: 'ho-so-ca-nhan', title: 'Hồ sơ cán bộ'))); break; 
                  case '/ket_qua_chung_nhan': Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId))); break; 
                  case '/ai_secretary': Navigator.push(context, MaterialPageRoute(builder: (context) => const MeetingRecorderScreen())); break;     
                  case '/student_feedback': Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentSendToStaffScreen())); break;
                  case '/student_secretary':
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const StudentSecretaryScreen())
                    );
                    break;

                  case '/document_scanner':
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const DocumentScannerScreen())
                    );
                    break;
                  case '/onedrive_manager': 
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const OneDriveManagerScreen())
                    ); 
                    break;
                  //case '/chat_group_list': 
                  //  if (isStaff) Navigator.push(context, MaterialPageRoute(builder: (context) => ChatGroupListPage(userCode: widget.studentId))); 
                  //  else _showSnackBar("Chức năng chỉ dành cho cán bộ", Colors.orange);
                  //  break;
                  // lib/views/home_screen.dart

                case '/chat_group_list': 
                    // Chuyển thẳng vào danh sách nhóm Native
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (context) => ChatGroupListPage(userCode: widget.studentId)
                      )
                    );
                    break;
                  default: Navigator.pushNamed(context, route); break; 
                } 
              }, 
              child: Column(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Icon(_getIcon(m['icon']), size: 30, color: c)), const SizedBox(height: 8), Text(m['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)]),
            ); 
          }).toList(),
        )
      ]),
    );
  }

  Widget _buildStatisticCard() {
    if (widget.studentProfilesList.isEmpty) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (_selectedTabIndex >= widget.studentProfilesList.length) _selectedTabIndex = 0;
    final current = widget.studentProfilesList[_selectedTabIndex];
    String status = current['trang_thai'] ?? "---";
    Color statusColor = status.toLowerCase().contains("tốt nghiệp") ? Colors.green : status.toLowerCase().contains("bảo lưu") ? Colors.orange : Colors.blue;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), transform: Matrix4.translationValues(0, -20, 0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(children: [
        if (widget.studentProfilesList.length > 1) Container(height: 38, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Row(children: List.generate(widget.studentProfilesList.length, (index) => Expanded(child: GestureDetector(onTap: () => setState(() => _selectedTabIndex = index), child: Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: index == _selectedTabIndex ? vinhUniBlue : Colors.transparent, width: 2.5))), child: Text(widget.studentProfilesList[index]['ten_nganh'] ?? 'Ngành', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: index == _selectedTabIndex ? FontWeight.bold : FontWeight.w500, color: index == _selectedTabIndex ? vinhUniBlue : Colors.grey.shade500)))))))),
        Padding(padding: const EdgeInsets.all(18), child: Column(children: [if (widget.studentProfilesList.length == 1) Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(current['ten_nganh'] ?? "Ngành học", style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 14))), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_statBox("GPA", current['gpa'].toString(), vinhUniBlue), Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)), _statBox("Tín chỉ", current['tin_chi'].toString(), vinhUniBlue), Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)), _statBox("Xếp loại", current['rank'], const Color(0xFF1B5E20))]), const SizedBox(height: 18), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Trạng thái:", style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)))])]))
      ]),
    );
  }

  Widget _statBox(String label, String val, Color c) => Column(children: [Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600))]);
  
 Widget _buildTeacherBanner() => Container(
  margin: const EdgeInsets.symmetric(horizontal: 20),
  transform: Matrix4.translationValues(0, -20, 0), // Giữ nguyên hiệu ứng đè lên header
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: vinhUniBlue.withOpacity(0.2)),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)
    ],
  ),
  child: Row(
    children: [
      // Icon bảo mật/quản trị
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.admin_panel_settings_rounded, 
          color: Colors.orange, 
          size: 32,
        ),
      ),
      const SizedBox(width: 16),
      // Chỉ giữ lại tiêu đề chính
      const Expanded(
        child: Text(
          "Cổng thông tin Cán bộ",
          style: TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold, 
            color: Color(0xFF003366),
          ),
        ),
      ),
    ],
  ),
); 
  Widget _buildNewsSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Text("Khám phá VinhUni", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), SizedBox(height: 150, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 20, right: 10), children: [_buildNewsCard("Thư viện số", "Tài liệu online", Icons.auto_stories, Colors.blue, "https://thuvien.vinhuni.edu.vn/"), _buildNewsCard("Tin tức", "Thông báo mới", Icons.newspaper, Colors.green, "https://vinhuni.edu.vn/"), _buildNewsCard("Hotline", "Hỗ trợ SV", Icons.headset_mic, Colors.orange, "tel:02383855452")]))]);
  
  Widget _buildNewsCard(String title, String desc, IconData icon, Color color, String url) => GestureDetector(onTap: () async { final uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: Container(width: 220, margin: const EdgeInsets.only(right: 15), padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]), borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.white, size: 28), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11))])])));
}