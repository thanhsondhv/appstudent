import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  // 1. LUỒNG INIT DATA (XỬ LÝ OFFLINE FIRST TOÀN DIỆN)
  // =========================================================================
  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');

    if (userId == null || userId.isEmpty) {
      setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
      return;
    }
    currentUserId = userId;

    try {
      // 1. Tải danh sách ngành (Có hỗ trợ Offline)
      await _fetchPrograms(currentUserId);
      
      // 2. Tải danh sách bộ lọc Năm/Kỳ (Có hỗ trợ Offline)
      await _fetchFilters(currentUserId);

      // 3. Nếu có bộ lọc thì cập nhật Combobox và tải Lịch
      if (rawFilterData.isNotEmpty) {
        listNamHoc = rawFilterData.map((e) => e['nam'].toString()).toSet().toList();
        listNamHoc.sort((a, b) => b.compareTo(a));
        selectedNamHoc = listNamHoc.first;

        _updateFilters(updateNam: true);

        // 4. Tải Lịch học (Có hỗ trợ Offline)
        await _fetchSchedule(currentUserId);
      } else {
        setState(() { errorMessage = "Không có dữ liệu bộ lọc."; isLoading = false; });
      }
    } catch (e) {
      // Chỉ báo lỗi nếu không có cả mạng lẫn cache
      if (scheduleData.isEmpty && programList.length == 1) {
        setState(() { errorMessage = "Không có kết nối mạng và chưa có dữ liệu ngoại tuyến!"; isLoading = false; });
      }
    }
  }

  // =========================================================================
  // 2. TẢI COMBOBOX NGÀNH HỌC (CÓ CACHE)
  // =========================================================================
  Future<void> _fetchPrograms(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_programs_$userId';

    // 1. Đọc Cache trước
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null) {
      final List<dynamic> data = json.decode(cachedStr);
      programList = [
        {"program_id": "ALL", "program_name": "Tất cả ngành học"},
        ...data.map((e) => {"program_id": e["program_id"].toString(), "program_name": e["program_name"].toString()})
      ];
    }

    // 2. Gọi API ngầm
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/student-programs/$userId'; 
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body); // Lưu đè cache
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          programList = [
            {"program_id": "ALL", "program_name": "Tất cả ngành học"},
            ...data.map((e) => {"program_id": e["program_id"].toString(), "program_name": e["program_name"].toString()})
          ];
        });
      }
    } catch (e) {
      debugPrint("Offline: Dùng cache cho Combobox Ngành");
      if (programList.length == 1) throw Exception("No network"); // Ném lỗi ra initData nếu không có cache
    }
  }

  // =========================================================================
  // 3. TẢI BỘ LỌC NĂM HỌC / HỌC KỲ (CÓ CACHE)
  // =========================================================================
  Future<void> _fetchFilters(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache_filters_$userId';

    // 1. Đọc Cache
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null) {
      rawFilterData = json.decode(cachedStr);
    }

    // 2. Gọi API ngầm
    try {
      final url = 'https://mobi.vinhuni.edu.vn/api/get-filters/$userId';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
        rawFilterData = json.decode(response.body);
      }
    } catch (e) {
      debugPrint("Offline: Dùng cache cho Combobox Bộ lọc");
      if (rawFilterData.isEmpty) throw Exception("No network");
    }
  }

  // =========================================================================
  // LOGIC CẬP NHẬT COMBOBOX CON KHI CHỌN NĂM/KỲ
  // =========================================================================
  void _updateFilters({bool updateNam = false, bool updateKy = false}) {
    setState(() {
      if (updateNam) {
        listHocKy = rawFilterData.where((e) => e['nam'].toString() == selectedNamHoc).map((e) => e['ky'].toString()).toSet().toList();
        listHocKy.sort();
        if(listHocKy.isNotEmpty) selectedHocKy = listHocKy.first;
      }
      listTuan = rawFilterData.where((e) => e['nam'].toString() == selectedNamHoc && e['ky'].toString() == selectedHocKy).map((e) => e['tuan'].toString()).toSet().toList();
      List<int> intTuans = listTuan.map((e) => int.parse(e)).toList();
      intTuans.sort();
      listTuan = intTuans.map((e) => e.toString()).toList();
      if(listTuan.isNotEmpty) selectedTuan = listTuan.first;
    });
  }

  // =========================================================================
  // 4. TẢI LỊCH HỌC CHÍNH THỨC (CÓ CACHE)
  // =========================================================================
  // Đã sửa FFuture thành Future
