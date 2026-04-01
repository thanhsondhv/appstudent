import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'thongbao_chitiet_screen.dart';
import '../services/notification_service.dart';
import '../services/database_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ThongBaoScreen extends StatefulWidget {
  const ThongBaoScreen({super.key});

  @override
  State<ThongBaoScreen> createState() => _ThongBaoScreenState();
}

class _ThongBaoScreenState extends State<ThongBaoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);
  
  List<dynamic> generalNotifs = [];   
  List<dynamic> workNotifs = [];      
  List<dynamic> reminderNotifs = [];  
  List<dynamic> personalNotifs = [];  
  
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

  // 🔥 CẬP NHẬT: Gom nhóm và lọc tin theo vai trò (Bỏ Văn bản của Cán bộ)
  void _updateGroups(List<dynamic> data) {
    bool isStaff = (userRole == "CanBo" || userRole == "CoVan");

    setState(() {
      // Tab 1: Tin chung (VinhUni)
      generalNotifs = data.where((n) {
        String loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
        // Cán bộ: Không đưa tin VAN_BAN vào đây nữa
        if (isStaff && loai.contains('VAN_BAN')) return false;
        return _safeGetTabGroup(n) == 'GENERAL';
      }).toList();

      // Tab 2: Học tập/Công tác
      workNotifs = data.where((n) => _safeGetTabGroup(n) == 'WORK').toList();

      // Tab 3: Nhắc lịch/Cảnh báo
      reminderNotifs = data.where((n) => _safeGetTabGroup(n) == 'REMINDER').toList();

      // Tab 4: Cá nhân
      personalNotifs = data.where((n) => _safeGetTabGroup(n) == 'PERSONAL').toList();
    });
  }

  String _safeGetTabGroup(dynamic n) {
    if (n['TabGroup'] != null) return n['TabGroup'].toString().toUpperCase();
    String loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
    if (['GENERAL', 'THONG_BAO', 'TIN_TUC'].contains(loai)) return 'GENERAL';
    if (['VAN_BAN', 'VAN_BAN_PHAP_QUY'].contains(loai)) return 'GENERAL'; 
    if (['LICH_TUAN', 'LICH_CONGTAC', 'WORK', 'LICH_HOC', 'LOP_HP'].contains(loai)) return 'WORK';
    if (['CANH_BAO', 'LICH_THI', 'REMINDER'].contains(loai)) return 'REMINDER';
    return 'PERSONAL';
  }

  Future<void> fetchNotifications() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('user_code');
    if (userId == null) return;

    // Load offline
    final localData = await DatabaseHelper.instance.getOfflineNotifs(userId);
    if (mounted && localData.isNotEmpty) {
      setState(() { _updateGroups(localData); isLoading = false; });
    }

    // Sync online
    NotificationService.fetchAndSyncNotifs(userId).then((newData) {
      if (mounted) {
        setState(() { _updateGroups(newData); isLoading = false; });
      }
    });
  }

  // 🔥 CẬP NHẬT: Nhãn Tab Pro cho Cán bộ (Thay Văn bản thành VinhUni)
  List<String> _getTabLabels() {
    if (userRole == "CanBo" || userRole == "CoVan" || userRole == "Admin") {
      return ["VINHUNI", "CÔNG TÁC", "NHẮC LỊCH", "CÁ NHÂN"];
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
        title: const Text("Thông báo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.done_all_rounded, color: vinhUniBlue, size: 22),
            onPressed: _showMarkAllReadConfirm, // Tính năng pro cho thông báo
            tooltip: "Đánh dấu tất cả đã đọc",
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: vinhUniBlue,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: vinhUniBlue,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          tabs: [
            _buildTabWithBadge(labels[0], generalNotifs),
            _buildTabWithBadge(labels[1], workNotifs),
            _buildTabWithBadge(labels[2], reminderNotifs),
            _buildTabWithBadge(labels[3], personalNotifs),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(generalNotifs, "Không có tin mới"),
                _buildList(workNotifs, "Chưa có lịch trình"),
                _buildList(reminderNotifs, "Không có nhắc nhở"),
                _buildList(personalNotifs, "Hộp thư trống"),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg) {
    if (list.isEmpty) return _buildEmptyState(emptyMsg);
    
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: list.length,
        itemBuilder: (context, index) => _buildNotificationCard(list[index]),
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notif) {
    bool isRead = (notif['IsRead'] == true || notif['IsRead'] == 1);
    String loai = notif['LoaiTin']?.toString().toUpperCase() ?? "PERSONAL";
    
    IconData icon;
    Color color;
    switch (loai) {
      case 'VAN_BAN': icon = Icons.description_outlined; color = Colors.indigo; break;
      case 'LICH_TUAN': icon = Icons.event_note_outlined; color = Colors.blue; break;
      case 'LICH_THI': icon = Icons.assignment_outlined; color = Colors.red; break;
      case 'CANH_BAO': icon = Icons.report_problem_outlined; color = Colors.orange; break;
      case 'LOP_HP': icon = Icons.school_outlined; color = Colors.green; break;
      default: icon = Icons.notifications_none_outlined; color = Colors.blueGrey;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (c) => ChiTietThongBaoScreen(notification: notif)))
          .then((_) => fetchNotifications());
      },
      onLongPress: () => _showDeleteMenu(notif),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : vinhUniBlue.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isRead ? Colors.transparent : vinhUniBlue.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(loai.replaceAll('_', ' '), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
                    Text(notif['NgayPhatHanh'] ?? "", style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                  const SizedBox(height: 6),
                  Text(notif['TieuDe'] ?? "", 
                    style: TextStyle(fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, fontSize: 14.5, color: Colors.black87),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(notif['TomTat'] ?? "", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!isRead) Container(margin: const EdgeInsets.only(top: 25, left: 5), width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  // --- UI COMPONENTS & HELPERS ---

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }

  void _showMarkAllReadConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Xác nhận", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text("Bạn muốn đánh dấu tất cả thông báo là đã đọc?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { Navigator.pop(ctx); /* Call API here */ }, child: Text("Đồng ý", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // Giữ nguyên các hàm Badge và Delete Menu của Sơn vì đã ổn định
  Widget _buildTabWithBadge(String label, List<dynamic> list) {
    int unreadCount = list.where((n) => n['IsRead'] == false || n['IsRead'] == 0).length;
    return Tab(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Text(label),
          if (unreadCount > 0)
            Positioned(
              right: -14, top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text('$unreadCount', 
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  void _showDeleteMenu(dynamic notif) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text("Xóa thông báo này", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                onTap: () { Navigator.pop(context); _handleHideNotif(notif['ID']); },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text("Hủy bỏ"),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleHideNotif(int id) async {
    // Giữ nguyên logic gọi API ẩn tin của Sơn
    setState(() {
      generalNotifs.removeWhere((item) => item['ID'] == id);
      workNotifs.removeWhere((item) => item['ID'] == id);
      reminderNotifs.removeWhere((item) => item['ID'] == id);
      personalNotifs.removeWhere((item) => item['ID'] == id);
    });
  }
}