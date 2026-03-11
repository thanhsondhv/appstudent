import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'search_screen.dart';
import 'chungchi_tracuu.dart';

// Import các file màn hình khác
import 'chat_screen.dart';
import 'thongbao_screen.dart';
import 'profile_screen.dart';
import 'certificate_page.dart';
import 'schedule__canbo_screen.dart';
import 'api_service_lichcanbo.dart';
import 'vanban_screen.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color activeColor = const Color(0xFF0078D4);
  
  int _currentIndex = 0;
  String studentName = "Đang tải...";
  String studentId = ""; 
  String userRole = "SinhVien"; 
  String faculty = "";
  
  // 🔥 Biến lưu DANH SÁCH LỚP VÀ ĐIỂM (Hỗ trợ sinh viên học nhiều ngành)
  List<dynamic> studentProfilesList = [];

  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;
  int _unreadCount = 0; 

  // BIẾN LƯU MENU TỪ SERVER
  List<dynamic> appMenu = [];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Luồng khởi tạo: Load User -> Load Menu -> Load Profile/Diem
    _loadUserInfo().then((_) {
      _fetchDynamicMenu();
      if (studentId.isNotEmpty) {
        _fetchStudentExtraInfo(studentId);
      }
    });
    
    NotificationService.onRefreshBadge = () {
      if (mounted) _fetchUnreadCount();
    };
  }

  // =======================================================
  // 🔥 GỌI API LẤY LỚP VÀ ĐIỂM TÍCH LŨY (CÓ CACHE)
  // =======================================================
  Future<void> _fetchStudentExtraInfo(String id) async {
    if (id.isEmpty || userRole == 'CanBo') return;

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_student_full_info_$id';

    // 1. Đọc Cache trước
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null) {
      final data = jsonDecode(cachedStr);
      if (mounted) setState(() => studentProfilesList = data['profiles'] ?? []);
    }

    // 2. Gọi API ngầm lấy dữ liệu (Hồ sơ + Điểm)
    try {
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/student-info/$id'),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          prefs.setString(cacheKey, response.body); // Lưu đè cache
          if (mounted) setState(() => studentProfilesList = data['profiles'] ?? []);
        }
      }
    } catch (e) {
      debugPrint("Offline: Dùng Cache Student Info");
    }
  }

  // =======================================================
  // LOAD MENU ĐỘNG TỪ SQL (OFFLINE-FIRST)
  // =======================================================
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
        if (json.encode(data) != cachedStr) {
          await prefs.setString(cacheKey, response.body);
          if (mounted) setState(() => appMenu = data);
        }
      }
    } catch (e) {}
  }

  Future<void> _fetchUnreadCount() async {
    if (studentId.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/count-unread/$studentId?v=${DateTime.now().millisecondsSinceEpoch}'),
      );
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        setState(() => _unreadCount = data['unread_count'] ?? 0);
      }
    } catch (e) {}
  }

  // =======================================================
  // 🔥 XỬ LÝ LOAD USER & CẮT TIỀN TỐ "SV"
  // =======================================================
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      String rawId = prefs.getString('user_code') ?? "";
      // Cắt bỏ chữ SV ở đầu
      String cleanId = rawId.toUpperCase().replaceFirst(RegExp(r'^SV'), '');

      setState(() {
        studentId = cleanId;
        studentName = prefs.getString('full_name') ?? "Người dùng";
        userRole = prefs.getString('user_role') ?? "SinhVien";
        faculty = prefs.getString('faculty') ?? "";
      });
      _fetchUnreadCount(); 
    }
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
        studentName: studentName, 
        studentId: studentId, 
        userRole: userRole,
        faculty: faculty, 
        avatarUrl: avatarUrl,
        appMenu: appMenu, 
        studentProfilesList: studentProfilesList, 
        onAvatarTap: () => setState(() => _currentIndex = 4),
        onChatTap: () {
          setState(() => _currentIndex = 3);
          Future.delayed(const Duration(milliseconds: 200), () => chatScreenKey.currentState?.activateChatTab());
        },
      ),
      const ThongBaoScreen(),
      const SizedBox(), 
      ChatScreen(key: chatScreenKey), 
      ProfileScreen(onAvatarUpdate: _refreshAvatar),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: false, 
      drawer: _buildModernDrawer(context, avatarUrl),
      
      body: IndexedStack(
        index: _currentIndex, 
        children: screens.asMap().entries.map((entry) {
          if (entry.key == 3) return entry.value; 
          return SafeArea(child: entry.value);
        }).toList(),
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
                CircleAvatar(
                  radius: 35, backgroundColor: Colors.white,
                  backgroundImage: NetworkImage(avatarUrl),
                  onBackgroundImageError: (_, __) {},
                ),
                const SizedBox(height: 12),
                Text(studentName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("Mã số: $studentId", style: const TextStyle(color: Colors.white70, fontSize: 14)), 
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
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        if (index == 2) return; 
        FocusScope.of(context).unfocus();
        setState(() => _currentIndex = index);
        if (index == 3) Future.delayed(const Duration(milliseconds: 200), () => chatScreenKey.currentState?.activateChatTab());
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: vinhUniBlue,
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Trang chủ"),
        BottomNavigationBarItem(
          icon: _unreadCount > 0 
              ? Badge(label: Text('$_unreadCount'), backgroundColor: Colors.red, child: const Icon(Icons.notifications_rounded))
              : const Icon(Icons.notifications_rounded),
          label: "Thông báo"
        ),
        const BottomNavigationBarItem(icon: SizedBox(width: 24, height: 24), label: ""),
        const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: "Trợ lý AI"),
        const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Cá nhân"),
      ],
    );
  }
}

