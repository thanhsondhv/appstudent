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
  final Color vinhUniBlue = const Color(0xFF0054A6);

  // --- 1. BIẾN DỮ LIỆU BỘ LỌC ---
  List<dynamic> _rawFilters = [];
  List<String> _years = [];
  List<String> _semesters = [];
  List<String> _weeks = [];

  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedWeek;

  List<dynamic> _schedule = [];
  bool _isLoading = false;
  String _userId = "";

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // =========================================================
  // LOGIC KHỞI TẠO & BỘ LỌC
  // =========================================================

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = (prefs.getString('user_code') ?? "").toUpperCase().replaceAll("CB", "");

      // 1. Tải bộ lọc từ API
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/get-filters/$_userId"));
      if (res.statusCode == 200) {
        _rawFilters = jsonDecode(res.body);

        // 2. Lấy danh sách Năm học
        _years = _rawFilters.map((e) => e['nam'].toString()).toSet().toList()..sort((a, b) => b.compareTo(a));

        if (_years.isNotEmpty) {
          // Ưu tiên chọn năm hiện tại
          _selectedYear = _years.contains("2025-2026") ? "2025-2026" : _years.first;
          _updateSemesterList(_selectedYear!, isInit: true);
        }
      }
    } catch (e) {
      debugPrint("❌ Lỗi khởi tạo: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Khi chọn Năm -> Cập nhật danh sách Kỳ
  void _updateSemesterList(String year, {bool isInit = false}) {
    setState(() {
      _selectedYear = year;
      _semesters = _rawFilters
          .where((e) => e['nam'].toString() == year)
          .map((e) => e['ky'].toString())
          .toSet().toList();

      if (_semesters.isNotEmpty) {
        _selectedSemester = _semesters.first;
        _updateWeekList(year, _selectedSemester!, isInit: isInit);
      }
    });
  }

  // Khi chọn Kỳ -> Cập nhật danh sách Tuần
  void _updateWeekList(String year, String semester, {bool isInit = false}) {
    setState(() {
      _selectedSemester = semester;
      _weeks = _rawFilters
          .where((e) => e['nam'].toString() == year && e['ky'].toString() == semester)
          .map((e) => e['tuan'].toString())
          .toSet().toList();

      // Sắp xếp tuần theo số
      List<int> intWeeks = _weeks.map((e) => int.parse(e)).toList()..sort();
      _weeks = intWeeks.map((e) => e.toString()).toList();

      if (_weeks.isNotEmpty) {
        _selectedWeek = _weeks.first;
      }

      // Sau khi thiết lập xong bộ lọc, tự động fetch TKB
      _fetchTkb();
    });
  }

  // =========================================================
  // GỌI API LẤY LỊCH DẠY
  // =========================================================

  Future<void> _fetchTkb() async {
    if (_selectedYear == null || _selectedSemester == null || _selectedWeek == null) return;

    setState(() => _isLoading = true);
    try {
      final url = "https://mobi.vinhuni.edu.vn/api/lecturer/schedule-v4/CB$_userId"
          "?nam=$_selectedYear"
          "&ky=${Uri.encodeComponent(_selectedSemester!)}"
          "&tuan=$_selectedWeek";

      final res = await http.get(Uri.parse(url));
      final result = jsonDecode(res.body);

      if (result['status'] == 'success') {
        setState(() => _schedule = result['data']);
      } else {
        setState(() => _schedule = []);
      }
    } catch (e) {
      debugPrint("❌ Lỗi Fetch TKB: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // =========================================================
  // GIAO DIỆN
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("TKB GIẢNG VIÊN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        centerTitle: true,
        backgroundColor: vinhUniBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // --- THANH LỌC ĐỘNG ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
            child: Row(
              children: [
                _buildFilterDropdown("Năm học", _selectedYear, _years, (v) => _updateSemesterList(v!)),
                const SizedBox(width: 8),
                _buildFilterDropdown("Học kỳ", _selectedSemester, _semesters, (v) => _updateWeekList(_selectedYear!, v!)),
                const SizedBox(width: 8),
                _buildFilterDropdown("Tuần", _selectedWeek, _weeks, (v) {
                  setState(() => _selectedWeek = v);
                  _fetchTkb();
                }, isWeek: true),
              ],
            ),
          ),

          // --- DANH SÁCH LỊCH DẠY ---
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : _schedule.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _schedule.length,
                        itemBuilder: (context, index) => _buildScheduleCard(_schedule[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String? value, List<String> items, Function(String?) onChanged, {bool isWeek = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: vinhUniBlue, fontWeight: FontWeight.w600),
              items: items.map((s) => DropdownMenuItem(value: s, child: Text(isWeek ? "T. $s" : s, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onChanged,
            ),
          ),
          Container(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("Không có lịch dạy trong tuần này", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> item) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cột Thứ & Tiết
            Container(
              width: 55,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Text("T${item['thu']}", style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text("Tiết ${item['tiet_bd']}", style: TextStyle(fontSize: 10, color: vinhUniBlue.withOpacity(0.8))),
                ],
              ),
            ),
            const SizedBox(width: 15),
            // Nội dung lớp
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['ten_lop'] ?? "Môn học", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.room_outlined, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text("Phòng: ${item['phong']}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(width: 15),
                      const Icon(Icons.schedule_outlined, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text("${item['so_tiet']} tiết", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Thông tin thời gian triển khai
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      "📅 ${item['tu_ngay']} - ${item['den_ngay']}",
                      style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
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