import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/diemthi.dart';
import '../services/database_helper.dart'; // 🔥 Sửa lỗi DatabaseHelper
import '../core/api/api.dart';

class DiemThiScreen extends StatefulWidget {
  const DiemThiScreen({super.key});
  @override
  State<DiemThiScreen> createState() => _DiemThiScreenState();
}

class _DiemThiScreenState extends State<DiemThiScreen> {
  final DiemThiService _service = DiemThiService();
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  List<dynamic> rawFilterData = [];
  List<dynamic> gradeData = [];
  bool isLoading = true;
  String? errorMessage;

  List<String> listNamHoc = [];
  List<String> listHocKy = [];
  String selectedNamHoc = "Tất cả";
  String selectedHocKy = "Tất cả";

  // Biến cho tính năng Ngành học
  String selectedProgramId = "ALL";
  List<Map<String, dynamic>> programList = [
    {"program_id": "ALL", "program_name": "Tất cả ngành học"}
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // --- 1. KHỞI TẠO DỮ LIỆU (CƠ CHẾ CACHE-FIRST) ---
  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    final db = DatabaseHelper.instance;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');

      if (userId == null) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }

      // A. HIỆN BỘ LỌC TỪ CACHE NGAY LẬP TỨC
      final cachedFilters = await db.getGradeFilters(userId);
      if (cachedFilters != null && cachedFilters.isNotEmpty) {
        _processFilters(cachedFilters);
        _fetchGrades(userId, useCacheOnly: true); // Hiện điểm cũ từ máy luôn
      }

