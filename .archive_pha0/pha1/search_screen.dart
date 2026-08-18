import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Color vinhUniBlue = const Color(0xFF0054A6);
  
  Timer? _debounce;
  bool _isLoading = false;
  String _studentId = "";

  // Tách riêng 2 danh sách kết quả
  List<dynamic> _subjectResults = [];
  List<dynamic> _notificationResults = [];

  @override
  void initState() {
    super.initState();
    _loadStudentId();
  }

  Future<void> _loadStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentId = prefs.getString('user_code') ?? "";
    });
  }

  // Lọc chống Spam API
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() { 
        _subjectResults = []; 
        _notificationResults = [];
        _isLoading = false; 
      });
      return;
    }

    // Chờ 500ms sau khi người dùng ngừng gõ mới gọi API
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  // Gọi API tìm kiếm song song cả Môn học và Thông báo
  Future<void> _performSearch(String keyword) async {
    if (_studentId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // ⚠️ ĐÂY LÀ NƠI BẠN GỌI API THẬT TRÊN FASTAPI
      // Ví dụ gọi 2 API song song để tăng tốc độ:
      var subjectRes = http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/search-subject?student_id=$_studentId&keyword=$keyword'));
      var notifRes = http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/search-notification?student_id=$_studentId&keyword=$keyword'));

      var responses = await Future.wait([subjectRes, notifRes]).timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          // Xử lý kết quả Môn học
          if (responses[0].statusCode == 200) {
            _subjectResults = json.decode(utf8.decode(responses[0].bodyBytes))['results'] ?? [];
          }
          // Xử lý kết quả Thông báo
          if (responses[1].statusCode == 200) {
            _notificationResults = json.decode(utf8.decode(responses[1].bodyBytes))['results'] ?? [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi tìm kiếm: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sử dụng DefaultTabController để tạo 2 Tab (Môn học & Thông báo)
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(color: vinhUniBlue),
          titleSpacing: 0,
          title: TextField(
            controller: _searchController,
            autofocus: true, // Tự động bật bàn phím khi mở trang
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: "Tìm môn học, thông báo...",
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            ),
          ),
          actions: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              )
          ],
          bottom: TabBar(
            labelColor: vinhUniBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: vinhUniBlue,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(text: "MÔN HỌC & ĐIỂM"),
              Tab(text: "THÔNG BÁO"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSubjectTab(),
            _buildNotificationTab(),
          ],
        ),
      ),
    );
  }

  // --- GIAO DIỆN TAB MÔN HỌC ---
  Widget _buildSubjectTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_searchController.text.isEmpty) return _buildEmptyState("Nhập từ khóa để tìm môn học...");
    if (_subjectResults.isEmpty) return _buildEmptyState("Không tìm thấy môn học nào.");

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: _subjectResults.length,
      itemBuilder: (context, index) {
        final item = _subjectResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['subject_name'] ?? "Tên môn học", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: vinhUniBlue)),
                const Divider(),
                if (item['schedule'] != null) _buildInfoRow(Icons.calendar_today, Colors.blue, "Lịch học:", item['schedule']),
                if (item['exam_date'] != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.assignment, Colors.orange, "Lịch thi:", "${item['exam_date']} - Phòng: ${item['exam_room'] ?? ''}"),
                ],
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.grade, 
                  item['grade'] != null ? Colors.green : Colors.grey, 
                  "Điểm tổng kết:", 
                  item['grade']?.toString() ?? "Chưa có điểm", 
                  isBold: item['grade'] != null
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- GIAO DIỆN TAB THÔNG BÁO ---
  Widget _buildNotificationTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_searchController.text.isEmpty) return _buildEmptyState("Nhập từ khóa để tìm thông báo...");
    if (_notificationResults.isEmpty) return _buildEmptyState("Không tìm thấy thông báo nào.");

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: _notificationResults.length,
      itemBuilder: (context, index) {
        final item = _notificationResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 1,
          child: ListTile(
            contentPadding: const EdgeInsets.all(15),
            leading: CircleAvatar(
              backgroundColor: Colors.red.shade50,
              child: const Icon(Icons.notifications_active, color: Colors.redAccent),
            ),
            title: Text(item['title'] ?? "Tiêu đề thông báo", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                Text(item['date'] ?? "Ngày gửi", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 5),
                Text(item['content'] ?? "Nội dung...", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ],
            ),
            onTap: () {
              // Xử lý khi nhấn vào thông báo để xem chi tiết
            },
          ),
        );
      },
    );
  }

  // Hàm tiện ích hiển thị text khi trống
  Widget _buildEmptyState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          Text(text, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // Hàm tiện ích hiển thị một dòng thông tin
  Widget _buildInfoRow(IconData icon, Color iconColor, String title, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text("$title ", style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? iconColor : Colors.black87)),
        ),
      ],
    );
  }
}