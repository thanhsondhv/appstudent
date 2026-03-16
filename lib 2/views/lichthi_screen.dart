import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http; // Bắt buộc thêm để gọi API trực tiếp
import 'dart:convert';
import '../services/lichthi.dart';

class LichThiScreen extends StatefulWidget {
  const LichThiScreen({super.key});
  @override
  State<LichThiScreen> createState() => _LichThiScreenState();
}

class _LichThiScreenState extends State<LichThiScreen> {
  final LichThiService _service = LichThiService();
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color examAccent = const Color(0xFFE53935);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  List<dynamic> rawFilterData = [];
  List<dynamic> examData = [];
  bool isLoading = true;
  String? errorMessage;

  List<String> listNamHoc = [];
  List<String> listHocKy = [];
  String selectedNamHoc = "";
  String selectedHocKy = "";

  // 🌟 KHAI BÁO BIẾN CHO TÍNH NĂNG 2 NGÀNH
  String selectedProgramId = "ALL";
  List<Map<String, dynamic>> programList = [
    {"program_id": "ALL", "program_name": "Tất cả ngành học"}
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }

      // Lấy danh sách Ngành học trước
      await _fetchPrograms(userId);

      // Lấy filters thô
      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        listNamHoc = rawFilterData.map((e) => e['nam'].toString()).toSet().toList();
        listNamHoc.sort((a, b) => b.compareTo(a));
        selectedNamHoc = listNamHoc.first;

