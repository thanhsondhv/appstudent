import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

      // 1. Lấy filters thô
      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        listNamHoc = rawFilterData.map((e) => e['nam'].toString()).toSet().toList();
        listNamHoc.sort((a, b) => b.compareTo(a));
        selectedNamHoc = listNamHoc.first;

        // 2. Cập nhật kỳ tương ứng với năm đầu tiên
        _updateKys();

        // 3. Tải lịch thi lần đầu
        await _fetchExams(userId);
      } else {
        setState(() { errorMessage = "Không tìm thấy dữ liệu lọc."; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi kết nối máy chủ!"; isLoading = false; });
    }
  }

  // Logic Realtime: Lọc Học kỳ dựa trên Năm đang chọn
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

  Future<void> _fetchExams(String userId) async {
    setState(() => isLoading = true);
    try {
      final exams = await _service.getExams(
          userId: userId,
          namHoc: selectedNamHoc,
          hocKy: selectedHocKy
      );
      setState(() {
        examData = exams;
        isLoading = false;
      });
    } catch (e) {
      setState(() { errorMessage = "Lỗi tải lịch thi!"; isLoading = false; });
    }
  }

  // --- CÁC HÀM PHỤ TRỢ XỬ LÝ DỮ LIỆU ---
  
  String _extractFromHtml(String html, String label) {
    if (html.isEmpty) return "---";
    final RegExp regExp = RegExp('$label:</b>\\s*(?:<span[^>]*>)?([^<]+)');
    final match = regExp.firstMatch(html);
    return match != null ? match.group(1)!.trim().replaceAll('&nbsp;', ' ') : "---";
  }

  String _formatCaThi(String caThiRaw) {
    if (caThiRaw == "---" || caThiRaw.isEmpty) return "---";
    // Xử lý nếu chuỗi là dạng "1 (Bắt đầu: 07:00)"
    final RegExp timeReg = RegExp(r'(\d+)\s*\(Bắt đầu:\s*(\d{2}:\d{2})');
    final match = timeReg.firstMatch(caThiRaw);
    if (match != null) return "Ca ${match.group(1)} (${match.group(2)})";
    
    // Xử lý nếu chuỗi là dạng giờ "07:00:00" -> lấy "07:00"
    if (caThiRaw.contains(':') && caThiRaw.length >= 5) {
       return caThiRaw.substring(0, 5);
    }
    return caThiRaw;
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
          Row(
            children: [
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (v) {
                selectedNamHoc = v!;
                _updateKys(); // Realtime update
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

  // --- PHẦN DANH SÁCH LỊCH THI (ĐÃ SỬA LỖI INT/STRING) ---
  Widget _buildExamList() {
    if (examData.isEmpty) return _buildEmptyView();
    
    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      physics: const BouncingScrollPhysics(),
      itemCount: examData.length,
      itemBuilder: (context, index) {
        final item = examData[index];
        
        // 1. Lấy chuỗi HTML cũ (fallback)
        final String html = item['NoiDung'] ?? "";
        
        // 2. SỬA LỖI: Dùng ?.toString() để ép kiểu số thành chuỗi an toàn
        // Ưu tiên lấy từ key mới (backend mới), nếu null thì lấy từ HTML (backend cũ)
        final String phong = item['Phong']?.toString() ?? _extractFromHtml(html, "Phòng thi");
        final String caThiRaw = item['Gio']?.toString() ?? _extractFromHtml(html, "Ca thi"); 
        final String sbd = item['SBD']?.toString() ?? _extractFromHtml(html, "Số báo danh");
        
        // 3. Xử lý ngày thi
        final String ngayThi = item['NgayThi']?.replaceAll('Ngày thi: ', '') ?? "---";

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 5)
              )
            ],
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
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 18, color: vinhUniBlue),
                                  const SizedBox(width: 10),
                                  Text(ngayThi, style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 15)),
                                ],
                              ),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, thickness: 0.5)),
                              
                              // Hàng 3 thông tin quan trọng
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _infoBox("Phòng", phong, Icons.location_on_rounded, Colors.blueGrey),
                                  _infoBox("Thời gian", _formatCaThi(caThiRaw), Icons.access_time_filled_rounded, Colors.orange),
                                  _infoBox("SBD", sbd, Icons.badge_rounded, Colors.teal),
                                ],
                              ),
                              
                              const SizedBox(height: 15),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: examAccent),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text("Lưu ý: Mang theo thẻ SV/CCCD để vào phòng thi.", style: TextStyle(fontSize: 10.5, color: examAccent, fontWeight: FontWeight.bold))),
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
       _initData(); // Gọi lại hàm lấy dữ liệu
    }, child: const Text("Thử lại"))
  ]));
}