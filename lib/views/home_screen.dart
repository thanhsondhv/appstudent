import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
// Import các màn hình
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

final GlobalKey<ChatScreenState> chatScreenKey = GlobalKey<ChatScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- 1. CẤU HÌNH MÀU SẮC & TRẠNG THÁI ---
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color activeColor = const Color(0xFF0078D4);
  bool _isLoading = false;
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- 2. THÔNG TIN NGƯỜI DÙNG ---
  String studentName = "Đang tải...";
  String studentId = ""; 
  String userRole = "SinhVien"; 
  String userFaculty = ""; 
  String userDept = "";    
  
  List<dynamic> studentProfilesList = [];
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;
  int _unreadCount = 0; 
  List<dynamic> appMenu = [];

  @override
void initState() {
  super.initState();
  
  // 1. Khởi tạo các dữ liệu ngầm (User, Token...)
  _initAppData();

  // 2. Kiểm tra phiên bản (Đợi App dựng xong 1 khung hình rồi mới hiện BottomSheet)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkVersion(); 
  });
}

  Future<void> _initAppData() async {
  // 1. Load User Info lên trước để lấy Role
  await _loadUserInfo(); 
  
  // 2. Chạy song song các vụ bốc dữ liệu khác
  Future.wait([
    _fetchDynamicMenu(),
    if (studentId.isNotEmpty) _fetchStudentExtraInfo(studentId),
  ]);

  if (studentId.isNotEmpty) {
    NotificationService.syncTokenToServer(studentId); 
  }
}
 
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      String rawId = prefs.getString('user_code') ?? "";
      String cleanId = rawId.toUpperCase().replaceFirst(RegExp(r'^SV'), '');
      setState(() {
        studentId = cleanId;
        studentName = prefs.getString('full_name') ?? prefs.getString('user_name') ?? "Người dùng";
        userRole = prefs.getString('user_role') ?? "SinhVien";
        userFaculty = prefs.getString('user_faculty') ?? ""; 
        userDept = prefs.getString('user_dept') ?? "";
      });
      _fetchUnreadCount(); 
    }
  }
 // Thêm hàm so sánh thông minh này vào class _HomeScreenState
bool _isNewerVersion(String current, String latest) {
  try {
    // Tách "1.2.0+14" thành ["1.2.0", "14"]
    List<String> curParts = current.split('+');
    List<String> latParts = latest.split('+');

    // 1. So sánh phần Version trước (1.2.0)
    if (curParts[0] != latParts[0]) {
      return true; // Khác version chính là cần update
    }

    // 2. Nếu version giống nhau, so sánh Build Number (14 vs 15)
    int curBuild = int.parse(curParts.length > 1 ? curParts[1] : "0");
    int latBuild = int.parse(latParts.length > 1 ? latParts[1] : "0");

    return latBuild > curBuild; // Chỉ hiện update nếu bản server lớn hơn bản máy
  } catch (e) {
    return false;
  }
}

Future<void> _checkVersion() async {
  debugPrint("🚀 Đang bắt đầu check version...");
  try {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String currentVer = "${packageInfo.version}+${packageInfo.buildNumber}";

    //debugPrint("📱 Version hiện tại trên máy: $currentVer");

    final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/check-version'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      Map<String, dynamic> platformData = Platform.isAndroid ? data['android'] : data['ios'];

      String latestVer = platformData['latest_version'];
      debugPrint("☁️ Version mới nhất trên Server: $latestVer");

      bool needUpdate = _isNewerVersion(currentVer, latestVer);
      debugPrint("🔍 Kết quả so sánh: ${needUpdate ? 'CẦN UPDATE' : 'KHÔNG CẦN'}");

      if (needUpdate) {
        _showUpdateDialog(currentVer, latestVer, platformData['url'], platformData['is_force']);
      }
    }
  } catch (e) {
    debugPrint("🔥 Lỗi Debug: $e");
  }
}
// Thêm tham số String url vào hàm
void _showUpdateDialog(String current, String latest, String url, bool force) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: !force,
    enableDrag: !force,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
            child: Icon(Icons.rocket_launch_rounded, size: 50, color: vinhUniBlue),
          ),
          const SizedBox(height: 20),
          const Text("Đã có phiên bản mới!!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            "VinhUni App đã có bản $latest. Vui lòng cập nhật để trải nghiệm tính năng mới nhất.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(url); // Dùng URL truyền từ API xuống
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: vinhUniBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("CẬP NHẬT NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (!force)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Để sau", style: TextStyle(color: Colors.grey[500])),
            ),
        ],
      ),
    ),
  );
}

