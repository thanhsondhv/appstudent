// mo_diem_danh_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'live_attendance_screen.dart'; 

class MoDiemDanhScreen extends StatefulWidget {
  final String lecturerId;
  const MoDiemDanhScreen({super.key, required this.lecturerId});
  @override
  State<MoDiemDanhScreen> createState() => _MoDiemDanhScreenState();
}

class _MoDiemDanhScreenState extends State<MoDiemDanhScreen> {
  List<dynamic> _filters = [];
  List<String> _years = [];
  List<String> _semesters = [];
  String? _selectedYear, _selectedSemester, _selectedLhp;
  List<dynamic> _classList = [];
  List _existingSessions = [];
  int? _selectedBuoiId;
  DateTime _selectedDate = DateTime.now();
  bool _isClassLoading = false, _isLoading = false;

  @override
  void initState() { super.initState(); _loadAllFilters(); }

  Future<void> _loadAllFilters() async {
    final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/get-filters/${widget.lecturerId}"));
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      setState(() {
        _filters = data;
        _years = data.map((e) => e['nam'].toString()).toSet().toList()..sort((a, b) => b.compareTo(a));
        _selectedYear = _years.isNotEmpty ? _years[0] : null; // Tự động chọn năm mới nhất
        if (_selectedYear != null) _updateSemesterList(_selectedYear!);
      });
    }
  }

  void _updateSemesterList(String year) {
    setState(() {
      _semesters = _filters.where((e) => e['nam'] == year).map((e) => e['ky'].toString()).toSet().toList();
      _selectedSemester = _semesters.isNotEmpty ? _semesters[0] : null;
      _fetchClasses();
    });
  }

  Future<void> _fetchClasses() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() => _isClassLoading = true);
    final url = "https://mobi.vinhuni.edu.vn/api/lecturer/classes-filtered?lecturer_id=${widget.lecturerId}&nam=$_selectedYear&ky=${Uri.encodeComponent(_selectedSemester!)}";
    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') {
      setState(() {
        _classList = data['data'];
        _selectedLhp = _classList.isNotEmpty ? _classList[0]['ma_lop'] : null;
        if (_selectedLhp != null) _fetchSessions(_selectedLhp!);
      });
    }
    setState(() => _isClassLoading = false);
  }

  Future<void> _fetchSessions(String lhpCode) async {
    final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/sessions-by-class/${Uri.encodeComponent(lhpCode)}"));
    if (res.statusCode == 200) setState(() { 
      _existingSessions = jsonDecode(res.body);
      _selectedBuoiId = _existingSessions.isNotEmpty ? _existingSessions[0]['id'] : null;
    });
  }

  Future<void> _handleCreateNewSession() async {
    if (_selectedLhp == null) return;
    setState(() => _isLoading = true);
    final res = await http.post(Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/create-session"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "lhp_code": _selectedLhp, "lecturer_id": widget.lecturerId,
        "ngay_hoc": "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}",
        "duration": 20, "lat": 18.659, "lon": 105.695,
      }));
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') {
      await _fetchSessions(_selectedLhp!);
      setState(() => _selectedBuoiId = data['buoi_hoc_id']);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Đã tạo buổi mới thành công!")));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("THIẾT LẬP ĐIỂM DANH")),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildLabel("1. Năm học & Học kỳ:"),
        _buildDropdown(_years, _selectedYear, (v) => _updateSemesterList(v!)),
        const SizedBox(height: 10),
        _buildDropdown(_semesters, _selectedSemester, (v) { setState(() => _selectedSemester = v); _fetchClasses(); }),
        const SizedBox(height: 20),
        _buildLabel("2. Lớp học phần:"),
        _isClassLoading ? const LinearProgressIndicator() : _buildDropdown(_classList.map((e) => e['ma_lop'].toString()).toList(), _selectedLhp, (v) { setState(() => _selectedLhp = v); _fetchSessions(v!); }, displayFunc: (id) => _classList.firstWhere((e) => e['ma_lop'] == id)['ten_lop']),
        const SizedBox(height: 20),
        _buildLabel("3. BUỔI HỌC:"),
        Row(children: [
          Expanded(child: _buildDropdown(_existingSessions.map((e) => e['id'].toString()).toList(), _selectedBuoiId?.toString(), (v) => setState(() => _selectedBuoiId = int.parse(v!)), hint: "-- Chọn buổi --", displayFunc: (id) { var item = _existingSessions.firstWhere((e) => e['id'].toString() == id); return "Buổi ${item['buoi']} (${item['ngay']})"; })),
          const SizedBox(width: 10),
          IconButton.filled(onPressed: _isLoading ? null : _handleCreateNewSession, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 20),
        _buildLabel("Thời gian:"),
        _buildDatePicker(),
        const SizedBox(height: 40),
        SizedBox(width: double.infinity, height: 55, child: ElevatedButton.icon(
          onPressed: _selectedBuoiId == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (c) => LiveAttendanceScreen(buoiHocId: _selectedBuoiId!, lhpCode: _selectedLhp!, lecturerId: widget.lecturerId))),
          icon: const Icon(Icons.qr_code_scanner), label: const Text("HIỆN MÃ / QR ĐIỂM DANH"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan.shade400, foregroundColor: Colors.black),
        )),
      ])),
    );
  }

  Widget _buildLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));
  Widget _buildDropdown(List<String> items, String? val, Function(String?) onCh, {String hint = "Chọn...", String Function(String)? displayFunc}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), margin: const EdgeInsets.only(bottom: 5), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, hint: Text(hint), value: items.contains(val) ? val : null, items: items.map((e) => DropdownMenuItem(value: e, child: Text(displayFunc != null ? displayFunc(e) : e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(), onChanged: onCh)));
  Widget _buildDatePicker() => InkWell(onTap: () async { final p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030)); if (p != null) setState(() => _selectedDate = p); }, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"), const Icon(Icons.calendar_month)])));
}