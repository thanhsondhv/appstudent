import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TkbGiangVienScreen extends StatefulWidget {
  const TkbGiangVienScreen({super.key});

  @override
  State<TkbGiangVienScreen> createState() => _TkbGiangVienScreenState();
}

class _TkbGiangVienScreenState extends State<TkbGiangVienScreen> {
  // 1. Khai báo các tham số lọc (Mặc định)
  String selectedYear = "2025-2026";
  String selectedSemester = "Học kỳ 2";
  int selectedWeek = 24;

  List<dynamic> _schedule = [];
  bool _isLoading = false;

  // Danh sách cứng cho bộ lọc (Có thể thay thế bằng API lấy danh mục nếu cần)
  final List<String> years = ["2024-2025", "2025-2026", "2026-2027"];
  final List<String> semesters = ["Học kỳ 1", "Học kỳ 2", "Học kỳ Hè"];

  @override
  void initState() {
    super.initState();
    _fetchTkb();
  }

  // Hàm lấy dữ liệu từ API
  Future<void> _fetchTkb() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String userId = prefs.getString('user_code') ?? "";

      // Gọi API v4 với các tham số động
      final url = "https://mobi.vinhuni.edu.vn/api/lecturer/schedule-v4/$userId"
          "?nam=$selectedYear"
          "&ky=${Uri.encodeComponent(selectedSemester)}"
          "&tuan=$selectedWeek";

      final res = await http.get(Uri.parse(url));
      final result = jsonDecode(res.body);

      if (result['status'] == 'success') {
        setState(() {
          _schedule = result['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _schedule = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi TKB: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "TKB GIẢNG VIÊN",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0054A6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // --- THANH LỌC (FILTER BAR) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                ]),
            child: Row(
              children: [
                _buildFilterItem("Năm học", selectedYear, years, (val) {
                  setState(() => selectedYear = val!);
                  _fetchTkb();
                }),
                const SizedBox(width: 8),
                _buildFilterItem("Học kỳ", selectedSemester, semesters, (val) {
                  setState(() => selectedSemester = val!);
                  _fetchTkb();
                }),
                const SizedBox(width: 8),
                _buildFilterItem("Tuần", selectedWeek.toString(),
                    List.generate(52, (i) => (i + 1).toString()), (val) {
                  setState(() => selectedWeek = int.parse(val!));
                  _fetchTkb();
                }),
              ],
            ),
          ),

          // --- DANH SÁCH LỊCH DẠY ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6)))
                : _schedule.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _schedule.length,
                        itemBuilder: (context, index) {
                          final item = _schedule[index];
                          return _buildScheduleCard(item);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                  icon: const Icon(Icons.home, color: Color(0xFF0054A6)),
                  onPressed: () => Navigator.pop(context)),
              IconButton(icon: const Icon(Icons.person, color: Colors.grey), onPressed: () {}),
            ],
          ),
        ),
      ),
    );
  }

  // Widget xây dựng ô chọn Filter
  Widget _buildFilterItem(String label, String value, List<String> items, Function(String?) onChanged) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: Container(height: 1, color: Colors.grey[300]),
            style: const TextStyle(fontSize: 12, color: Color(0xFF0054A6), fontWeight: FontWeight.w600),
            items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // Widget hiển thị khi không có dữ liệu
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 50, color: Colors.grey[400]),
          const SizedBox(height: 10),
          Text("Không có lịch dạy trong tuần này", style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  // Widget hiển thị từng thẻ lịch dạy (Cập nhật thông tin ngày học)
  Widget _buildScheduleCard(Map<String, dynamic> item) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), 
          side: BorderSide(color: Colors.grey[200]!)
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cột hiển thị Thứ và Tiết
            Container(
              width: 55,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF0054A6).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(8)
              ),
              child: Column(
                children: [
                  Text("T${item['thu']}", 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0054A6), fontSize: 16)),
                  const SizedBox(height: 4),
                  Text("Tiết ${item['tiet_bd']}", 
                      style: const TextStyle(fontSize: 10, color: Color(0xFF0054A6), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 15),
            // Thông tin lớp học
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['ten_lop'], 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.blueAccent),
                      const SizedBox(width: 4),
                      Text("Phòng: ${item['phong']}", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(width: 12),
                      const Icon(Icons.timer_outlined, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text("${item['so_tiet']} tiết", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 🔥 HIỂN THỊ THÔNG TIN NGÀY HỌC (Từ ngày - Đến ngày)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          "${item['tu_ngay']} - ${item['den_ngay']}",
                          style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}