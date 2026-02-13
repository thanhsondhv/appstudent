import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/thoikhoabieu.dart';

class ThoiKhoaBieuScreen extends StatefulWidget {
  const ThoiKhoaBieuScreen({super.key});
  @override
  State<ThoiKhoaBieuScreen> createState() => _ThoiKhoaBieuScreenState();
}

class _ThoiKhoaBieuScreenState extends State<ThoiKhoaBieuScreen> {
  final ScheduleService _service = ScheduleService();
  final Color vinhUniBlue = const Color(0xFF0054A6);

  List<dynamic> rawFilterData = []; // Dữ liệu gốc từ API
  List<dynamic> scheduleData = [];
  bool isLoading = true;
  String? errorMessage;

  // Danh sách hiển thị trên ComboBox
  List<String> listNamHoc = [];
  List<String> listHocKy = [];
  List<String> listTuan = [];

  String selectedNamHoc = "";
  String selectedHocKy = "";
  String selectedTuan = "";

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

      // 1. Lấy dữ liệu Filter thô
      rawFilterData = await _service.getRawFilters(userId);

      if (rawFilterData.isNotEmpty) {
        // Lấy danh sách Năm học duy nhất
        listNamHoc = rawFilterData.map((e) => e['nam'].toString()).toSet().toList();
        listNamHoc.sort((a, b) => b.compareTo(a));
        selectedNamHoc = listNamHoc.first;

        // Cập nhật Học kỳ và Tuần theo Năm học đầu tiên
        _updateFilters(updateNam: true);

        // 2. Tải lịch học mặc định
        await _fetchSchedule(userId);
      } else {
        setState(() { errorMessage = "Không có dữ liệu lịch học."; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi kết nối!"; isLoading = false; });
    }
  }

  // LOGIC REALTIME: Cập nhật các danh sách con dựa trên lựa chọn
  void _updateFilters({bool updateNam = false, bool updateKy = false}) {
    setState(() {
      if (updateNam) {
        // Lấy Học kỳ thuộc Năm học đang chọn
        listHocKy = rawFilterData
            .where((e) => e['nam'].toString() == selectedNamHoc)
            .map((e) => e['ky'].toString()).toSet().toList();
        listHocKy.sort();
        selectedHocKy = listHocKy.first;
      }

      // Lấy Tuần thuộc Năm học và Học kỳ đang chọn
      listTuan = rawFilterData
          .where((e) => e['nam'].toString() == selectedNamHoc && e['ky'].toString() == selectedHocKy)
          .map((e) => e['tuan'].toString()).toSet().toList();

      // Sắp xếp tuần theo số
      List<int> intTuans = listTuan.map((e) => int.parse(e)).toList();
      intTuans.sort();
      listTuan = intTuans.map((e) => e.toString()).toList();

      selectedTuan = listTuan.first;
    });
  }

  Future<void> _fetchSchedule(String userId) async {
    setState(() => isLoading = true);
    final data = await _service.getSchedule(
      userId: userId, namHoc: selectedNamHoc, hocKy: selectedHocKy, tuan: selectedTuan,
    );
    setState(() { scheduleData = data; isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text("Thời Khóa Biểu", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: vinhUniBlue, centerTitle: true,
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
          Row(
            children: [
              // Combo Năm học
              Expanded(child: _buildDropdown("Năm học", selectedNamHoc, listNamHoc, (val) {
                selectedNamHoc = val!;
                _updateFilters(updateNam: true); // Cập nhật kỳ và tuần ngay lập tức
              })),
              const SizedBox(width: 12),
              // Combo Học kỳ
              Expanded(child: _buildDropdown("Học kỳ", selectedHocKy, listHocKy, (val) {
                selectedHocKy = val!;
                _updateFilters(); // Cập nhật tuần ngay lập tức
              })),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Combo Tuần học
              Expanded(
                flex: 2,
                child: _buildDropdown("Tuần học", selectedTuan, listTuan, (val) => setState(() => selectedTuan = val!), prefixIcon: Icons.calendar_view_week_rounded),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    _fetchSchedule(prefs.getString('user_id')!);
                  },
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
      isExpanded: true,
      menuMaxHeight: 300,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: vinhUniBlue),
        filled: true, fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      padding: const EdgeInsets.all(16),
      itemCount: scheduleData.length,
      itemBuilder: (context, index) {
        final item = scheduleData[index];
        String rawNoiDung = item['NoiDung'].toString()
            .replaceAll('<b>', '').replaceAll('</b>', '').replaceAll('<br>', '\n')
            .replaceAll('📍 ', '').replaceAll('⏰ ', '').replaceAll('📅 ', '');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
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
      Text(errorMessage ?? "Lỗi"),
      ElevatedButton(onPressed: _initData, child: const Text("Thử lại"))
    ]));
  }
}