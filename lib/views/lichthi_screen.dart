import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lichthi.dart';
import '../services/database_helper.dart';
import '../core/api/api.dart';
import '../core/auth/session.dart';
import '../core/offline/cached_fetch.dart';
import '../core/offline/dai_bao_ban_cu.dart';

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

  /// Đúng khi máy chủ không phản hồi và màn hình đang hiển thị dữ liệu đã lưu
  /// trên máy. Dùng để báo cho người dùng biết số liệu có thể chưa mới nhất.
  bool dangXemBanCu = false;
  String? errorMessage;

  List<String> listNamHoc = [];
  List<String> listHocKy = [];
  String selectedNamHoc = "";
  String selectedHocKy = "";

  String selectedProgramId = "ALL";
  List<Map<String, dynamic>> programList = [
    {"program_id": "ALL", "program_name": "Tất cả ngành học"}
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // --- 1. LOGIC KHỞI TẠO (CACHE FIRST) ---
  Future<void> _initData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    final db = DatabaseHelper.instance;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }

      // A. Đọc bộ lọc từ Cache SQLite trước để hiện Năm/Kỳ ngay
      final cachedFilters = await db.getExamFilters(userId);
      if (cachedFilters != null && cachedFilters.isNotEmpty) {
        _processFilters(cachedFilters);
        // Hiện lịch thi cũ từ máy lên trước cho SV xem luôn
        _fetchExams(userId, useCacheOnly: true);
      }

      // B. Gọi mạng âm thầm cập nhật dữ liệu mới
      await _fetchPrograms(userId);
      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        await db.saveExamFilters(userId, rawFilterData); 
        _processFilters(rawFilterData);
        await _fetchExams(userId); 
      } else if (examData.isEmpty && cachedFilters == null) {
        setState(() { errorMessage = "Không tìm thấy dữ liệu lọc."; isLoading = false; });
      }
    } catch (e) {
      if (examData.isEmpty) {
        setState(() { errorMessage = "Lỗi kết nối máy chủ!"; isLoading = false; });
      }
    }
  }

  void _processFilters(List data) {
    setState(() {
      rawFilterData = data;
      listNamHoc = data.map((e) => e['nam'].toString()).toSet().toList();
      listNamHoc.sort((a, b) => b.compareTo(a));
      
      if (selectedNamHoc.isEmpty || !listNamHoc.contains(selectedNamHoc)) {
        selectedNamHoc = listNamHoc.isNotEmpty ? listNamHoc.first.toString() : "";
      }
      _updateKys();
    });
  }

  void _updateKys() {
    setState(() {
      listHocKy = rawFilterData
          .where((e) => e['nam'].toString() == selectedNamHoc)
          .map((e) => e['ky'].toString())
          .toSet().toList();
      listHocKy.sort();
      if (selectedHocKy.isEmpty || !listHocKy.contains(selectedHocKy)) {
        selectedHocKy = listHocKy.isNotEmpty ? listHocKy.first.toString() : "";
      }
    });
  }

  // --- 2. HÀM LẤY LỊCH THI ---
  //
  // Sửa 18/08/2026 (Pha 1): dùng chung cachedFetch thay cho đoạn
  // "đọc đệm → hiện ngay → gọi mạng → ghi đè" từng được chép lại ở cả bốn màn
  // lịch với bốn cách xử lý lỗi khác nhau.
  //
  // Điểm mới so với bản cũ: khi máy chủ lỗi, màn hình nói rõ đang xem dữ liệu
  // cũ thay vì im lặng hiển thị số liệu có thể đã lỗi thời.
  Future<void> _fetchExams(String userId, {bool useCacheOnly = false}) async {
    final db = DatabaseHelper.instance;
    final String nam = selectedNamHoc;
    final String ky = selectedHocKy;

    await cachedFetch<List<dynamic>>(
      duongDan: '/api/get-exams/$userId',
      thamSo: {
        'nam_hoc': nam,
        'hoc_ky': ky,
        'program_id': selectedProgramId,
      },
      hanCho: const Duration(seconds: 10),
      chiDocTuMay: useCacheOnly,
      docTuMay: () => db.getExams(userId, nam, ky),
      ghiVaoMay: (duLieu) => db.saveExams(userId, nam, ky, duLieu),
      chuyenDoi: (tho) => tho is List ? tho : <dynamic>[],
      khiCoDuLieu: (kq) {
        if (!mounted) return;
        setState(() {
          examData = kq.duLieu;
          isLoading = false;
          dangXemBanCu = kq.dangDungBanCu;
        });
      },
    );
  }

  Future<void> _fetchPrograms(String userId) async {
    final res = await Api.get('/api/student-programs/$userId');
    if (!res.thanhCong) {
      debugPrint("⚠️ [LịchThi] Không tải được danh sách ngành: ${res.thongDiepLoi}");
      return;
    }

    final data = res.data is List ? res.data as List : const [];
    if (!mounted) return;
    setState(() {
      programList = [
        {"program_id": "ALL", "program_name": "Tất cả ngành học"},
        ...data.map((e) => {
              "program_id": e["program_id"].toString(),
              "program_name": e["program_name"].toString()
            }),
      ];
    });
  }

  // --- 3. HELPER FORMAT ---
  String _formatCaThi(String caThiRaw) {
    if (caThiRaw == "---" || caThiRaw.isEmpty) return "---";
    final RegExp timeReg = RegExp(r'(\d+)\s*\(Bắt đầu:\s*(\d{2}:\d{2})');
    final match = timeReg.firstMatch(caThiRaw);
    if (match != null) return "Ca ${match.group(1)} (${match.group(2)})";
    return caThiRaw;
  }

  String _getCoSoName(dynamic id) {
    String strId = id.toString();
    if (strId == "2") return "CS2 (Nghi Lộc)";
    if (strId == "1") return "CS1 (Lê Duẩn)";
    return "Chưa xác định";
  }

  // --- 4. GIAO DIỆN ---
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
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          DaiBaoBanCu(
            hienThi: dangXemBanCu,
            khiBamTaiLai: () async => _fetchExams(await Session.userCode),
          ),
          Expanded(
            child: isLoading && examData.isEmpty
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null && examData.isEmpty
                ? _buildErrorView()
                : RefreshIndicator(
                    onRefresh: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await _fetchExams(prefs.getString('user_id') ?? "");
                    },
                    child: examData.isEmpty ? _buildEmptyView() : _buildExamList(),
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
                    child: Text(program["program_name"]!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() => selectedProgramId = v!);
                  _triggerFetch();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (v) {
                setState(() => selectedNamHoc = v!);
                _updateKys();
                _triggerFetch();
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown("Học kỳ", selectedHocKy, listHocKy, (v) {
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
    final String? userId = prefs.getString('user_id');
    if (userId != null) _fetchExams(userId);
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: vinhUniBlue.withOpacity(0.6), fontSize: 11),
          filled: true,
          fillColor: vinhUniBlue.withOpacity(0.02),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
      onChanged: onChanged,
    );
  }

  // --- ĐÂY LÀ HÀM DUY NHẤT _buildExamList ---
  Widget _buildExamList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: examData.length,
      itemBuilder: (context, index) {
        final item = examData[index];
        
        // 🔥 FIX LỖI TYPE: Luôn dùng .toString()
        final String phong = item['Phong']?.toString() ?? "---";
        final String caThi = item['Gio']?.toString() ?? "---"; 
        final String sbd = item['SBD']?.toString() ?? "---";
        final String hinhThuc = item['HinhThucThi']?.toString() ?? "---";
        final String coSo = _getCoSoName(item['IDDM_Cosodaotao']?.toString() ?? "");
        final String ngayThi = item['NgayThi']?.toString() ?? "---";
        final String tenMon = item['TenHocPhan']?.toString() ?? "Học phần";

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: examAccent.withOpacity(0.04), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 18, color: examAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tenMon, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 18, color: vinhUniBlue),
                        const SizedBox(width: 10),
                        Text(ngayThi, style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _infoBox("Phòng", phong, Icons.location_on, Colors.blueGrey),
                        _infoBox("Thời gian", _formatCaThi(caThi), Icons.access_time, Colors.orange),
                        _infoBox("SBD", sbd, Icons.badge, Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _infoChip(coSo, Icons.business, Colors.indigo),
                        const SizedBox(width: 8),
                        _infoChip(hinhThuc, Icons.assignment, Colors.purple),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _infoChip(String text, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Widget _infoBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEmptyView() => const Center(child: Text("Không có lịch thi", style: TextStyle(color: Colors.grey)));
  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(errorMessage ?? "Lỗi tải dữ liệu"),
    TextButton(onPressed: _initData, child: const Text("Thử lại"))
  ]));
}