// =======================================================
// 🔥 HOMECONTENT: QUẢN LÝ GIAO DIỆN CHÍNH & TAB ĐIỂM
// =======================================================
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

  // Từ điển Icon SQL -> Flutter
  IconData _getIcon(String code) {
  switch (code) {
    // Thêm icon cho Lịch công tác (Khớp với IconCode 'calendar_today' trong SQL)
    case 'calendar_today': 
      return Icons.calendar_today;
    case 'verified':
       return Icons.verified_user_rounded;
    case 'description_rounded': // 🔥 Thêm case này cho nút VĂN BẢN
      return Icons.description_rounded;  
    case 'card_membership': 
      return Icons.card_membership;
    case 'event_note': 
      return Icons.event_note;
    case 'assignment': 
      return Icons.assignment;
    case 'bar_chart': 
      return Icons.bar_chart;
    case 'schema_rounded': 
      return Icons.schema_rounded;
    case 'grading_rounded': 
      return Icons.grading_rounded;
    case 'account_balance_wallet_rounded': 
      return Icons.account_balance_wallet_rounded;
    case 'health_and_safety_rounded': 
      return Icons.health_and_safety_rounded;
    case 'military_tech_rounded': 
      return Icons.military_tech_rounded;
    case 'card_giftcard_rounded': 
      return Icons.card_giftcard_rounded;
    case 'warning_amber_rounded': 
      return Icons.warning_amber_rounded;
    case 'campaign_rounded': 
      return Icons.campaign_rounded;
    case 'auto_awesome': 
      return Icons.auto_awesome;
    case 'settings': 
      return Icons.settings;
    default: 
      return Icons.widgets_rounded; 
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
          
          if (widget.userRole != 'CanBo') 
            _buildStatisticCard(),

          if (widget.userRole == 'CanBo')
            _buildTeacherBanner(),
          
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
                child: Container(
                  padding: const EdgeInsets.all(2), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  child: CircleAvatar(
                    radius: 26, backgroundColor: Colors.white,
                    backgroundImage: NetworkImage(widget.avatarUrl ?? ""),
                    onBackgroundImageError: (_, __) {},
                  ),
                )
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =======================================================
  // 🔥 BẢNG ĐIỂM DẠNG TAB SIÊU GỌN - HIỂN THỊ THEO TÊN NGÀNH
  // =======================================================
  Widget _buildStatisticCard() {
    const Color premiumBlue = Color(0xFF003366); 
    
    // 1. Kiểm tra nếu chưa có dữ liệu thì hiện vòng quay tải tin
    if (widget.studentProfilesList.isEmpty) {
      return const SizedBox(
        height: 120, 
        child: Center(child: CircularProgressIndicator(strokeWidth: 2))
      );
    }
    
    // 2. Đảm bảo index được chọn không vượt quá danh sách
    if (_selectedTabIndex >= widget.studentProfilesList.length) {
      _selectedTabIndex = 0;
    }

    // 3. Lấy dữ liệu của ngành đang được chọn (Tab hiện tại)
    final current = widget.studentProfilesList[_selectedTabIndex];
    String nganhHoc = current['ten_nganh'] ?? current['lop_hanh_chinh'] ?? "Ngành học";
    String status = current['trang_thai'] ?? "---";
    
    // Đổi màu trạng thái để SV dễ nhận biết
    Color statusColor = status.toLowerCase().contains("tốt nghiệp") ? Colors.green 
                      : status.toLowerCase().contains("bảo lưu") ? Colors.orange 
                      : Colors.blue;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      transform: Matrix4.translationValues(0, -20, 0), // Đẩy thẻ lên trên Header một chút
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: premiumBlue.withOpacity(0.15), width: 1), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06), 
            blurRadius: 15, 
            offset: const Offset(0, 8)
          )
        ]
      ),
      child: Column(
        children: [
          // 🔥 PHẦN 1: THANH TIÊU ĐỀ TABS (Chỉ hiện nếu sinh viên học từ 2 ngành trở lên)
          if (widget.studentProfilesList.length > 1)
            Container(
              height: 38, // Chiều cao mỏng theo ý bạn
              decoration: BoxDecoration(
                color: Colors.grey.shade50, 
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
              ),
              child: Row(
                children: List.generate(widget.studentProfilesList.length, (index) {
                  bool isActive = index == _selectedTabIndex;
                  // Lấy tên ngành hiển thị trên Tab
                  String tabTitle = widget.studentProfilesList[index]['ten_nganh'] ?? 'Ngành ${index + 1}';
                  
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = index),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isActive ? premiumBlue : Colors.transparent, 
                              width: 2.5
                            )
                          )
                        ),
                        child: Text(
                          tabTitle, 
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis, // Nếu tên ngành quá dài thì hiện dấu ...
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500, 
                            color: isActive ? premiumBlue : Colors.grey.shade500
                          )
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          
          // 🔥 PHẦN 2: NỘI DUNG CHI TIẾT (GPA, Tín chỉ, Trạng thái)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // Nếu chỉ có 1 ngành: Hiện tên ngành to làm tiêu đề
                if (widget.studentProfilesList.length == 1) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15), 
                    child: Text(
                      nganhHoc, 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: premiumBlue, fontSize: 14)
                    )
                  ),

                // Hàng thông số điểm
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
                Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
                const SizedBox(height: 12),

                // Trạng thái học tập
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Trạng thái học tập:", 
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1), 
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Text(
                        status.toUpperCase(), 
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, Color c) => Column(
    children: [
      Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c, letterSpacing: -0.5)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
    ]
  );

  Widget _buildTeacherBanner() {
    const Color premiumBlue = Color(0xFF003366); 
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      transform: Matrix4.translationValues(0, -20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: premiumBlue.withOpacity(0.2), width: 1.5), boxShadow: [BoxShadow(color: premiumBlue.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 32)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Cổng thông tin Cán bộ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: premiumBlue)),
            const SizedBox(height: 4),
            Text("Hệ thống quản lý và hỗ trợ đào tạo VinhUni", style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500, height: 1.4)),
          ])),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())),
        child: Container(
          height: 50, padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.blue.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF0054A6), size: 22), 
              const SizedBox(width: 12),
              Expanded(child: Text("Tìm kiếm dịch vụ, thông báo...", style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13))),
              Icon(Icons.mic_none_rounded, color: Colors.blueGrey.shade300, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureGrid() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 5, bottom: 15),
        child: Text("Chức năng chính",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      if (widget.appMenu.isEmpty)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator())),
      if (widget.appMenu.isNotEmpty)
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.9,
          children: widget.appMenu.map((m) {
            // Lưu ý: Đảm bảo các key 'color', 'route', 'icon', 'title' 
            // khớp với dữ liệu từ API của bạn (hoặc ánh xạ từ SQL)
            Color c = Color(int.parse(m['color']));

            return GestureDetector(
              onTap: () {
                final String route = m['route'] ?? '';
                
                switch (route) {
                  // 1. Chuyển sang Tab Chat AI (Dùng Callback)
                  case '/chatscreen':
                    if (widget.onChatTap != null) widget.onChatTap!();
                    break;

                  // 2. Chuyển sang Tab Profile (Dùng Callback)
                  case '/profile':
                    if (widget.onAvatarTap != null) widget.onAvatarTap!();
                    break;

                  // 3. Mở trang Tra cứu VĂN BẢN
                  case '/vanban':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const VanBanScreen()),
                    );
                    break;

                  // 4. Mở trang Chứng chỉ (Màn hình cũ)
                  case '/certificate_page':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CertificatePage(studentId: widget.studentId),
                      ),
                    );
                    break;

                  // 5. Mở trang Lịch công tác
                  case '/lichcongtac':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => StaffScheduleScreen()),
                    );
                    break;

                  // 🔥 7. Mở trang KẾT QUẢ CHỨNG NHẬN (Mới thêm dựa trên SQL của Sơn)
                  // Sửa đoạn này:
                  case '/ket_qua_chung_nhan':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        // 1. Đổi CertificateResultScreen -> ChungChiTraCuuScreen
                        // 2. Đổi studentId -> userMaSV
                        builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId), 
                      ),
                    );
                    break;
                  

                  // 6. Các trường hợp mặc định
                  default:
                    try {
                      Navigator.pushNamed(context, route);
                    } catch (e) {
                      debugPrint("❌ Route không tồn tại: $route");
                    }
                    break;
                }
              },
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    // Đảm bảo hàm _getIcon đã nhận diện mã 'verified' từ SQL
                    child: Icon(_getIcon(m['icon']), size: 30, color: c),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    m['title'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
    ]),
  );
}

  Widget _buildNewsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Text("Khám phá VinhUni", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(
        height: 150, 
        child: ListView(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 20, right: 10), 
          children: [
            _buildNewsCard("Thư viện số", "Tài liệu online", Icons.auto_stories, Colors.blue, "https://thuvien.vinhuni.edu.vn/"),
            _buildNewsCard("Tin tức", "Thông báo mới", Icons.newspaper, Colors.green, "https://vinhuni.edu.vn/"),
            _buildNewsCard("Hotline", "Hỗ trợ SV", Icons.headset_mic, Colors.orange, "tel:02383855452"),
          ]
        ),
      ),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: Colors.white, size: 28),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}