import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
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
  
  List<dynamic> generalNotifs = [];   // Tab 1: GENERAL
  List<dynamic> workNotifs = [];      // Tab 2: LICH_CONGTAC, LICH_TUAN
  List<dynamic> reminderNotifs = [];  // Tab 3: CANH_BAO
  List<dynamic> personalNotifs = [];  // Tab 4: DIEM, LICH_HOC, LICH_THI, PERSONAL
  
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    // 🔥 Tăng lên 4 Tab
    _tabController = TabController(length: 4, vsync: this);
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');
      
      if (userId == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final List<dynamic> data = await NotificationService.fetchAndSyncNotifs(userId);
      
      if (mounted) {
        setState(() {
          // 1. Thông báo chung toàn trường
          generalNotifs = data.where((n) => 
            n['LoaiTin']?.toString().toUpperCase() == 'GENERAL').toList();

          // 2. Lịch công tác/Lịch tuần
          workNotifs = data.where((n) => 
            ['LICH_CONGTAC', 'LICH_TUAN'].contains(n['LoaiTin']?.toString().toUpperCase())).toList();

          // 3. Cảnh báo/Nhắc lịch khẩn
          reminderNotifs = data.where((n) => 
            n['LoaiTin']?.toString().toUpperCase() == 'CANH_BAO').toList();

          // 4. Các tin cá nhân còn lại
          personalNotifs = data.where((n) {
            final loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
            return !['GENERAL', 'LICH_CONGTAC', 'LICH_TUAN', 'CANH_BAO'].contains(loai);
          }).toList();

          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi tải thông báo: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Map<String, dynamic> _getNotifStyle(String loai) {
    switch (loai.toUpperCase()) {
      case 'LICH_CONGTAC':
      case 'LICH_TUAN':
        return {'icon': Icons.calendar_today_rounded, 'color': Colors.blue};
      case 'DIEM':
        return {'icon': Icons.assessment_rounded, 'color': Colors.green};
      case 'LICH_THI':
        return {'icon': Icons.assignment_rounded, 'color': Colors.red};
      case 'LICH_HOC':
        return {'icon': Icons.school_rounded, 'color': Colors.teal};
      case 'CANH_BAO':
        return {'icon': Icons.warning_amber_rounded, 'color': Colors.orange};
      case 'GENERAL':
        return {'icon': Icons.campaign_rounded, 'color': vinhUniBlue};
      default:
        return {'icon': Icons.person_rounded, 'color': Colors.amber.shade700};
    }
  }

  // Hàm xử lý xóa vĩnh viễn (Cải tiến để nhận diện đúng danh sách)
  Future<void> _handleDeleteAction(int id, int index, List<dynamic> targetList) async {
    final prefs = await SharedPreferences.getInstance();
    final String? studentId = prefs.getString('user_code') ?? prefs.getString('user_id');

    setState(() => targetList.removeAt(index));
    await DatabaseHelper.instance.softDelete(id);

    if (studentId != null) {
      _syncDeleteToServer(id, studentId);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Đã xóa thông báo"), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _syncDeleteToServer(int notifId, String studentId) async {
    try {
      await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/hide-notif/$notifId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": studentId}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("⚠️ Lỗi đồng bộ xóa: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        title: const Text("Thông báo", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: vinhUniBlue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: vinhUniBlue,
          indicatorWeight: 3,
          isScrollable: true, // Cho phép vuốt ngang các tab nếu màn hình hẹp
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: "VINHUNI"), 
            Tab(text: "CÔNG TÁC"),
            Tab(text: "NHẮC LỊCH"),
            Tab(text: "CÁ NHÂN"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(generalNotifs, "Không có thông báo chung", generalNotifs),
                _buildList(workNotifs, "Chưa có lịch công tác", workNotifs),
                _buildList(reminderNotifs, "Không có nhắc nhở nào", reminderNotifs),
                _buildList(personalNotifs, "Hộp thư cá nhân trống", personalNotifs),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg, List<dynamic> sourceList) {
    if (list.isEmpty && !isLoading) {
      return Center(child: Text(emptyMsg, style: const TextStyle(color: Colors.grey)));
    }
    
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final notif = list[index];
          return Dismissible(
            key: Key(notif['ID'].toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete_sweep, color: Colors.white, size: 28),
            ),
            onDismissed: (direction) => _handleDeleteAction(notif['ID'], index, sourceList),
            child: _buildNotificationCard(notif),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notif) {
    bool isRead = notif['IsRead'] ?? false;
    String loai = notif['LoaiTin']?.toString().toUpperCase() ?? "PERSONAL";
    var style = _getNotifStyle(loai);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChiTietThongBaoScreen(notification: notif)),
        ).then((_) => fetchNotifications());
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
              backgroundColor: style['color'].withOpacity(0.1),
              child: Icon(style['icon'], color: style['color'], size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatLoaiTin(loai), 
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: style['color'])
                      ),
                      Text(notif['NgayPhatHanh'] ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif['TieuDe'] ?? "", 
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, 
                        fontSize: 15, color: Colors.black87
                      ),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text("Người gửi: ${notif['NguoiDang'] ?? 'Hệ thống'}", 
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
                ],
              ),
            ),
            if (!isRead) const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Icon(Icons.circle, color: Colors.red, size: 8),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLoaiTin(String loai) {
    switch(loai) {
      case 'LICH_CONGTAC': return 'Công tác';
      case 'LICH_TUAN': return 'Lịch tuần';
      case 'CANH_BAO': return 'Nhắc lịch';
      case 'DIEM': return 'Điểm số';
      case 'LICH_HOC': return 'Lịch học';
      case 'LICH_THI': return 'Lịch thi';
      case 'GENERAL': return 'Trường';
      default: return 'Cá nhân';
    }
  }
}