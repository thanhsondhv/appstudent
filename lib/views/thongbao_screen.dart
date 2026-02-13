import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'thongbao_chitiet_screen.dart';

class ThongBaoScreen extends StatefulWidget {
  const ThongBaoScreen({super.key});

  @override
  State<ThongBaoScreen> createState() => _ThongBaoScreenState();
}

class _ThongBaoScreenState extends State<ThongBaoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);
  
  List<dynamic> generalNotifs = []; // Tab TỪ VINHUNI
  List<dynamic> personalNotifs = []; // Tab CÁ NHÂN
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');
      if (userId == null) return;

      final response = await http.get(Uri.parse(
          'https://mobi.vinhuni.edu.vn/api/get-notifs/$userId?page=1'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        
        if (mounted) {
          setState(() {
            // --- LOGIC SỬA LỖI: MẶC ĐỊNH LÀ VINHUNI ---
            // Nếu không có trường 'LoaiTin' hoặc không phải là 'PERSONAL' 
            // -> Thì auto cho vào Tab TỪ VINHUNI
            generalNotifs = data.where((n) {
              final type = n['LoaiTin']; 
              return type != 'PERSONAL'; // Chỉ cần khác Personal là lấy hết
            }).toList();

            personalNotifs = data.where((n) => n['LoaiTin'] == 'PERSONAL').toList();
            
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      debugPrint("Lỗi lấy thông báo: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Thông báo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: vinhUniBlue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: vinhUniBlue,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            // --- SỬA TÊN TAB THEO YÊU CẦU ---
            Tab(text: "TỪ VINHUNI"), 
            Tab(text: "CÁ NHÂN"),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(generalNotifs, "Không có thông báo từ trường"),
                _buildList(personalNotifs, "Không có tin nhắn cá nhân"),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg) {
    if (list.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(emptyMsg, style: const TextStyle(color: Colors.grey)),
        ],
      ));
    }
    
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      color: vinhUniBlue,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (context, index) => _buildNotificationCard(list[index]),
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notif) {
    bool isRead = notif['IsRead'] ?? false;
    // Tự động đoán loại tin nếu backend chưa trả về
    bool isGeneral = (notif['LoaiTin'] == 'GENERAL') || (notif['LoaiTin'] == null);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => ChiTietThongBaoScreen(notification: notif)));
        if (!isRead) setState(() => notif['IsRead'] = true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF0F7FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isRead ? Colors.transparent : vinhUniBlue.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: isGeneral ? vinhUniBlue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              child: Icon(
                isGeneral ? Icons.school_rounded : Icons.person_rounded,
                color: isGeneral ? vinhUniBlue : Colors.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(notif['GioDang'] ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (!isRead) const Icon(Icons.circle, color: Colors.red, size: 8),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif['TieuDe'] ?? "", 
                      style: TextStyle(fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, fontSize: 15, color: Colors.black87),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text("Người gửi: ${notif['NguoiDang']}", 
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}