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
  Future<void> _fetchSchedule(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    String cacheKey = 'cache_schedule_${userId}_${selectedNamHoc}_${selectedHocKy}_${selectedTuan}_$selectedProgramId';

    // 1. Lấy Cache (Hiển thị ngay lập tức)
    final String? cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      setState(() {
        scheduleData = json.decode(cachedStr);
        isLoading = false; 
      });
    } else {
      setState(() => isLoading = true); 
    }

    // 2. Gọi API ngầm
    try {
      String nam = selectedNamHoc == "Tất cả" ? "ALL" : selectedNamHoc;
      String ky = selectedHocKy == "Tất cả" ? "ALL" : selectedHocKy;
      String t = selectedTuan;
      
      final url = 'https://mobi.vinhuni.edu.vn/api/get-schedule/$userId?nam_hoc=$nam&hoc_ky=$ky&tuan=$t&program_id=$selectedProgramId';
      
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (json.encode(data) != cachedStr) { // Chỉ cập nhật UI nếu data mới khác cache
          prefs.setString(cacheKey, json.encode(data));
          if(mounted) setState(() { scheduleData = data; isLoading = false; });
        }
      }
    } catch (e) {
      debugPrint("Offline: Dùng cache cho Bảng lịch học");
      if (mounted) {
        if (scheduleData.isEmpty) {
          setState(() { errorMessage = "Đang offline và chưa có dữ liệu ngoại tuyến!"; isLoading = false; });
        } else {
          // Hiện thông báo nhỏ cho biết đang xem offline
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Đang hiển thị dữ liệu ngoại tuyến"), duration: Duration(seconds: 2), backgroundColor: Colors.orange)
          );
        }
      }
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
    if (scheduleData.isEmpty) return const Center(child: Text("Không có lịch học"));
    return ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: scheduleData.length,
      itemBuilder: (context, index) {
        final item = scheduleData[index];
        String rawNoiDung = item['NoiDung'].toString().replaceAll('<b>', '').replaceAll('</b>', '').replaceAll('<br>', '\n').replaceAll('📍 ', '').replaceAll('⏰ ', '').replaceAll('📅 ', '');
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
                          Text(item['TenHocPhan'] ?? "Môn học", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Icon(Icons.calendar_today_rounded, size: 16, color: vinhUniBlue.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Text(item['NgayThi'] ?? "", style: const TextStyle(color: Colors.black54, fontSize: 13)),
                          ]),
                          const Divider(height: 24),
                          Text(rawNoiDung, style: const TextStyle(height: 1.6, fontSize: 13, color: Colors.black54)),
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

  Widget _buildErrorView() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(errorMessage ?? "Lỗi", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _initData, child: const Text("Thử lại"))
    ]));
  }
}