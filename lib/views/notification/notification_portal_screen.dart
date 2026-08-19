import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'send_individual_screen.dart';
import 'send_group_screen.dart'; 
import 'notification_history_screen.dart'; 
import 'automated_notif_screen.dart'; 
// 🔥 QUAN TRỌNG: Đừng quên dòng import này
import 'send_all_school_screen.dart'; 
import '../../core/auth/user_role.dart';

class NotificationPortalScreen extends StatefulWidget {
  const NotificationPortalScreen({super.key});
  @override
  State<NotificationPortalScreen> createState() => _NotificationPortalScreenState();
}

class _NotificationPortalScreenState extends State<NotificationPortalScreen> {
  // ⚠️ Mặc định là quyền THẤP NHẤT. Trước 18/08/2026 mặc định là "canbo",
  // nghĩa là khi chưa đọc được phiên thì sinh viên tạm thời có quyền cán bộ.
  UserRole _userRole = UserRole.sinhVien;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userRole = UserRole.parse(prefs.getString('user_role'));
    });
  }

  // Phân quyền qua lớp chung — xem lib/core/auth/user_role.dart
  bool get _isAdmin => _userRole.isAdmin;
  bool get _isCovan => _userRole == UserRole.coVan;
  bool get _hasHighPrivilege => _userRole.canApproveLeave;

  @override
  Widget build(BuildContext context) {
    const Color vinhUniBlue = Color(0xFF0054A6);

    final bool isAdmin = _userRole.isAdmin;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: vinhUniBlue,
        elevation: 0,
        centerTitle: true,
        // Nút quay lại màu trắng đồng nhất giao diện mới
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), 
          onPressed: () => Navigator.pop(context)
        ),
        title: const Text(
          "TRUNG TÂM THÔNG BÁO", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.9,
          children: [
            // 1. Gửi cá nhân: Tất cả các role cán bộ/admin đều có quyền dùng
            _buildCard(context, "Gửi cá nhân", Icons.person, Colors.orange, const SendIndividualScreen()),
            
            // 2. Gửi nhóm lớp: Dành cho Cán bộ, Giảng viên và Cố vấn
            _buildCard(context, "Gửi nhóm lớp", Icons.groups, Colors.blue, const SendGroupScreen()),
            
            // 3. Lọc Khoa/Khóa: Chỉ hiện cho những người có quyền cao (Cố vấn, Admin)
            if (_hasHighPrivilege)
              _buildCard(context, "Lọc Khoa/Khóa", Icons.domain_rounded, Colors.green, const SendGroupScreen(initialScope: "DEPT_COHORT")),

            // 4. GỬI TOÀN TRƯỜNG: Tính năng tối cao chỉ dành cho Admin hoặc AD
            if (isAdmin)
              _buildCard(context, "Toàn trường", Icons.account_balance_rounded, Colors.purple, const SendAllSchoolScreen()),

            // 5. CẤU HÌNH TỰ ĐỘNG: Cài đặt hệ thống chỉ dành cho Admin hoặc AD
            if (isAdmin)
              _buildCard(context, "Cấu hình", Icons.settings_suggest_rounded, Colors.indigo, const AutomatedNotifScreen()),
            
            // 6. Lịch sử tin: Cho phép mọi cán bộ xem lại lịch sử để theo dõi Watchdog cá nhân
            _buildCard(context, "Lịch sử tin", Icons.history_edu_rounded, Colors.teal, const NotificationHistoryScreen()),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, String title, IconData icon, Color color, Widget target) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1), 
              blurRadius: 10, 
              offset: const Offset(0, 5)
            )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Icon(icon, color: color, size: 32), 
            const SizedBox(height: 10), 
            Text(
              title, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            )
          ]
        ),
      ),
    );
  }
}