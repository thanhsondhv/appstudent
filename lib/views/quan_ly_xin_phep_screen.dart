import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; 

class QuanLyXinPhepScreen extends StatefulWidget {
  final String studentId;
  const QuanLyXinPhepScreen({super.key, required this.studentId});

  @override
  State<QuanLyXinPhepScreen> createState() => _QuanLyXinPhepScreenState();
}

class _QuanLyXinPhepScreenState extends State<QuanLyXinPhepScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  // --- Form State ---
  String? _selectedYear;
  String? _selectedSemester;
  DateTime _selectedDate = DateTime.now();
  String? _selectedLhpId;
  String _selectedCategory = 'VANG_HOC';
  final TextEditingController _reasonController = TextEditingController();
  
  // Trạng thái Loading
  bool _isSubmitting = false;
  bool _isLoadingClasses = false;
  List<dynamic> _classList = [];

  // Dữ liệu Năm học & Học kỳ
  final List<String> _years = [];
  final List<String> _semesters = ["Học kỳ 1", "Học kỳ 2", "Học kỳ Hè"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateYears();
    
    // Mặc định năm hiện tại và kỳ hiện tại
    _selectedYear = _years.first; 
    _selectedSemester = _semesters[1]; // Mặc định HK2
    
    // 🔥 Gọi lấy danh sách lớp lần đầu
    _fetchClasses();
  }

  void _generateYears() {
    int currentYear = DateTime.now().year;
    for (int i = 0; i < 3; i++) {
      _years.add("${currentYear - i - 1}-${currentYear - i}");
    }
  }

  // 🔥 HÀM LẤY DANH SÁCH LỚP THEO NĂM/KỲ
  Future<void> _fetchClasses() async {
    setState(() {
      _isLoadingClasses = true;
      _selectedLhpId = null; // Reset lớp đã chọn khi lọc lại
    });

    try {
      // Gửi kèm tham số lọc year và semester lên Backend
      final String url = "https://mobi.vinhuni.edu.vn/api/student/my-classes/${widget.studentId}"
          "?year=$_selectedYear&semester=$_selectedSemester";
          
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() {
          _classList = jsonDecode(res.body);
        });
      }
    } catch (e) {
      debugPrint("Lỗi fetch lớp: $e");
    } finally {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: vinhUniBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("QUẢN LÝ NGHỈ HỌC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "TẠO ĐƠN MỚI"),
            Tab(text: "LỊCH SỬ GỬI"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewRequestTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildNewRequestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row Năm học & Học kỳ
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Năm học"),
                    _buildDropdownContainer(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _selectedYear,
                        items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) {
                          setState(() => _selectedYear = v);
                          _fetchClasses(); // 🔥 Lọc lại lớp
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Học kỳ"),
                    _buildDropdownContainer(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _selectedSemester,
                        items: _semesters.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) {
                          setState(() => _selectedSemester = v);
                          _fetchClasses(); // 🔥 Lọc lại lớp
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _buildLabel("1. Ngày xin vắng học"),
          InkWell(
            onTap: () => _selectDate(context),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('dd/MM/yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  Icon(Icons.calendar_today_rounded, color: vinhUniBlue, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildLabel("2. Chọn lớp học phần"),
          _buildDropdownContainer(
            child: _isLoadingClasses 
              ? const SizedBox(height: 20, width: 20, child: LinearProgressIndicator()) 
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Bấm để chọn lớp..."),
                    value: _selectedLhpId,
                    items: _classList.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'], style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) => setState(() => _selectedLhpId = v),
                  ),
                ),
          ),
          const SizedBox(height: 20),

          _buildLabel("3. Hình thức xin phép"),
          _buildDropdownContainer(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedCategory,
                items: const [
                  DropdownMenuItem(value: 'VANG_HOC', child: Text("Vắng học (Cả buổi)")),
                  DropdownMenuItem(value: 'MUON_HOC', child: Text("Đi muộn (Vào sau)")),
                  DropdownMenuItem(value: 'LY_DO_KHAC', child: Text("Lý do khác")),
                ],
                onChanged: (v) => setState(() => _selectedCategory = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildLabel("4. Lý do chi tiết"),
          TextField(
            controller: _reasonController,
            maxLines: 4,
            decoration: _inputDecor("Nhập lý do cụ thể (ốm đau, việc gia đình...)", Icons.edit_note),
          ),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _isLoadingClasses) ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: vinhUniBlue, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: _isSubmitting 
                ? const CircularProgressIndicator(color: Colors.white) 
                : const Text("GỬI ĐƠN XIN PHÉP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: FutureBuilder(
        future: http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/student/attendance-history/${widget.studentId}")),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || !snapshot.hasData) return const Center(child: Text("Lỗi kết nối máy chủ!"));

          final List history = jsonDecode(snapshot.data!.body)['data'] ?? [];
          if (history.isEmpty) return const Center(child: Text("Bạn chưa có đơn xin phép nào.", style: TextStyle(color: Colors.grey)));

          return ListView.separated(
            itemCount: history.length,
            padding: const EdgeInsets.all(15),
            separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final item = history[idx];
              int status = item['status'] ?? 0;
              Color statusColor = status == 1 ? Colors.green : (status == 2 ? Colors.red : Colors.orange);
              
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: statusColor.withOpacity(0.1), child: Icon(status == 1 ? Icons.check : Icons.access_time, color: statusColor, size: 20)),
                  title: Text(item['lhp_name'] ?? "Lớp HP", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text("Ngày vắng: ${item['absence_date'] ?? '---'}\nLý do: ${item['reason']}", style: const TextStyle(fontSize: 11)),
                  trailing: _buildStatusTag(status),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- HÀM GỬI ĐƠN ---
  Future<void> _submitRequest() async {
    if (_selectedLhpId == null || _reasonController.text.isEmpty) {
      _showSnack("Vui lòng nhập lý do và chọn lớp!", Colors.orange); return;
    }
    setState(() => _isSubmitting = true);
    try {
      final res = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/student/send-attendance-request"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": widget.studentId,
          "lhp_code": _selectedLhpId,
          "category": _selectedCategory,
          "reason": _reasonController.text.trim(),
          "year": _selectedYear,
          "semester": _selectedSemester,
          "absence_date": DateFormat('yyyy-MM-dd').format(_selectedDate),
        }),
      );
      if (res.statusCode == 200) {
        _showSnack("Đã gửi đơn thành công!", Colors.green);
        _reasonController.clear();
        _tabController.animateTo(1);
      }
    } catch (e) { _showSnack("Lỗi kết nối Server", Colors.red); }
    setState(() => _isSubmitting = false);
  }

  Widget _buildStatusTag(int status) {
    String text = "Chờ duyệt"; Color color = Colors.orange;
    if (status == 1) { text = "Đã duyệt"; color = Colors.green; }
    if (status == 2) { text = "Từ chối"; color = Colors.red; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 5), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)));
  
  Widget _buildDropdownContainer({required Widget child}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: child);

  InputDecoration _inputDecor(String hint, IconData icon) => InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: vinhUniBlue), filled: true, fillColor: Colors.white, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)));

  void _showSnack(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating));
}