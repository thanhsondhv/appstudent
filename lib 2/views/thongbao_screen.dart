//thongbao_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'thongbao_chitiet_screen.dart';
import '../services/notification_service.dart';
import '../services/database_helper.dart';
class ThongBaoScreen extends StatefulWidget {
  const ThongBaoScreen({super.key});

  @override
  State<ThongBaoScreen> createState() => _ThongBaoScreenState();
}

class _ThongBaoScreenState extends State<ThongBaoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);
  
  // Các danh sách tin theo nhóm quy hoạch
  List<dynamic> generalNotifs = [];   // Tab 1: VINHUNI / VĂN BẢN
  List<dynamic> workNotifs = [];      // Tab 2: HỌC TẬP / CÔNG TÁC
  List<dynamic> reminderNotifs = [];  // Tab 3: NHẮC LỊCH
  List<dynamic> personalNotifs = [];  // Tab 4: CÁ NHÂN
  
  bool isLoading = true;
  String userRole = "SinhVien"; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initRoleAndFetch();
  }

  Future<void> _initRoleAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userRole = prefs.getString('user_role') ?? "SinhVien";
      });
      fetchNotifications();
    }
  }

  // 🔥 HÀM PHÒNG THỦ: Đảm bảo phân loại đúng kể cả khi SQLite chưa cập nhật cột TabGroup
  String _safeGetTabGroup(dynamic n) {
  if (n['TabGroup'] != null) return n['TabGroup'].toString().toUpperCase();

  String loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
  
  // 🔥 ÉP VĂN BẢN PHÁP QUY VÀO TAB 1 (GENERAL)
  if (['GENERAL', 'THONG_BAO', 'VAN_BAN_PHAP_QUY', 'VAN_BAN'].contains(loai)) {
    return 'GENERAL';
  }
  
  if (['LICH_TUAN', 'LICH_CONGTAC', 'WORK', 'LICH_HOC'].contains(loai)) return 'WORK';
  if (['CANH_BAO', 'LICH_THI'].contains(loai)) return 'REMINDER';
  return 'PERSONAL';
}

  Future<void> fetchNotifications() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('user_code');

    if (userId == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    // 1. Lấy offline trước
    final localData = await DatabaseHelper.instance.getOfflineNotifs(userId);
    if (mounted) {
      setState(() {
        _updateGroups(localData);
        if (localData.isNotEmpty) isLoading = false;
      });
    }

    // 2. Đồng bộ mạng
    NotificationService.fetchAndSyncNotifs(userId).then((newData) {
      if (mounted) {
        setState(() {
          _updateGroups(newData);
          isLoading = false;
        });
      }
    });
  }

// Hàm phụ để tách logic lọc cho sạch code
void _updateGroups(List<dynamic> data) {
  generalNotifs = data.where((n) => _safeGetTabGroup(n) == 'GENERAL').toList();
  workNotifs = data.where((n) => _safeGetTabGroup(n) == 'WORK').toList();
  reminderNotifs = data.where((n) => _safeGetTabGroup(n) == 'REMINDER').toList();
  personalNotifs = data.where((n) => _safeGetTabGroup(n) == 'PERSONAL').toList();
}

  // Trả về nhãn Tab phù hợp với vai trò người dùng
  List<String> _getTabLabels() {
    if (userRole == "CanBo" || userRole == "GiangVien") {
      return ["VĂN BẢN", "CÔNG TÁC", "NHẮC LỊCH", "CÁ NHÂN"];
    } else {
      return ["VINHUNI", "HỌC TẬP", "NHẮC LỊCH", "CÁ NHÂN"];
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _getTabLabels();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        title: const Text("Thông báo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: vinhUniBlue,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: vinhUniBlue,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
          tabs: [
            _buildTabWithBadge(labels[0], generalNotifs),
            _buildTabWithBadge(labels[1], workNotifs),
            _buildTabWithBadge(labels[2], reminderNotifs),
            _buildTabWithBadge(labels[3], personalNotifs),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(generalNotifs, "Không có tin mới", generalNotifs),
                _buildList(workNotifs, "Chưa có lịch trình", workNotifs),
                _buildList(reminderNotifs, "Không có nhắc nhở", reminderNotifs),
                _buildList(personalNotifs, "Hộp thư trống", personalNotifs),
              ],
            ),
    );
  }

  Widget _buildTabWithBadge(String label, List<dynamic> list) {
    // Đếm số tin chưa đọc trong danh sách
    int unreadCount = list.where((n) => n['IsRead'] == false || n['IsRead'] == 0).length;
    
    return Tab(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Text(label),
          if (unreadCount > 0)
            Positioned(
              right: -12, top: -5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text('$unreadCount', 
                  style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg, List<dynamic> sourceList) {
    if (list.isEmpty) return Center(child: Text(emptyMsg, style: const TextStyle(color: Colors.grey, fontSize: 13)));
    
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return _buildNotificationCard(list[index]);
        },
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notif) {
    // Xử lý trạng thái đã đọc từ cả boolean (Server) và integer (SQLite)
    bool isRead = (notif['IsRead'] == true || notif['IsRead'] == 1);
    String loai = notif['LoaiTin']?.toString().toUpperCase() ?? "PERSONAL";
    
    IconData icon;
    Color color;
    switch (loai) {
      case 'VAN_BAN': icon = Icons.description_rounded; color = Colors.indigo; break;
      case 'LICH_TUAN': icon = Icons.calendar_view_week_rounded; color = Colors.blue; break;
      case 'LICH_THI': icon = Icons.assignment_late_rounded; color = Colors.red; break;
      case 'CANH_BAO': icon = Icons.warning_amber_rounded; color = Colors.orange; break;
      case 'GENERAL': icon = Icons.campaign_rounded; color = vinhUniBlue; break;
      default: icon = Icons.notifications_none_rounded; color = Colors.blueGrey;
    }

    return GestureDetector(
      onTap: () {
        
        Navigator.push(context, MaterialPageRoute(builder: (c) => ChiTietThongBaoScreen(notification: notif)))
          .then((_) => fetchNotifications());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF0F7FF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: isRead ? Border.all(color: Colors.grey.shade100) : Border.all(color: vinhUniBlue.withOpacity(0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1), 
              radius: 20,
              child: Icon(icon, color: color, size: 20)
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(loai.replaceAll('_', ' '), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                    Text(notif['NgayPhatHanh'] ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 5),
                  Text(notif['TieuDe'] ?? "", 
                    style: TextStyle(fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, fontSize: 14, color: Colors.black87),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(notif['TomTat'] ?? "", style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!isRead) const Padding(padding: EdgeInsets.only(top: 20), child: Icon(Icons.circle, color: Colors.red, size: 8)),
          ],
        ),
      ),
    );
  }
}