Widget _buildVersionInfo(String label, String ver, Color color) {
  return Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 4),
      Text(ver, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ],
  );
}
  // --- 4. LOGIC ĐIỂM DANH (QR + FACEID + GPS) ---
  void _handleQRScan() async {
    final String? qrResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (qrResult != null && qrResult.isNotEmpty) {
      final LocalAuthentication auth = LocalAuthentication();
      try {
        bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Xác thực để hoàn tất điểm danh qua QR',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );

        if (!didAuthenticate) {
          _showErrorSnackBar("Xác thực sinh trắc học thất bại!");
          return;
        }

        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

        _submitAttendance(
          qrResult, 
          lat: position.latitude, 
          lon: position.longitude, 
          isBiometric: true
        );
      } catch (e) {
        _showErrorSnackBar("Lỗi xác thực hoặc GPS: $e");
      }
    }
  }

  Future<void> _submitAttendance(String code, {double? lat, double? lon, bool isBiometric = false}) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/submit"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": studentId,
          "code": code,
          "lat": lat ?? 0.0,
          "lon": lon ?? 0.0,
          "is_biometric_valid": isBiometric,
        }),
      );

      final resData = jsonDecode(response.body);
      if (mounted) {
        if (resData['status'] == 'success') {
          _showSuccessDialog("✅ Điểm danh thành công!");
        } else {
          _showSnackBar(resData['message'] ?? "Lỗi điểm danh", Colors.red);
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar("🔥 Lỗi kết nối Server!", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  void _showErrorSnackBar(String msg) => _showSnackBar(msg, Colors.red);

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("XÁC NHẬN")))],
      ),
    );
  }

  Future<void> _fetchDynamicMenu() async {
  final prefs = await SharedPreferences.getInstance();
  
  // 1. Xác định Role chuẩn (Ưu tiên lấy từ biến đã load ở _loadUserInfo)
  String rawRole = (prefs.getString('user_role') ?? userRole).toLowerCase().trim();
  String roleForApi = (rawRole == 'admin' || rawRole == 'ad' || rawRole == 'covan' || rawRole == 'canbo' || rawRole == 'cb') 
      ? "CB" 
      : "SV";

  final cacheKey = 'cache_app_menu_$roleForApi';

  // 2. 🔥 BƯỚC 1: HIỆN CACHE NGAY LẬP TỨC (0.01 giây)
  final cachedStr = prefs.getString(cacheKey);
  if (cachedStr != null && cachedStr.isNotEmpty) {
    final List<dynamic> cachedData = json.decode(cachedStr);
    if (mounted) {
      setState(() {
        appMenu = cachedData;
      });
      debugPrint("🚀 Đã hiện Menu từ máy (Cache)");
    }
  }

  // 3. 🔥 BƯỚC 2: GỌI API CẬP NHẬT NGẦM
  try {
    final url = 'https://mobi.vinhuni.edu.vn/api/app-menu/$roleForApi';
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final List<dynamic> newData = json.decode(response.body);
      
      // Nếu dữ liệu mới khác dữ liệu cũ thì mới update UI để tránh lag
      if (json.encode(newData) != cachedStr) {
        await prefs.setString(cacheKey, response.body); // Lưu cache mới
        if (mounted) {
          setState(() {
            appMenu = newData;
          });
        }
        debugPrint("✅ Đã cập nhật Menu mới từ Server");
      }
    }
  } catch (e) {
    debugPrint("🔥 Lỗi mạng khi tải Menu: $e");
    // Nếu lỗi mạng mà đã có cache thì vẫn dùng cache, không báo lỗi cho user
  }
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
    final role = userRole.toLowerCase(); // Lấy từ biến role đã có
    
    // Nếu là nhân sự thì không cần load bảng điểm
    if (id.isEmpty || role == 'canbo' || role == 'admin' || role == 'covan' || role == 'ad' || role == 'cb') {
      return;
    }

    final db = DatabaseHelper.instance;

    // 🔥 1. ĐỌC CACHE SQLITE TRƯỚC (Hiện số ngay lập tức)
    try {
      final cachedStats = await db.getStudentStats(id);
      if (cachedStats != null && mounted) {
        setState(() => studentProfilesList = cachedStats);
      }
    } catch (e) {
      debugPrint("Lỗi đọc cache stats: $e");
    }

    // 🔥 2. GỌI MẠNG CẬP NHẬT (Âm thầm)
    try {
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/student-info/$id'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List profiles = data['profiles'] ?? [];
        
        // Lưu vào máy cho lần sau
        await db.saveStudentStats(id, profiles);
        
        if (mounted) {
          setState(() => studentProfilesList = profiles);
        }
      }
    } catch (e) {
      debugPrint("Offline: Đang hiển thị điểm số cũ.");
    }
  }

  void _refreshAvatar() {
    setState(() {
      _avatarVersion = DateTime.now().millisecondsSinceEpoch;
      _loadUserInfo(); 
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    // Tạo URL avatar có version để tránh bị cache ảnh cũ
    String avatarUrl = 'https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId?v=$_avatarVersion';

    // Danh sách các màn hình tương ứng với BottomNavigationBar
    final List<Widget> screens = [
      HomeContent(
        studentName: studentName, 
        studentId: studentId, 
        userRole: userRole, // Role từ SharedPreferences
        faculty: userFaculty, 
        avatarUrl: avatarUrl, 
        appMenu: appMenu, 
        studentProfilesList: studentProfilesList, 
        onAvatarTap: () => setState(() => _currentIndex = 4), // Chuyển sang tab Cá nhân
        onChatTap: () => setState(() => _currentIndex = 3),  // Chuyển sang tab Chat AI
      ),
      const ThongBaoScreen(),
      const SizedBox(), // Chỗ trống giữ chỗ cho nút Quét mã ở giữa
      ChatScreen(key: chatScreenKey), 
      ProfileScreen(onAvatarUpdate: _refreshAvatar),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: _buildModernDrawer(context, avatarUrl),
      body: IndexedStack(
        index: _currentIndex, 
        // Logic SafeArea: Riêng màn hình Chat (index 3) cho phép tràn viền để đẹp hơn
        children: screens.asMap().entries.map((entry) {
          return entry.key == 3 ? entry.value : SafeArea(child: entry.value);
        }).toList(),
      ),
      bottomNavigationBar: _buildModernBottomBar(),
    );
  }

  Widget _buildModernDrawer(BuildContext context, String avatarUrl) {
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 30, left: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [vinhUniBlue, activeColor])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 35, backgroundColor: Colors.white, backgroundImage: NetworkImage(avatarUrl)),
                const SizedBox(height: 12),
                Text(studentName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("Mã số: $studentId", style: const TextStyle(color: Colors.white70, fontSize: 14)), 
                if (userFaculty.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text("💼 $userFaculty", style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                if (userDept.isNotEmpty) 
                  Text("🏛 $userDept", style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ListTile(leading: Icon(Icons.home, color: vinhUniBlue), title: const Text("Trang chủ"), onTap: () => Navigator.pop(context)),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Đăng xuất"),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildModernBottomBar() {
    return SafeArea(
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          // 🔥 Nếu nhấn vào nút ở giữa (index 2), thực hiện quét QR luôn
          if (index == 2) {
            _handleQRScan();
            return;
          }
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: vinhUniBlue,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Trang chủ"),
          BottomNavigationBarItem(
            icon: _unreadCount > 0 ? Badge(label: Text('$_unreadCount'), child: const Icon(Icons.notifications_rounded)) : const Icon(Icons.notifications_rounded),
            label: "Thông báo"
          ),
          // 🔥 Nút Quét mã thay cho SizedBox trống
          const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner_rounded), label: "Quét mã"),
          const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: "Trợ lý AI"),
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Cá nhân"),
        ],
      ),
    );
  }
}

