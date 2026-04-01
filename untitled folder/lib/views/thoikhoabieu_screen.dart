import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/database_helper.dart'; // 🔥 Dòng quan trọng nhất để sửa lỗi của bạn

class ThoiKhoaBieuScreen extends StatefulWidget {
  const ThoiKhoaBieuScreen({super.key});
  @override
  State<ThoiKhoaBieuScreen> createState() => _ThoiKhoaBieuScreenState();
}

class _ThoiKhoaBieuScreenState extends State<ThoiKhoaBieuScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);

  List<dynamic> rawFilterData = []; 
  List<dynamic> scheduleData = [];
  bool isLoading = true;
  String? errorMessage;

  List<String> listNamHoc = [];
  List<String> listHocKy = [];
  List<String> listTuan = [];

  String selectedNamHoc = "";
  String selectedHocKy = "";
  String selectedTuan = "";

  String selectedProgramId = "ALL";
  List<Map<String, dynamic>> programList = [
    {"program_id": "ALL", "program_name": "Tất cả ngành học"}
  ];

  String currentUserId = "";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // =========================================================================
  // 1. LUỒNG KHỞI TẠO (CƠ CHẾ CACHE-FIRST)
  // =========================================================================
  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    final db = DatabaseHelper.instance;
    
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');

    if (userId == null || userId.isEmpty) {
      setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
      return;
    }
    currentUserId = userId;

    try {
      // A. Đọc bộ lọc từ máy (Hiện Năm/Kỳ/Tuần ngay lập tức)
      final cachedFilters = await db.getScheduleFilters(currentUserId);
      if (cachedFilters != null && cachedFilters.isNotEmpty) {
        _processFilters(cachedFilters);
        // Hiện lịch cũ từ máy lên trước (0.1 giây)
        _fetchSchedule(currentUserId, useCacheOnly: true); 
      }

      // B. Gọi mạng âm thầm cập nhật dữ liệu mới
      await _fetchPrograms(currentUserId);
      final url = 'https://mobi.vinhuni.edu.vn/api/get-filters/$currentUserId';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final List<dynamic> newData = json.decode(response.body);
        await db.saveScheduleFilters(currentUserId, newData); // Lưu cache SQLite
        _processFilters(newData);
        await _fetchSchedule(currentUserId); // Cập nhật bản mới từ mạng
      }
    } catch (e) {
      if (scheduleData.isEmpty) setState(() => isLoading = false);
    }
  }

  void _processFilters(List data) {
    setState(() {
      rawFilterData = data;
      listNamHoc = data.map((e) => e['nam'].toString()).toSet().toList();
      listNamHoc.sort((a, b) => b.compareTo(a));
      
      if (selectedNamHoc.isEmpty || !listNamHoc.contains(selectedNamHoc)) {
        selectedNamHoc = listNamHoc.isNotEmpty ? listNamHoc.first : "";
      }
      _updateFilters(updateNam: true);
    });
  }

  // =========================================================================
  // 2. LẤY LỊCH HỌC (CACHE + API)
  // =========================================================================
  Future<void> _fetchSchedule(String userId, {bool useCacheOnly = false}) async {
    final db = DatabaseHelper.instance;
    String nam = selectedNamHoc;
    String ky = selectedHocKy;
    String tuan = selectedTuan;
    String prog = selectedProgramId;

    // A. Đọc máy hiện lên trước (Khử xoay)
    final cached = await db.getSchedule(userId, nam, ky, tuan, prog);
    if (cached != null) {
      setState(() {
        scheduleData = cached;
        isLoading = false; 
      });
    } else if (!useCacheOnly) {
      setState(() => isLoading = true); 
    }

    if (useCacheOnly) return;

    // B. Gọi mạng cập nhật
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/get-schedule/$userId?nam_hoc=$nam&hoc_ky=$ky&tuan=$tuan&program_id=$prog';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        await db.saveSchedule(userId, nam, ky, tuan, prog, data); // Lưu cache
        
        if (mounted) {
          setState(() {
            scheduleData = data;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // =========================================================================
  // 3. LOGIC HỖ TRỢ (NGÀNH, BỘ LỌC)
  // =========================================================================
  Future<void> _fetchPrograms(String userId) async {
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/student-programs/$userId'; 
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          programList = [
            {"program_id": "ALL", "program_name": "Tất cả ngành học"},
            ...data.map((e) => {
              "program_id": e["program_id"].toString(), 
              "program_name": e["program_name"].toString()
            })
          ];
        });
      }
    } catch (e) { debugPrint("Offline programs: $e"); }
  }

  void _updateFilters({bool updateNam = false}) {
    setState(() {
      if (updateNam) {
        listHocKy = rawFilterData
            .where((e) => e['nam'].toString() == selectedNamHoc)
            .map((e) => e['ky'].toString())
            .toSet().toList();
        listHocKy.sort();
        if (selectedHocKy.isEmpty || !listHocKy.contains(selectedHocKy)) {
          selectedHocKy = listHocKy.isNotEmpty ? listHocKy.first : "";
        }
      }

      listTuan = rawFilterData
          .where((e) => e['nam'].toString() == selectedNamHoc && e['ky'].toString() == selectedHocKy)
          .map((e) => e['tuan'].toString())
          .toSet().toList();
      
      List<int> intTuans = listTuan.map((e) => int.tryParse(e) ?? 0).toList();
      intTuans.sort();
      listTuan = intTuans.map((e) => e.toString()).toList();
      
      if (selectedTuan.isEmpty || !listTuan.contains(selectedTuan)) {
        selectedTuan = listTuan.isNotEmpty ? listTuan.first : "";
      }
    });
  }

  // =========================================================================
  // 4. GIAO DIỆN CHÍNH
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text("Thời Khóa Biểu", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: vinhUniBlue, 
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading && scheduleData.isEmpty
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null && scheduleData.isEmpty
                ? _buildErrorView()
                : RefreshIndicator(
                    onRefresh: () => _fetchSchedule(currentUserId),
                    child: _buildList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true, value: selectedProgramId, icon: Icon(Icons.school_rounded, color: vinhUniBlue.withOpacity(0.7)),
                items: programList.map((p) => DropdownMenuItem(value: p["program_id"] as String, child: Text(p["program_name"], style: TextStyle(fontSize: 13, fontWeight: p["program_id"] == "ALL" ? FontWeight.bold : FontWeight.w500, color: p["program_id"] == "ALL" ? vinhUniBlue : Colors.black87), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (val) {
                  if (val != null) { setState(() => selectedProgramId = val); _fetchSchedule(currentUserId); }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (val) { selectedNamHoc = val!; _updateFilters(updateNam: true); _fetchSchedule(currentUserId); })),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown("Học kỳ", selectedHocKy, listHocKy, (val) { selectedHocKy = val!; _updateFilters(); _fetchSchedule(currentUserId); })),
            ],
          ),
          const SizedBox(height: 12),
          _buildDropdown("Tuần học", selectedTuan, listTuan, (val) { setState(() => selectedTuan = val!); _fetchSchedule(currentUserId); }, prefixIcon: Icons.calendar_view_week_rounded),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged, {IconData? prefixIcon}) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
      isExpanded: true, menuMaxHeight: 300,
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(fontSize: 13, color: vinhUniBlue),
        filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: vinhUniBlue) : null,
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(label == "Tuần học" ? "Tuần $e" : e, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildList() {
    if (scheduleData.isEmpty) return _buildEmptyView();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scheduleData.length,
      itemBuilder: (context, index) {
        final item = scheduleData[index];
        
        // 🔥 FIX LỖI TYPE: Luôn dùng .toString()
        String rawNoiDung = item['NoiDung']?.toString() ?? "";
        rawNoiDung = rawNoiDung.replaceAll('<b>', '').replaceAll('</b>', '').replaceAll('<br>', '\n').replaceAll('📍 ', '').replaceAll('⏰ ', '').replaceAll('📅 ', '');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 5, color: vinhUniBlue),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['TenHocPhan']?.toString() ?? "Môn học", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(Icons.calendar_today_rounded, size: 13, color: vinhUniBlue.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Text(item['NgayThi']?.toString() ?? "", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ]),
                          const Divider(height: 20),
                          Text(rawNoiDung, style: const TextStyle(height: 1.4, fontSize: 13, color: Color(0xFF475569))),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _showAttendanceRequestSheet(item),
                              icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                              label: const Text("Xin nghỉ / Đi muộn", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 5. XIN NGHỈ HỌC
  // =========================================================================
  void _showAttendanceRequestSheet(dynamic item) {
    String? lhpCode = item['MaLopHP']?.toString();
    if (lhpCode == null || lhpCode.isEmpty || lhpCode == "null") {
      _showSnack("Lỗi: Không tìm thấy mã lớp học phần!", Colors.red);
      return;
    }

    String selectedType = 'VANG_HOC';
    final TextEditingController reasonCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              Text("XIN PHÉP VẮNG / MUỘN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: vinhUniBlue)),
              Text("Môn: ${item['TenHocPhan']}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
              const Divider(height: 30),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: _inputDecor("Hình thức xin phép", Icons.category_rounded),
                items: const [
                  DropdownMenuItem(value: 'VANG_HOC', child: Text("Vắng học (Cả buổi)")),
                  DropdownMenuItem(value: 'MUON_HOC', child: Text("Đi muộn (Vào sau)")),
                  DropdownMenuItem(value: 'LY_DO_KHAC', child: Text("Lý do khác")),
                ],
                onChanged: (v) => setModalState(() => selectedType = v!),
              ),
              const SizedBox(height: 15),
              TextField(controller: reasonCtrl, maxLines: 3, decoration: _inputDecor("Nhập lý do chi tiết...", Icons.edit_note_rounded)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => _submitAttendanceRequest(lhpCode, selectedType, reasonCtrl.text),
                  child: const Text("GỬI ĐƠN XIN PHÉP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAttendanceRequest(String lhpCode, String category, String reason) async {
    if (reason.trim().isEmpty) { _showSnack("Vui lòng nhập lý do!", Colors.orange); return; }
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
    try {
      final res = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/student/send-attendance-request"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": currentUserId, "lhp_code": lhpCode, "category": category, "reason": reason}),
      ).timeout(const Duration(seconds: 10));
      Navigator.pop(context); // Tắt loading
      if (res.statusCode == 200) {
        Navigator.pop(context); // Đóng BottomSheet
        _showSnack("Gửi đơn thành công!", Colors.green);
      }
    } catch (e) { Navigator.pop(context); _showSnack("Lỗi kết nối server!", Colors.red); }
  }

  // --- HELPERS ---
  void _showSnack(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(10)));
  InputDecoration _inputDecor(String l, IconData i) => InputDecoration(labelText: l, prefixIcon: Icon(i, color: vinhUniBlue, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));
  Widget _buildEmptyView() => const Center(child: Text("Không có lịch học", style: TextStyle(color: Colors.grey)));
  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(errorMessage ?? "Lỗi"), TextButton(onPressed: _initData, child: const Text("Thử lại"))]));
}