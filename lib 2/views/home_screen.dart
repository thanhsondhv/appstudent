import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';

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
  String userFaculty = ""; // Chức vụ/Khoa
  String userDept = "";    // Phòng ban
  
  List<dynamic> studentProfilesList = [];
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;
  int _unreadCount = 0; 
  List<dynamic> appMenu = [];

  @override
  void initState() {
    super.initState();
    _initAppData();
  }

  Future<void> _initAppData() async {
    await _loadUserInfo();
    _fetchDynamicMenu();
    if (studentId.isNotEmpty) {
      _fetchStudentExtraInfo(studentId);
      NotificationService.syncTokenToServer(studentId); 
    }
  }

  // --- 3. LOAD THÔNG TIN (DUY NHẤT 1 HÀM) ---
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

  // --- 5. TIỆN ÍCH UI ---
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

  // --- 6. API FETCHING ---
  Future<void> _fetchDynamicMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_app_menu_$userRole';
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      setState(() => appMenu = json.decode(cachedStr));
    }
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/app-menu/$userRole';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        await prefs.setString(cacheKey, response.body);
        if (mounted) setState(() => appMenu = data);
      }
    } catch (e) {}
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
    if (id.isEmpty || userRole == 'CanBo') return;
    try {
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/student-info/$id'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => studentProfilesList = data['profiles'] ?? []);
      }
    } catch (e) {}
  }

  void _refreshAvatar() {
    setState(() {
      _avatarVersion = DateTime.now().millisecondsSinceEpoch;
      _loadUserInfo(); 
    });
  }

  @override
  Widget build(BuildContext context) {
    String avatarUrl = 'https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId?v=$_avatarVersion';

    final List<Widget> screens = [
      HomeContent(
        studentName: studentName, studentId: studentId, userRole: userRole,
        faculty: userFaculty, avatarUrl: avatarUrl, appMenu: appMenu, 
        studentProfilesList: studentProfilesList, 
        onAvatarTap: () => setState(() => _currentIndex = 4),
        onChatTap: () => setState(() => _currentIndex = 3),
      ),
      const ThongBaoScreen(),
      const SizedBox(), 
      ChatScreen(key: chatScreenKey), 
      ProfileScreen(onAvatarUpdate: _refreshAvatar),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: _buildModernDrawer(context, avatarUrl),
      body: IndexedStack(
        index: _currentIndex, 
        children: screens.asMap().entries.map((entry) {
          return entry.key == 3 ? entry.value : SafeArea(child: entry.value);
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleQRScan,
        backgroundColor: const Color(0xFF003366),
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
          if (index == 2) return; 
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: vinhUniBlue,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Trang chủ"),
          BottomNavigationBarItem(
            icon: _unreadCount > 0 ? Badge(label: Text('$_unreadCount'), child: const Icon(Icons.notifications_rounded)) : const Icon(Icons.notifications_rounded),
            label: "Thông báo"
          ),
          const BottomNavigationBarItem(icon: SizedBox.shrink(), label: ""),
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
      default: return Icons.widgets_rounded; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        children: [
          _buildHeader(),
          if (widget.userRole != 'CanBo') _buildStatisticCard(),
          if (widget.userRole == 'CanBo') _buildTeacherBanner(),
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
      child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 32)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Cổng thông tin Cán bộ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF003366))), const SizedBox(height: 4), Text("Hệ thống quản lý và hỗ trợ đào tạo VinhUni", style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4))]))]),
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
                    case '/ket_qua_chung_nhan': Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId))); break;
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