// Giữ nguyên class HomeContent của bạn nhưng thay faculty bằng widget.faculty

class HomeContent extends StatefulWidget {
  final String studentName, studentId, userRole, faculty;
  final String? avatarUrl; 
  final List<dynamic> appMenu; 
  final List<dynamic> studentProfilesList;
  final VoidCallback? onAvatarTap, onChatTap; 

  const HomeContent({
    super.key, 
    required this.studentName, required this.studentId, required this.userRole, required this.faculty, 
    this.avatarUrl, required this.appMenu, required this.studentProfilesList, 
    this.onAvatarTap, this.onChatTap, 
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  int _selectedTabIndex = 0;

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
      case 'leaderboard': return Icons.leaderboard_rounded; // Cho Xếp loại
      case 'account_box': return Icons.account_box_rounded; // Cho Hồ sơ
      case 'contact_phone': return Icons.contact_phone_rounded; // Cho Danh bạ
      case 'chat_groups': return Icons.chat_rounded; // Cho Nhóm chat
      default: return Icons.widgets_rounded; 
    }
  }


  @override
  Widget build(BuildContext context) {
    // Chuẩn hóa role về chữ thường để so sánh không bị sai
    final String role = widget.userRole.toLowerCase();
    
    // Kiểm tra xem người dùng có phải là nhân sự (Staff) hay không
    bool isStaff = role == 'canbo' || role == 'admin' || role == 'covan' || role == 'ad' || role == 'cb';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        children: [
          _buildHeader(),
          
          // 🔥 FIX LỖI XOAY TẠI ĐÂY:
          // Nếu là nhân sự (Admin/Cố vấn/Cán bộ) thì hiện Banner, không hiện Bảng điểm
          if (isStaff) 
            _buildTeacherBanner() 
          else 
            _buildStatisticCard(),
            
          _buildSearchBar(), 
          const SizedBox(height: 15),
          _buildFeatureGrid(), 
          const SizedBox(height: 25),
          _buildNewsSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        Container(
          height: 140, 
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0054A6), Color(0xFF0078D4)]),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.menu, color: Colors.white, size: 28), onPressed: () => Scaffold.of(context).openDrawer()),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(widget.studentName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(widget.faculty.isNotEmpty ? widget.faculty : "Mã số: ${widget.studentId}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    
                  ]
                ),
              ),
              GestureDetector(
                onTap: widget.onAvatarTap, 
                child: CircleAvatar(radius: 26, backgroundImage: NetworkImage(widget.avatarUrl ?? "")),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticCard() {
    const Color premiumBlue = Color(0xFF003366); 
    if (widget.studentProfilesList.isEmpty) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (_selectedTabIndex >= widget.studentProfilesList.length) _selectedTabIndex = 0;
    final current = widget.studentProfilesList[_selectedTabIndex];
    String nganhHoc = current['ten_nganh'] ?? current['lop_hanh_chinh'] ?? "Ngành học";
    String status = current['trang_thai'] ?? "---";
    Color statusColor = status.toLowerCase().contains("tốt nghiệp") ? Colors.green : status.toLowerCase().contains("bảo lưu") ? Colors.orange : Colors.blue;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      transform: Matrix4.translationValues(0, -20, 0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200, width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        children: [
          if (widget.studentProfilesList.length > 1)
            Container(
              height: 38, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(
                children: List.generate(widget.studentProfilesList.length, (index) {
                  bool isActive = index == _selectedTabIndex;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = index),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? premiumBlue : Colors.transparent, width: 2.5))),
                        child: Text(widget.studentProfilesList[index]['ten_nganh'] ?? 'Ngành', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: isActive ? premiumBlue : Colors.grey.shade500)),
                      ),
                    ),
                  );
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                if (widget.studentProfilesList.length == 1) Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(nganhHoc, style: const TextStyle(fontWeight: FontWeight.bold, color: premiumBlue, fontSize: 14))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBox("GPA", current['gpa'].toString(), premiumBlue),
                    Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)),
                    _statBox("Tín chỉ", current['tin_chi'].toString(), premiumBlue),
                    Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)),
                    _statBox("Xếp loại", current['rank'], const Color(0xFF1B5E20)),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Trạng thái:", style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, Color c) => Column(children: [Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c, letterSpacing: -0.5)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600))]);

  Widget _buildTeacherBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      transform: Matrix4.translationValues(0, -20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF003366).withOpacity(0.2), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 32)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Cổng thông tin Cán bộ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF003366))), const SizedBox(height: 4), Text("Hệ thống quản lý, hỗ trợ  người học", style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4))]))]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())),
        child: Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.blue.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]), child: Row(children: [const Icon(Icons.search_rounded, color: Color(0xFF0054A6), size: 22), const SizedBox(width: 12), Expanded(child: Text("Tìm kiếm dịch vụ...", style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13))), Icon(Icons.mic_none_rounded, color: Colors.blueGrey.shade300, size: 20)])),
      ),
    );
  }

  Widget _buildFeatureGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(left: 5, bottom: 15), child: Text("Chức năng chính", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        if (widget.appMenu.isNotEmpty)
          GridView.count(
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
                    // --- TÍCH HỢP CỔNG CÁN BỘ (WEBVIEW) ---
                    case '/xep_loai':
                      Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(
                        hsid: widget.studentId, 
                        chucNang: 'XepLoai_ThangTheoCaNhan', // Slug URL phía Odoo
                        title: 'Xếp loại cán bộ'
                      ))); break;
                    case '/ho_so':
                      Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(
                        hsid: widget.studentId, 
                        chucNang: 'ho-so-ca-nhan', 
                        title: 'Hồ sơ cán bộ'
                      ))); break;
                    case '/ket_qua_chung_nhan': Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId))); break;
                    //---
                    case '/chat_group_list': 
                      final String role = widget.userRole.toLowerCase();
                      bool isStaffLocal = role == 'canbo' || role == 'admin' || role == 'covan' || role == 'ad' || role == 'cb';

                      if (isStaffLocal) {
                        Navigator.push(
                          context, 
                          MaterialPageRoute(
                            builder: (context) => ChatRoomPage(
                              groupId: 'GROUP_CAN_BO_TOAN_TRUONG', 
                              userCode: widget.studentId,
                              // ĐÃ XÓA userRole và isLocked ở đây vì Page sẽ tự lấy từ API
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Chức năng điều hành hiện chỉ dành cho cán bộ."),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      break;
                    //---
                    default: try { Navigator.pushNamed(context, route); } catch (e) {} break;
                  }
                },
                child: Column(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Icon(_getIcon(m['icon']), size: 30, color: c)), const SizedBox(height: 8), Text(m['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)]),
              );
            }).toList(),
          ),
      ]),
    );
  }

  Widget _buildNewsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Text("Khám phá VinhUni", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(height: 150, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 20, right: 10), children: [_buildNewsCard("Thư viện số", "Tài liệu online", Icons.auto_stories, Colors.blue, "https://thuvien.vinhuni.edu.vn/"), _buildNewsCard("Tin tức", "Thông báo mới", Icons.newspaper, Colors.green, "https://vinhuni.edu.vn/"), _buildNewsCard("Hotline", "Hỗ trợ SV", Icons.headset_mic, Colors.orange, "tel:02383855452")])),
    ]);
  }

  Widget _buildNewsCard(String title, String desc, IconData icon, Color color, String url) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        width: 220, margin: const EdgeInsets.only(right: 15), padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.white, size: 28), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11))])]),
      ),
    );
  }
}