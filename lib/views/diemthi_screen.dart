import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/diemthi.dart';

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
  String selectedNamHoc = "";
  String selectedHocKy = "";

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

      if (userId == null) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }

      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        listNamHoc = rawFilterData.map((e) => e['nam'].toString()).toSet().toList();
        listNamHoc.sort((a, b) => b.compareTo(a));
        selectedNamHoc = listNamHoc.first;

        _updateKys();
        await _fetchGrades(userId);
      } else {
        setState(() { errorMessage = "Không tìm thấy dữ liệu bộ lọc"; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi kết nối hệ thống!"; isLoading = false; });
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

  Future<void> _fetchGrades(String userId) async {
    setState(() => isLoading = true);
    final grades = await _service.getGrades(
        userId: userId,
        namHoc: selectedNamHoc,
        hocKy: selectedHocKy
    );
    setState(() {
      gradeData = grades;
      isLoading = false;
    });
  }

  Color _getGradeColor(String grade) {
    final g = grade.toUpperCase();
    if (g.startsWith('A')) return const Color(0xFF2E7D32);
    if (g.startsWith('B')) return const Color(0xFF43A047);
    if (g.startsWith('C')) return const Color(0xFFFB8C00);
    if (g.startsWith('D')) return const Color(0xFFF4511E);
    return const Color(0xFFD32F2F);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
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
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null ? _buildErrorView() : _buildGradeList(),
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
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [vinhUniBlue, vinhUniBlue.withOpacity(0.8)]),
            ),
            child: ElevatedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final id = prefs.getString('user_id');
                if (id != null) _fetchGrades(id);
              },
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              label: const Text("TRA CỨU ĐIỂM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
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
          labelStyle: TextStyle(color: vinhUniBlue.withOpacity(0.7), fontSize: 13),
          filled: true, fillColor: vinhUniBlue.withOpacity(0.03),
          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: vinhUniBlue.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: vinhUniBlue))),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildGradeList() {
    if (gradeData.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined, size: 80, color: vinhUniBlue.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text("Chưa có dữ liệu học tập", style: TextStyle(color: Colors.blueGrey.withOpacity(0.6), fontSize: 16)),
        ],
      ));
    }
    return ListView.builder(
      // QUAN TRỌNG: Để bottom: 150 để không bị thanh menu dưới che mất nội dung cuối
      padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 150),
      physics: const BouncingScrollPhysics(),
      itemCount: gradeData.length,
      itemBuilder: (context, index) {
        final item = gradeData[index];
        final String rawInfo = item['NoiDung'] ?? "";
        
        // --- LOGIC TÁCH DỮ LIỆU TỪ JSON BACKEND ---
        String getVal(String key) {
		  // Dùng split('|') để tách các cặp "Key: Value"
		  final parts = rawInfo.split('|');
		  for (var p in parts) {
			if (p.contains(key)) {
			  final valuePart = p.split(':');
			  if (valuePart.length > 1) return valuePart[1].trim();
			}
		  }
		  return "---";
		}

        final cc = getVal("CC");
		final gk = getVal("GK");
		final thi = getVal("Thi");
		final he4 = getVal("Hệ 4");
		
        
        // Lấy điểm hệ 10 và điểm chữ từ chuỗi "Tổng kết: 8.5 (A)"
        final String summary = item['NgayThi'] ?? "";
        final he10Match = RegExp(r'Tổng kết:\s*([\d\.]+)').firstMatch(summary);
        final letterMatch = RegExp(r'\(([A-F\+\s]+)\)').firstMatch(summary);
        
        final he10 = he10Match?.group(1) ?? "---";
        final letter = letterMatch?.group(1) ?? "?";
        final tinChi = getVal("Tín chỉ"); // Backend gửi số tín chỉ trong nội dung luôn

        final Color statusColor = _getGradeColor(letter);

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 6, color: statusColor.withOpacity(0.6)),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: vinhUniBlue.withOpacity(0.03),
                          child: Row(
                            children: [
                              Icon(Icons.bookmark_outline_rounded, size: 20, color: vinhUniBlue),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item['TenHocPhan'] ?? "",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2D3142)),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: vinhUniBlue, borderRadius: BorderRadius.circular(10)),
                                child: Text("TC: $tinChi", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
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
                                  _scoreItem("Chuyên cần", cc, Icons.edit_note_rounded),
                                  _scoreItem("Giữa kỳ", gk, Icons.pending_actions_rounded),
                                  _scoreItem("Cuối kỳ", thi, Icons.assignment_turned_in_rounded, isBlue: true),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _richTextRow("Hệ 10:", he10, vinhUniBlue),
                                      const SizedBox(height: 4),
                                      _richTextRow("Hệ 4:", he4, Colors.green.shade600),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: statusColor.withOpacity(0.2))
                                    ),
                                    child: Column(
                                      children: [
                                        Text(letter, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: statusColor, height: 1)),
                                        Text("Điểm chữ", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor.withOpacity(0.7))),
                                      ],
                                    ),
                                  )
                                ],
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

  Widget _richTextRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _scoreItem(String label, String value, IconData icon, {bool isBlue = false}) {
    return Column(
      children: [
        Icon(icon, size: 18, color: isBlue ? vinhUniBlue : Colors.blueGrey.withOpacity(0.4)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isBlue ? vinhUniBlue : const Color(0xFF2D3142))),
      ],
    );
  }

  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.cloud_off_rounded, size: 60, color: Colors.redAccent),
    const SizedBox(height: 10),
    Text(errorMessage ?? "Lỗi không xác định", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500)),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _initData, child: const Text("Tải lại trang"))
  ]));
}