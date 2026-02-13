import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Import các màn hình chức năng
// Đảm bảo đường dẫn import đúng với dự án của bạn
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
  final Color vinhUniBlue = const Color(0xFF0054A6);
  int _currentIndex = 0;
  bool _hasUnread = false;
  
  // --- KHAI BÁO BIẾN Ở ĐÂY LÀ ĐÚNG (Trong State) ---
  String studentName = "Sinh viên";
  String studentId = ""; 

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _checkUnreadNotifications();
  }

  Future<void> _loadStudentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        studentName = prefs.getString('full_name') ??
            prefs.getString('user_name') ??
            prefs.getString('user_id') ?? "Sinh viên";
            
        // Lấy ID sinh viên để load ảnh Avatar
        studentId = prefs.getString('user_id') ?? ""; 
      });
    }
  }

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
      debugPrint("Lỗi check badge: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Danh sách màn hình
    final List<Widget> screens = [
      // Truyền studentId xuống HomeContent
      HomeContent(studentName: studentName, studentId: studentId),
      const ThongBaoScreen(),
      const ChatScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: vinhUniBlue,
          unselectedItemColor: Colors.grey[400],
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 1) {
              setState(() => _hasUnread = false);
            } else {
              _checkUnreadNotifications();
            }
          },
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Trang chủ"),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_rounded),
                  if (_hasUnread)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    )
                ],
              ),
              label: "Thông báo",
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.smart_toy_rounded), label: "Trợ lý AI"),
            const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Cá nhân"),
          ],
        ),
      ),
    );
  }
}

// === GIAO DIỆN HOME CONTENT (Header cong + Avatar) ===
class HomeContent extends StatelessWidget {
  final String studentName;
  final String studentId; // Nhận biến ID từ State

  const HomeContent({
    super.key, 
    required this.studentName, 
    required this.studentId
  });

  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          _buildFeatureGrid(context),
          const SizedBox(height: 25),
          _buildNewsSection(),
          const SizedBox(height: 100), 
        ],
      ),
    );
  }

  // 1. HEADER CONG + AVATAR (Đã sửa logic ảnh)
  Widget _buildHeader(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [vinhUniBlue, const Color(0xFF0078D4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(color: vinhUniBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Xin chào,", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                            studentName.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // --- AVATAR ---
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white,
                        // ✅ SỬA LỖI TẠI ĐÂY: Chỉ gán ảnh khi studentId có dữ liệu
                        backgroundImage: (studentId.isNotEmpty) 
                            ? NetworkImage('https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId')
                            : null,
                        
                        // ✅ SỬA LỖI TẠI ĐÂY: Hàm xử lý lỗi cũng phải là null nếu không có ảnh
                        onBackgroundImageError: (studentId.isNotEmpty) 
                            ? (exception, stackTrace) {
                                debugPrint("Lỗi tải ảnh avatar: $exception");
                              }
                            : null,

                        // ✅ HIỂN THỊ ICON MẶC ĐỊNH: Nếu không có ID hoặc khi đang đợi tải ảnh
                        child: (studentId.isEmpty) 
                            ? const Icon(Icons.person, color: Colors.grey, size: 30) 
                            : null,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Học kỳ 2 năm học 2025-2026 đã bắt đầu!",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.7), size: 14),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 2. GRID CHỨC NĂNG
  Widget _buildFeatureGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Tiện ích sinh viên", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildFeatureItem(context, "Lịch học", Icons.calendar_month_rounded, const Color(0xFFE3F2FD), const Color(0xFF1976D2), 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ThoiKhoaBieuScreen()))),
              _buildFeatureItem(context, "Lịch thi", Icons.assignment_late_rounded, const Color(0xFFFFF3E0), const Color(0xFFF57C00), 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LichThiScreen()))),
              _buildFeatureItem(context, "Kết quả", Icons.pie_chart_rounded, const Color(0xFFE8F5E9), const Color(0xFF388E3C), 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DiemThiScreen()))),
              _buildFeatureItem(context, "Học phí", Icons.account_balance_wallet_rounded, const Color(0xFFF3E5F5), const Color(0xFF7B1FA2), 
                  () => _showComingSoon(context)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _buildFeatureItem(context, "Dịch vụ", Icons.dataset_linked_outlined, const Color(0xFFFFEBEE), const Color(0xFFD32F2F), 
                  () => _showComingSoon(context)),
              const SizedBox(width: 25),
              _buildFeatureItem(context, "Khảo sát", Icons.poll_rounded, const Color(0xFFE0F7FA), const Color(0xFF0097A7), 
                  () => _showComingSoon(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(BuildContext context, String title, IconData icon, Color bg, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60, width: 60,
            decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: bg.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  // 3. TIN TỨC / KHÁM PHÁ (Giao diện Magazine Pro)
  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Khám phá VinhUni", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                  SizedBox(height: 4),
                  Text("Tin tức & Hoạt động nổi bật", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              Text("Xem tất cả", style: TextStyle(fontSize: 12, color: vinhUniBlue, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 180,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 20, right: 10),
            children: [
              _buildModernNewsCard("Thư viện số", "Truy cập hàng ngàn giáo trình online miễn phí.", Icons.auto_stories_rounded, [const Color(0xFF0054A6), const Color(0xFF009688)]),
              _buildModernNewsCard("Ký túc xá", "Đăng ký phòng & thanh toán trực tuyến.", Icons.apartment_rounded, [const Color(0xFFFF512F), const Color(0xFFDD2476)]),
              _buildModernNewsCard("CLB Sinh viên", "Tham gia 50+ CLB năng động tại trường.", Icons.groups_3_rounded, [const Color(0xFF4776E6), const Color(0xFF8E54E9)]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernNewsCard(String title, String subtitle, IconData icon, List<Color> gradientColors) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 15, bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: gradientColors[0].withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(right: -20, top: -20, child: Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle))),
            Positioned(right: -40, bottom: -40, child: Container(width: 150, height: 150, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.3))),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tính năng đang phát triển")));
  }
}