      // B. TẢI NGÀNH & BỘ LỌC MỚI TỪ API (Âm thầm)
      await _fetchPrograms(userId);
      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        await db.saveGradeFilters(userId, rawFilterData); // Lưu cache vào SQLite
        _processFilters(rawFilterData);
        await _fetchGrades(userId); // Cập nhật bản mới từ mạng
      } else if (gradeData.isEmpty && cachedFilters == null) {
        setState(() { errorMessage = "Không tìm thấy dữ liệu bộ lọc"; isLoading = false; });
      }
    } catch (e) {
      if (gradeData.isEmpty) {
        setState(() { errorMessage = "Lỗi kết nối hệ thống!"; isLoading = false; });
      }
    }
  }

  void _processFilters(List data) {
    setState(() {
      rawFilterData = data;
      // Ép kiểu String cho năm để tránh lỗi Type
      var nams = data.map((e) => e['nam'].toString()).toSet().toList();
      nams.sort((a, b) => b.compareTo(a));
      listNamHoc = ["Tất cả", ...nams];
      
      if (selectedNamHoc.isEmpty || !listNamHoc.contains(selectedNamHoc)) {
        selectedNamHoc = listNamHoc.first;
      }
      _updateKys();
    });
  }

  // --- 2. TẢI BẢNG ĐIỂM (DUY NHẤT 1 HÀM) ---
  Future<void> _fetchGrades(String userId, {bool useCacheOnly = false}) async {
    final db = DatabaseHelper.instance;
    String nam = selectedNamHoc == "Tất cả" ? "ALL" : selectedNamHoc;
    String ky = selectedHocKy == "Tất cả" ? "ALL" : selectedHocKy;
    String prog = selectedProgramId;

    // A. ĐỌC TỪ SQLITE HIỆN LÊN TRƯỚC (0.1 giây)
    final cached = await db.getGrades(userId, nam, ky, prog);
    if (cached != null) {
      setState(() {
        gradeData = cached;
        isLoading = false; 
      });
    } else if (!useCacheOnly) {
      setState(() => isLoading = true); 
    }

    if (useCacheOnly) return;

    // B. GỌI API ĐỒNG BỘ BẢN MỚI
    try {
      final response = await Api.get(
        '/api/get-grades/$userId',
        thamSo: {'nam_hoc': nam, 'hoc_ky': ky, 'program_id': prog},
        hanCho: const Duration(seconds: 10),
      );

      if (response.thanhCong) {
        final List<dynamic> data = response.data is List ? response.data as List : const [];
        await db.saveGrades(userId, nam, ky, prog, data); // Lưu lại vào SQLite
        
        if (mounted) {
          setState(() {
            gradeData = data;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Offline mode: Đang hiển thị điểm từ cache.");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- 3. CÁC HÀM HỖ TRỢ ---
  Future<void> _fetchPrograms(String userId) async {
    try {
      final response = await Api.get('/api/student-programs/$userId');
      if (response.thanhCong) {
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
      if (selectedNamHoc == "Tất cả") {
        listHocKy = ["Tất cả"];
      } else {
        var kys = rawFilterData
            .where((e) => e['nam'].toString() == selectedNamHoc)
            .map((e) => e['ky'].toString())
            .toSet().toList();
        kys.sort();
        listHocKy = ["Tất cả", ...kys];
      }
      selectedHocKy = listHocKy.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("KẾT QUẢ HỌC TẬP",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading && gradeData.isEmpty
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null && gradeData.isEmpty
                ? _buildErrorView() 
                : RefreshIndicator(
                    onRefresh: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await _fetchGrades(prefs.getString('user_id') ?? "");
                    },
                    child: _buildGradeList(),
                  ),
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
          // ComboBox chọn Ngành
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.05), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.school_rounded, size: 20, color: vinhUniBlue),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedProgramId,
                    items: programList.map<DropdownMenuItem<String>>((p) {
                      return DropdownMenuItem<String>(
                        value: p["program_id"].toString(),
                        child: Text(p["program_name"].toString(), 
                          style: const TextStyle(fontSize: 13, overflow: TextOverflow.ellipsis)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() => selectedProgramId = v!);
                      _triggerFetch();
                    },
                  ),
                ),
              )
            ]),
          ),
          const SizedBox(height: 12),
          // Bộ lọc Năm học - Học kỳ
          Row(
            children: [
              Expanded(child: _buildInputDropdown("Năm học", selectedNamHoc, listNamHoc, (v) {
                setState(() {
                  selectedNamHoc = v!;
                  _updateKys();
                });
                _triggerFetch();
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildInputDropdown("Học kỳ", selectedHocKy, listHocKy, (v) {
                setState(() => selectedHocKy = v!);
                _triggerFetch();
              })),
            ],
          ),
        ],
      ),
    );
  }

  void _triggerFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('user_id');
    if (id != null) _fetchGrades(id);
  }

  Widget _buildInputDropdown(String label, String val, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: items.contains(val) ? val : (items.isNotEmpty ? items.first : null),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: vinhUniBlue.withOpacity(0.1))),
      ),
      items: items.map<DropdownMenuItem<String>>((String i) => DropdownMenuItem<String>(value: i, child: Text(i, style: const TextStyle(fontSize: 12)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildGradeList() {
    if (gradeData.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: gradeData.length,
      itemBuilder: (context, index) {
        final item = gradeData[index];
        final String rawInfo = item['NoiDung']?.toString() ?? "";
        final String summary = item['NgayThi']?.toString() ?? "";

        String parse(String key) {
          final parts = rawInfo.split('|');
          for (var p in parts) {
            if (p.contains(key)) return p.split(':').last.trim();
          }
          return "---";
        }

        final he10 = RegExp(r'Tổng kết:\s*([\d\.]+)').firstMatch(summary)?.group(1) ?? "---";
        final letter = RegExp(r'\(([A-F\+\s]+)\)').firstMatch(summary)?.group(1) ?? "?";
        final Color statusColor = _getGradeColor(letter);

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.03), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_outline_rounded, size: 20, color: vinhUniBlue),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item['TenHocPhan']?.toString() ?? "Học phần", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: vinhUniBlue, borderRadius: BorderRadius.circular(10)),
                      child: Text("TC: ${parse("TC")}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _scoreItem("Chuyên cần", parse("CC"), Icons.edit_note),
                        _scoreItem("Giữa kỳ", parse("GK"), Icons.pending_actions),
                        _scoreItem("Cuối kỳ", parse("Thi"), Icons.assignment_turned_in, isBlue: true),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _summaryText("Hệ 10:", he10, vinhUniBlue),
                            _summaryText("Hệ 4:", parse("Hệ 4"), Colors.green.shade700),
                          ],
                        ),
                        _buildLetterBadge(letter, statusColor),
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _scoreItem(String label, String val, IconData icon, {bool isBlue = false}) => Column(children: [
    Icon(icon, size: 18, color: isBlue ? vinhUniBlue : Colors.grey),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isBlue ? vinhUniBlue : Colors.black87)),
  ]);

  Widget _summaryText(String label, String val, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(width: 8),
      Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  Widget _buildLetterBadge(String letter, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
    child: Text(letter, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
  );

  Widget _buildEmptyState() => const Center(child: Text("Không có dữ liệu", style: TextStyle(color: Colors.grey)));
  Widget _buildErrorView() => Center(child: Text(errorMessage ?? "Lỗi tải bảng điểm"));

  Color _getGradeColor(String grade) {
    if (grade.contains('A')) return Colors.green.shade700;
    if (grade.contains('B')) return Colors.blue.shade700;
    if (grade.contains('C')) return Colors.orange.shade700;
    if (grade.contains('D')) return Colors.deepOrange;
    return Colors.red.shade700;
  }
}