Future<void> _fetchSchedule(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  String cacheKey = 'cache_schedule_${userId}_${selectedNamHoc}_${selectedHocKy}_${selectedTuan}_$selectedProgramId';

  // 🔥 BƯỚC QUAN TRỌNG: Tạm thời xóa cache để chắc chắn lấy dữ liệu mới có MaLopHP
  await prefs.remove(cacheKey); 

  setState(() => isLoading = true); 

  try {
    String nam = selectedNamHoc == "Tất cả" ? "ALL" : selectedNamHoc;
    String ky = selectedHocKy == "Tất cả" ? "ALL" : selectedHocKy;
    
    final url = 'https://mobi.vinhuni.edu.vn/api/get-schedule/$userId?nam_hoc=$nam&hoc_ky=$ky&tuan=$selectedTuan&program_id=$selectedProgramId';
    
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      
      // Lưu lại bản cache mới nhất (đã có trường MaLopHP)
      await prefs.setString(cacheKey, json.encode(data));
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        // Bổ sung nút Back thủ công để đảm bảo luôn xuất hiện trên mọi luồng Navigator
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            // Sử dụng maybePop để quay lại an toàn, tránh đóng app đột ngột
            Navigator.of(context).maybePop();
          },
        ),
        title: const Text(
          "Thời Khóa Biểu", 
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)
        ),
        backgroundColor: vinhUniBlue, 
        centerTitle: true,
        elevation: 0, // Làm phẳng AppBar để mượt mà hơn với FilterBar bên dưới
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null
                ? _buildErrorView()
                : _buildList(),
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
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (val) { selectedNamHoc = val!; _updateFilters(updateNam: true); })),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown("Học kỳ", selectedHocKy, listHocKy, (val) { selectedHocKy = val!; _updateFilters(); })),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(flex: 2, child: _buildDropdown("Tuần học", selectedTuan, listTuan, (val) => setState(() => selectedTuan = val!), prefixIcon: Icons.calendar_view_week_rounded)),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _fetchSchedule(currentUserId),
                  style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("Lọc", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
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
        filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: vinhUniBlue) : null,
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(label == "Tuần học" ? "Tuần $e" : e, style: const TextStyle(fontSize: 14)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildList() {
    if (scheduleData.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_rounded, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text("Không có lịch học trong tuần này", style: TextStyle(color: Colors.grey)),
          ],
        )
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scheduleData.length,
      itemBuilder: (context, index) {
        final item = scheduleData[index];
        
        // Làm sạch nội dung text (Xử lý các tag HTML cơ bản)
        String rawNoiDung = item['NoiDung'].toString()
            .replaceAll('<b>', '')
            .replaceAll('</b>', '')
            .replaceAll('<br>', '\n')
            .replaceAll('📍 ', '')
            .replaceAll('⏰ ', '')
            .replaceAll('📅 ', '');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Thanh màu xanh bên trái tạo điểm nhấn
                  Container(width: 5, color: vinhUniBlue),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Tên học phần
                          Text(
                            item['TenHocPhan'] ?? "Môn học",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 2. Thời gian (Ngày tháng)
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 14, color: vinhUniBlue.withOpacity(0.7)),
                              const SizedBox(width: 8),
                              Text(
                                item['NgayThi'] ?? "",
                                style: const TextStyle(color: Colors.black54, fontSize: 13),
                              ),
                            ],
                          ),
                          
                          const Divider(height: 24, thickness: 0.5),

                          // 3. Nội dung chi tiết (Phòng học, Tiết học, Giảng viên)
                          Text(
                            rawNoiDung,
                            style: const TextStyle(
                              height: 1.5,
                              fontSize: 13,
                              color: Color(0xFF475569),
                            ),
                          ),

                          const SizedBox(height: 12),
                          const Divider(height: 1, thickness: 0.5),
                          
                          // 4. 🔥 NÚT XIN NGHỈ / ĐI MUỘN (Tích hợp mới)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _showAttendanceRequestSheet(item),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.orange.shade800,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                              label: const Text(
                                "Xin nghỉ / Đi muộn",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
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
  // Hàm hiển thị thông báo nhanh (SnackBar)