        _updateKys();
        await _fetchExams(userId);
      } else {
        setState(() { errorMessage = "Không tìm thấy dữ liệu lọc."; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi kết nối máy chủ!"; isLoading = false; });
    }
  }

  // 🌟 HÀM TẢI DANH SÁCH NGÀNH
  Future<void> _fetchPrograms(String userId) async {
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/student-programs/$userId'; 
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          programList = [
            {"program_id": "ALL", "program_name": "Tất cả ngành học"},
            ...data.map((e) => {
                  "program_id": e["program_id"].toString(),
                  "program_name": e["program_name"].toString()
                }).toList()
          ];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách ngành: $e");
    }
  }

  void _updateKys() {
    setState(() {
      listHocKy = rawFilterData
          .where((e) => e['nam'].toString() == selectedNamHoc)
          .map((e) => e['ky'].toString())
          .toSet().toList();
      listHocKy.sort();
      selectedHocKy = listHocKy.isNotEmpty ? listHocKy.first : "";
    });
  }

  // 🌟 ĐÃ CẬP NHẬT: TRUYỀN THÊM PROGRAM ID
  Future<void> _fetchExams(String userId) async {
    setState(() => isLoading = true);
    try {
      String nam = selectedNamHoc == "Tất cả" ? "ALL" : selectedNamHoc;
      String ky = selectedHocKy == "Tất cả" ? "ALL" : selectedHocKy;
      final url = 'https://mobi.vinhuni.edu.vn/api/get-exams/$userId?nam_hoc=$nam&hoc_ky=$ky&program_id=$selectedProgramId';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> exams = json.decode(response.body);
        setState(() {
          examData = exams;
          isLoading = false;
        });
      } else {
        setState(() { examData = []; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi tải lịch thi!"; isLoading = false; });
    }
  }

  String _extractFromHtml(String html, String label) {
    if (html.isEmpty) return "---";
    final RegExp regExp = RegExp('$label:</b>\\s*(?:<span[^>]*>)?([^<]+)');
    final match = regExp.firstMatch(html);
    return match != null ? match.group(1)!.trim().replaceAll('&nbsp;', ' ') : "---";
  }

  String _formatCaThi(String caThiRaw) {
    if (caThiRaw == "---" || caThiRaw.isEmpty) return "---";
    final RegExp timeReg = RegExp(r'(\d+)\s*\(Bắt đầu:\s*(\d{2}:\d{2})');
    final match = timeReg.firstMatch(caThiRaw);
    if (match != null) return "Ca ${match.group(1)} (${match.group(2)})";
    
    if (caThiRaw.contains(':') && caThiRaw.length >= 5) {
       return caThiRaw.substring(0, 5);
    }
    return caThiRaw;
  }
  String _getCoSoName(dynamic id) {
    if (id == 2 || id == "2") return "CS2 (Nghi Lộc)";
    if (id == 1 || id == "1") return "CS1 (Lê Duẩn)";
    return "Chưa xác định";
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: const Text("LỊCH THI CHI TIẾT",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16, letterSpacing: 1.1)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null
                ? _buildErrorView()
                : _buildExamList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          // 🌟 COMBOBOX CHỌN NGÀNH (Giống hệt bên Bảng điểm)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: vinhUniBlue.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: vinhUniBlue.withOpacity(0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedProgramId,
                icon: Icon(Icons.school_rounded, color: vinhUniBlue.withOpacity(0.7)),
                items: programList.map((program) {
                  return DropdownMenuItem<String>(
                    value: program["program_id"],
                    child: Text(
                      program["program_name"],
                      style: TextStyle(
                          fontSize: 13, 
                          fontWeight: program["program_id"] == "ALL" ? FontWeight.bold : FontWeight.w500,
                          color: program["program_id"] == "ALL" ? vinhUniBlue : Colors.black87
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) async {
                  if (newValue != null) {
                    setState(() {
                      selectedProgramId = newValue;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    final id = prefs.getString('user_id');
                    if (id != null) _fetchExams(id);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (v) {
                selectedNamHoc = v!;
                _updateKys(); 
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown("Học kỳ", selectedHocKy, listHocKy, (v) {
                setState(() => selectedHocKy = v!);
              })),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final String? userId = prefs.getString('user_id');
                if (userId != null) _fetchExams(userId);
              },
              icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
              label: const Text("TRA CỨU LỊCH THI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: vinhUniBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: vinhUniBlue.withOpacity(0.6), fontSize: 12),
          filled: true,
          fillColor: vinhUniBlue.withOpacity(0.02),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildExamList() {
    if (examData.isEmpty) return _buildEmptyView();
    
    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      physics: const BouncingScrollPhysics(),
      itemCount: examData.length,
      itemBuilder: (context, index) {
        final item = examData[index];
        
        // Lấy dữ liệu trực tiếp từ các trường mới của API
        final String phong = item['Phong']?.toString() ?? "---";
        final String caThi = item['Gio']?.toString() ?? "---"; 
        final String sbd = item['SBD']?.toString() ?? "---";
        final String hinhThuc = item['HinhThucThi']?.toString() ?? "---";
        final String coSo = _getCoSoName(item['IDDM_Cosodaotao']);
        
        final String ngayThi = item['NgayThi']?.toString() ?? "---";

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 5, color: examAccent.withOpacity(0.7)),
                  Expanded(
                    child: Column(
                      children: [
                        // Header: Tên môn học
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: examAccent.withOpacity(0.04),
                          child: Row(
                            children: [
                              Icon(Icons.menu_book_rounded, size: 18, color: examAccent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(item['TenHocPhan'] ?? "Học phần",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF34495E))),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hàng 1: Ngày thi
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 18, color: vinhUniBlue),
                                  const SizedBox(width: 10),
                                  Text(ngayThi, style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 15)),
                                ],
                              ),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, thickness: 0.5)),
                              
                              // Hàng 2: Phòng - Thời gian - SBD
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _infoBox("Phòng", phong, Icons.location_on_rounded, Colors.blueGrey),
                                  _infoBox("Thời gian", _formatCaThi(caThi), Icons.access_time_filled_rounded, Colors.orange),
                                  _infoBox("SBD", sbd, Icons.badge_rounded, Colors.teal),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Hàng 3 (MỚI): Cơ sở - Hình thức thi
                              Row(
                                children: [
                                  _infoChip(coSo, Icons.business_rounded, Colors.indigo),
                                  const SizedBox(width: 8),
                                  _infoChip(hinhThuc, Icons.assignment_rounded, Colors.purple),
                                ],
                              ),
                              
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: examAccent),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text("Lưu ý: Mang theo thẻ SV/CCCD để vào phòng thi.", 
                                      style: TextStyle(fontSize: 10, color: examAccent, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              )
                            ],
                          ),
                        )
                      ],
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
  Widget _infoChip(String text, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, 
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _infoBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, 
            textAlign: TextAlign.center, 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2C3E50))
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.event_busy_rounded, size: 60, color: vinhUniBlue.withOpacity(0.2)),
    const SizedBox(height: 10),
    const Text("Không có lịch thi", style: TextStyle(color: Colors.grey))
  ]));

  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(errorMessage ?? "Lỗi không xác định"),
    TextButton(onPressed: () {
       _initData(); 
    }, child: const Text("Thử lại"))
  ]));
}