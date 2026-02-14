import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Import các màn hình chức năng (Đảm bảo các file này tồn tại trong project của bạn)
import 'chat_screen.dart';
import 'thongbao_screen.dart';
import 'profile_screen.dart';
import 'thoikhoabieu_screen.dart';
import 'diemthi_screen.dart';
import 'lichthi_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Cấu hình màu sắc VinhUni rực rỡ
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color activeColor = const Color(0xFF0078D4);
  final Color inactiveColor = const Color(0xFF94A3B8);

  int _currentIndex = 0;
  bool _hasUnread = false;
  String studentName = "Đang tải...";
  String studentId = "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _checkUnreadNotifications();
  }

  // 1. Tải thông tin sinh viên từ SharedPreferences
  Future<void> _loadStudentInfo() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      studentId = prefs.getString('user_id') ?? "";
      // Lấy từ khóa 'full_name' mà chúng ta đã thống nhất lưu ở trên
      studentName = prefs.getString('full_name') ?? "Sinh viên";
    });
  }
}

  // 2. Kiểm tra thông báo chưa đọc từ API
  Future<void> _checkUnreadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');
      if (userId == null) return;

      final response = await http.get(Uri.parse(
          'https://mobi.vinhuni.edu.vn/api/get-notifs/$userId?page=1'));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        bool unread = data.any((notif) => notif['IsRead'] == false);
        if (mounted) setState(() => _hasUnread = unread);
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi check badge: $e");
    }
  }

  // 3. Xử lý Đăng xuất
  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    // Danh sách màn hình cho BottomBar
    final List<Widget> screens = [
      HomeContent(
        studentName: studentName,
        studentId: studentId,
        onAvatarTap: () => setState(() => _currentIndex = 3),
      ),
      const ThongBaoScreen(),
      const ChatScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      
      // ✅ MENU 3 GẠCH (DRAWER)
      drawer: _buildModernDrawer(context),

      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      // ✅ BOTTOM BAR THIẾT KẾ MỚI
      bottomNavigationBar: _buildModernBottomBar(),
    );
  }

  Widget _buildModernBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          selectedItemColor: activeColor,
          unselectedItemColor: inactiveColor,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          onTap: (index) {
            if (index == 4) {
              _scaffoldKey.currentState?.openDrawer();
            } else {
              setState(() => _currentIndex = index);
              if (index == 1) setState(() => _hasUnread = false);
            }
          },
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: "Trang chủ"),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.notifications_active_rounded),
                  if (_hasUnread)
                    Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
                ],
              ),
              label: "Thông báo",
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.smart_toy_rounded), label: "Trợ lý AI"),
            const BottomNavigationBarItem(icon: Icon(Icons.account_circle_rounded), label: "Cá nhân"),
            const BottomNavigationBarItem(icon: Icon(Icons.menu_open_rounded), label: "Menu"),
          ],
        ),
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context) {
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
                  backgroundImage: (studentId.isNotEmpty) ? NetworkImage('https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId') : null,
                  child: studentId.isEmpty ? const Icon(Icons.person, size: 35) : null,
                ),
                const SizedBox(height: 12),
                Text(studentName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("Mã SV: $studentId", style: TextStyle(color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
          _buildDrawerItem(Icons.person_outline, "Thông tin chi tiết", () { Navigator.pop(context); setState(() => _currentIndex = 3); }),
          _buildDrawerItem(Icons.lock_outline, "Đổi mật khẩu", () => Navigator.pop(context)),
          const Spacer(),
          const Divider(),
          _buildDrawerItem(Icons.logout, "Đăng xuất", () => _logout(context), color: Colors.red),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(leading: Icon(icon, color: color ?? vinhUniBlue), title: Text(title, style: TextStyle(color: color)), onTap: onTap);
  }
}

// === WIDGET NỘI DUNG TRANG CHỦ ===
class HomeContent extends StatelessWidget {
  final String studentName;
  final String studentId;
  final VoidCallback? onAvatarTap;

  const HomeContent({super.key, required this.studentName, required this.studentId, this.onAvatarTap});

  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // ✅ FIX LỖI KHUẤT: Tạo khoảng trống 120px dưới cùng
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        children: [
          _buildHeader(context),
          _buildStatisticCard(),
          const SizedBox(height: 10),
          _buildFeatureGrid(context),
          const SizedBox(height: 25),
          _buildNewsSection(),
        ],
      ),
    );
  }

  // 1. Header màu xanh với Avatar nhấn được
  Widget _buildHeader(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [vinhUniBlue, const Color(0xFF0078D4)]),
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Xin chào,", style: TextStyle(color: Colors.white70, fontSize: 14)),
                      Text(studentName.toUpperCase(), 
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onAvatarTap,
                  child: CircleAvatar(
                    radius: 26, backgroundColor: Colors.white,
                    backgroundImage: (studentId.isNotEmpty) ? NetworkImage('https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId') : null,
                    child: studentId.isEmpty ? const Icon(Icons.person) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 2. Thẻ thống kê (Hồ sơ, Đang xét, Đã đạt)
  Widget _buildStatisticCard() {
    return Transform.translate(
      offset: const Offset(0, -30),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(Icons.article_outlined, "0", "Thông báo mới", Colors.green),
            _buildStatItem(Icons.pending_actions, "0", "Số môn có điểm", Colors.orange),
            _buildStatItem(Icons.task_alt, "0", "Số dư TK", Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String val, String label, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(height: 5),
      Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  // 3. Lưới tính năng (8 Icon)
  Widget _buildFeatureGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Chức năng chính", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4, mainAxisSpacing: 20, crossAxisSpacing: 10, childAspectRatio: 0.85,
            children: [
              _buildFeatureItem(context, "Lịch học", Icons.event_note, Colors.blue, const ThoiKhoaBieuScreen()),
              _buildFeatureItem(context, "Lịch thi", Icons.assignment, Colors.orange, const LichThiScreen()),
              _buildFeatureItem(context, "Kết quả", Icons.bar_chart, Colors.green, const DiemThiScreen()),
              _buildFeatureItem(context, "Học phí", Icons.account_balance_wallet, Colors.purple, null),
              _buildFeatureItem(context, "Dịch vụ", Icons.apps, Colors.red, null),
              _buildFeatureItem(context, "Khảo sát", Icons.thumbs_up_down, Colors.teal, null),
              _buildFeatureItem(context, "Tra cứu", Icons.search, Colors.indigo, null),
              _buildFeatureItem(context, "Liên hệ", Icons.contact_support, Colors.pink, null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(BuildContext context, String title, IconData icon, Color color, Widget? target) {
    return GestureDetector(
      onTap: () => target != null ? Navigator.push(context, MaterialPageRoute(builder: (_) => target)) : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
      ]),
    );
  }

  // 4. Mục Tin tức nổi bật
  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text("Khám phá VinhUni", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 160,
          child: ListView(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 20, right: 10),
            children: [
              _buildNewsCard("Thư viện số", "Truy cập tài liệu online", Icons.auto_stories, Colors.blue),
              _buildNewsCard("Ký túc xá", "Đăng ký chỗ ở trực tuyến", Icons.apartment, Colors.pink),
              _buildNewsCard("Hoạt động", "Các CLB đang tuyển quân", Icons.groups, Colors.orange),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewsCard(String title, String desc, IconData icon, Color color) {
    return Container(
      width: 240, margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ],
      ),
    );
  }
}