void _showSnack(String message, Color color) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

// Hàm trang trí ô nhập liệu (InputDecoration)
InputDecoration _inputDecor(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 14),
    prefixIcon: Icon(icon, color: vinhUniBlue, size: 20),
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: vinhUniBlue, width: 1.5),
    ),
  );
}
  // --- 1. GIAO DIỆN BOTTOM SHEET XIN PHÉP ---
  void _showAttendanceRequestSheet(dynamic item) {
  // 🚩 Dòng Debug cực kỳ quan trọng để kiểm tra mã lớp
  debugPrint("🔍 Kiểm tra dữ liệu môn học: $item");
  debugPrint("👉 MaLopHP: ${item['MaLopHP']}");

  if (item['MaLopHP'] == null || item['MaLopHP'] == "" || item['MaLopHP'] == "None") {
    _showSnack("Lỗi: Không tìm thấy mã lớp học phần. Vui lòng nhấn 'Lọc' để cập nhật lại lịch!", Colors.red);
    return;
  }

  String selectedType = 'VANG_HOC';
  final TextEditingController reasonCtrl = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true, 
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20, right: 20, top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))
                )
              ),
              const SizedBox(height: 20),
              Text("XIN PHÉP VẮNG / MUỘN", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: vinhUniBlue)),
              const SizedBox(height: 8),
              Text("Môn: ${item['TenHocPhan'] ?? 'Môn học'}", 
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
              const Divider(height: 30),

              // Dropdown chọn loại hình xin phép
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: _inputDecor("Hình thức xin phép", Icons.category_rounded),
                items: const [
                  DropdownMenuItem(value: 'VANG_HOC', child: Text("Vắng học (Cả buổi)")),
                  DropdownMenuItem(value: 'MUON_HOC', child: Text("Đi muộn (Vào sau)")),
                  DropdownMenuItem(value: 'LY_DO_KHAC', child: Text("Lý do khác")),
                ],
                onChanged: (v) {
                  // Cập nhật giao diện bên trong BottomSheet
                  setModalState(() => selectedType = v!);
                },
              ),
              const SizedBox(height: 15),

              // Ô nhập lý do
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: _inputDecor("Nhập lý do chi tiết...", Icons.edit_note_rounded),
              ),
              const SizedBox(height: 25),

              // Nút gửi đơn
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    // Truyền MaLopHP từ item sang hàm gửi
                    _submitAttendanceRequest(item['MaLopHP'], selectedType, reasonCtrl.text);
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text("GỬI ĐƠN XIN PHÉP", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
  // --- 2. LOGIC GỬI ĐƠN LÊN SERVER ---
  Future<void> _submitAttendanceRequest(String? lhpCode, String category, String reason) async {
    if (reason.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng nhập lý do!")));
      return;
    }

    // Hiển thị Loading
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));

    try {
      final body = {
        "student_id": currentUserId,
        "lhp_code": lhpCode, // Mã lớp học phần
        "category": category,
        "reason": reason
      };

      final res = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/student/send-attendance-request"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      Navigator.pop(context); // Tắt Loading

      if (res.statusCode == 200) {
        Navigator.pop(context); // Đóng BottomSheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gửi đơn thành công! Thầy/Cô sẽ nhận được tin nhắn của bạn."), backgroundColor: Colors.green)
        );
      } else {
        throw Exception("Lỗi server");
      }
    } catch (e) {
      Navigator.pop(context); // Tắt Loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không thể gửi đơn, vui lòng thử lại sau!"), backgroundColor: Colors.red));
    }
  }
  Widget _buildErrorView() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(errorMessage ?? "Lỗi", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _initData, child: const Text("Thử lại"))
    ]));
  }
}