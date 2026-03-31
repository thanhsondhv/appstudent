import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'send_individual_screen.dart';
import 'send_group_screen.dart'; 
import 'notification_history_screen.dart'; 
import 'automated_notif_screen.dart'; 
// 🔥 QUAN TRỌNG: Đừng quên dòng import này
import 'send_all_school_screen.dart'; 

class NotificationPortalScreen extends StatefulWidget {
  const NotificationPortalScreen({super.key});
  @override
  State<NotificationPortalScreen> createState() => _NotificationPortalScreenState();
}

class _NotificationPortalScreenState extends State<NotificationPortalScreen> {
  String _userRole = "canbo";

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { 
      _userRole = (prefs.getString('user_role') ?? "canbo").toLowerCase(); 
    });
  }

  bool get _hasHighPrivilege => _userRole == 'admin' || _userRole == 'covan' || _userRole == 'CoVan' || _userRole == 'Admin';

  @override
  Widget build(BuildContext context) {
    const Color vinhUniBlue = Color(0xFF0054A6);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: vinhUniBlue, elevation: 0, centerTitle: true,
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
          crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.9,
          children: [
            // 1. Gửi cá nhân
            _buildCard(context, "Gửi cá nhân", Icons.person, Colors.orange, SendIndividualScreen()),
            
            // 2. Gửi nhóm lớp
            _buildCard(context, "Gửi nhóm lớp", Icons.groups, Colors.blue, SendGroupScreen()),
            
            // 3. Lọc Khoa/Khóa (Admin, Cố vấn, AD)
            if (_hasHighPrivilege)
              _buildCard(context, "Lọc Khoa/Khóa", Icons.domain_rounded, Colors.green, SendGroupScreen(initialScope: "DEPT_COHORT")),

            // 🔥 4. NÚT TOÀN TRƯỜNG (Admin mới có) - Sơn thêm lại đoạn này nhé
            if (_userRole == 'admin' || _userRole == 'ad')
              _buildCard(context, "Toàn trường", Icons.account_balance_rounded, Colors.purple, SendAllSchoolScreen()),

            // 5. CẤU HÌNH TỰ ĐỘNG (Admin/AD mới có)
            if (_userRole == 'admin' || _userRole == 'ad')
              _buildCard(context, "Cấu hình", Icons.settings_suggest_rounded, Colors.indigo, AutomatedNotifScreen()),
            
            // 6. Lịch sử tin
            _buildCard(context, "Lịch sử tin", Icons.history_edu_rounded, Colors.teal, NotificationHistoryScreen()),
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