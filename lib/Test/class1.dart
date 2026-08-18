//homehome_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
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
import 'package:vinhuni_app/views/chatgroup/chat_room_page.dart';
import 'package:vinhuni_app/views/chatgroup/chat_group_list_page.dart';
import 'package:vinhuni_app/views/notification/student_send_to_staff_screen.dart';
import 'package:vinhuni_app/views/secretary/meeting_recorder_screen.dart';
import 'package:vinhuni_app/services/voice_control_service.dart';
import 'package:vinhuni_app/views/secretary/secretary_service.dart';
import 'package:flutter/services.dart';
import 'package:vinhuni_app/views/onedrive_manager_screen.dart';
import 'package:vinhuni_app/services/onedrive_service.dart';
import 'package:vinhuni_app/views/secretary/document_scanner_screen.dart';
import 'package:vinhuni_app/views/secretary/student_secretary_screen.dart';
import 'package:vinhuni_app/views/teams/teams_chat_list_screen.dart';
final GlobalKey<ChatScreenState> chatScreenKey = GlobalKey<ChatScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _voiceService = VoiceControlService(); 
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
    
    _initAppData();
    WidgetsBinding.instance.addPostFrameCallback((_) { _checkVersion(); });
  }

  Future<void> _initAppData() async {
  final prefs = await SharedPreferences.getInstance();
  final db = DatabaseHelper.instance; // Khởi tạo CSDL
  
  // 1. Lấy và làm sạch dữ liệu người dùng từ bộ nhớ đệm
  String rawId = prefs.getString('user_code') ?? "";
  String cleanId = rawId.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
  String role = prefs.getString('user_role') ?? "SinhVien";
  
  if (mounted) {
    setState(() {
      studentId = cleanId;
      studentName = prefs.getString('full_name') ?? prefs.getString('user_name') ?? "Người dùng";
      userRole = role;
      userFaculty = prefs.getString('user_faculty') ?? ""; 
      _avatarVersion = prefs.getInt('avatar_version') ?? 0;
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
    // 1. Lấy token
    String? token = prefs.getString('access_token');
    
    // 🛡️ CHẶN LỖI: Nếu token null thì dừng lại ngay
    if (token == null || token.isEmpty) {
      debugPrint("🚫 [Menu] Bỏ qua vì Token đang NULL. Đang đợi đăng nhập...");
      return; 
    }

    try {
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/app-menu'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token", 
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> newData = json.decode(response.body);
        if (mounted) {
          setState(() {
            appMenu = newData;
            _isLoading = false;
          });
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
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/check-version'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
      final response = await http.post(Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/submit"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"student_id": studentId, "code": code, "lat": lat ?? 0.0, "lon": lon ?? 0.0, "is_biometric_valid": isBiometric}));
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
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/count-unread/$studentId'));
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        setState(() => _unreadCount = data['unread_count'] ?? 0);
      }
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
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/student-info/$id'),
      ).timeout(const Duration(seconds: 120)); 

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
  Widget build(BuildContext context) {
    String avatarUrl = 'https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=$studentId&v=$_avatarVersion';
    final List<Widget> screens = [
      HomeContent(
        studentName: studentName, studentId: studentId, userRole: userRole, faculty: userFaculty, 
        avatarUrl: avatarUrl, appMenu: appMenu, studentProfilesList: studentProfilesList, 
        onAvatarTap: () => setState(() => _currentIndex = 4), onChatTap: () => setState(() => _currentIndex = 3),
      ),
      const ThongBaoScreen(), const SizedBox(),
      ChatScreen(key: chatScreenKey), ProfileScreen(onAvatarUpdate: _refreshAvatar),
    ];
    return Scaffold(
      key: _scaffoldKey, backgroundColor: const Color(0xFFF8FAFC),
      drawer: _buildModernDrawer(context, avatarUrl),
      body: IndexedStack(index: _currentIndex, children: screens.asMap().entries.map((entry) => entry.key == 3 ? entry.value : SafeArea(child: entry.value)).toList()),
      bottomNavigationBar: _buildModernBottomBar(),
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
    this.onChatTap
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}