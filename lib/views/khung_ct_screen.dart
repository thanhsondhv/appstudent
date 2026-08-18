import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/api/api.dart';

class KhungCTScreen extends StatefulWidget {
  const KhungCTScreen({super.key});

  @override
  State<KhungCTScreen> createState() => _KhungCTScreenState();
}

class _KhungCTScreenState extends State<KhungCTScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  bool isLoading = true;
  String? errorMessage;
  
  String selectedProgramId = ""; 
  String currentUserId = "";
  
  // 🔥 Biến trạng thái cho Combobox: Phân loại môn
  String selectedCourseType = "ALL"; 
  final List<Map<String, String>> courseTypes = [
    {"id": "ALL", "name": "Tất cả loại môn"},
    {"id": "Bắt buộc", "name": "Môn bắt buộc"},
    {"id": "Tự chọn", "name": "Môn tự chọn"},
  ];

  // 🔥 Biến trạng thái cho Combobox: Đã học / Chưa học
  String selectedStatus = "ALL"; 
  final List<Map<String, String>> statusTypes = [
    {"id": "ALL", "name": "Tất cả trạng thái"},
    {"id": "Đã học", "name": "Môn đã học"},
    {"id": "Chưa học", "name": "Môn chưa học"},
  ];

  List<Map<String, dynamic>> programList = [];
  List<dynamic> curriculumData = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id'); 

      if (userId == null || userId.isEmpty) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }
      currentUserId = userId; 

      await _fetchPrograms(currentUserId);
      
      if (programList.isNotEmpty) {
         selectedProgramId = programList.first["program_id"].toString();
         await _fetchCurriculum(selectedProgramId);
      } else {
         setState(() { errorMessage = "Không tìm thấy chương trình đào tạo."; isLoading = false; });
      }

    } catch (e) {
      setState(() { errorMessage = "Lỗi khởi tạo dữ liệu!"; isLoading = false; });
    }
  }

  Future<void> _fetchPrograms(String userId) async {
    try {
      final response = await Api.get('/api/student-programs/$userId');

      if (response.thanhCong) {
        final List<dynamic> data = response.data is List ? response.data as List : const [];
        setState(() {
          programList = data.map((e) => {
            "program_id": e["program_id"].toString(),
            "program_name": e["program_name"].toString()
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách ngành: $e");
      throw Exception("Lỗi mạng");
    }
  }

  Future<void> _fetchCurriculum(String programId) async {
    setState(() => isLoading = true);
    try {
      final response = await Api.get(
        '/api/curriculum-progress/$programId',
        thamSo: {'student_id': currentUserId},
      );
      if (response.thanhCong) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          curriculumData = data;
          isLoading = false;
        });
      } else {
        setState(() { curriculumData = []; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi tải khung chương trình!"; isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: const Text("KHUNG CHƯƠNG TRÌNH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null
                ? _buildErrorView()
                : _buildCurriculumList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    if (programList.isEmpty) return const SizedBox();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Chương trình đào tạo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          _buildDropdownContainer(
            value: selectedProgramId.isNotEmpty ? selectedProgramId : null,
            icon: Icons.school_rounded,
            items: programList.map((p) => DropdownMenuItem(
              value: p["program_id"] as String, 
              child: Text(p["program_name"], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87), overflow: TextOverflow.ellipsis)
            )).toList(),
            onChanged: (val) {
              if (val != null && val != selectedProgramId) {
                setState(() => selectedProgramId = val);
                _fetchCurriculum(val);
              }
            }
          ),
          
          const SizedBox(height: 12),
          
          // 🔥 2 COMBOBOX LỌC CẠNH NHAU
          Row(
            children: [
              // Lọc Phân Loại Môn
              Expanded(
                child: _buildDropdownContainer(
                  value: selectedCourseType,
                  icon: Icons.filter_list_rounded,
                  isLight: true,
                  items: courseTypes.map((t) => DropdownMenuItem(
                    value: t["id"], 
                    child: Text(t["name"]!, style: TextStyle(fontSize: 13, fontWeight: selectedCourseType == t["id"] ? FontWeight.bold : FontWeight.w500, color: selectedCourseType == t["id"] ? vinhUniBlue : Colors.black87))
                  )).toList(),
                  onChanged: (val) { if (val != null) setState(() => selectedCourseType = val); }
                ),
              ),
              const SizedBox(width: 10),
              // Lọc Đã Học / Chưa Học
              Expanded(
                child: _buildDropdownContainer(
                  value: selectedStatus,
                  icon: Icons.checklist_rounded,
                  isLight: true,
                  items: statusTypes.map((t) => DropdownMenuItem(
                    value: t["id"], 
                    child: Text(t["name"]!, style: TextStyle(fontSize: 13, fontWeight: selectedStatus == t["id"] ? FontWeight.bold : FontWeight.w500, color: selectedStatus == t["id"] ? vinhUniBlue : Colors.black87))
                  )).toList(),
                  onChanged: (val) { if (val != null) setState(() => selectedStatus = val); }
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // Hàm phụ trợ vẽ Combobox cho gọn code
  Widget _buildDropdownContainer({required String? value, required IconData icon, required List<DropdownMenuItem<String>> items, required Function(String?) onChanged, bool isLight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isLight ? Colors.grey.shade50 : vinhUniBlue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isLight ? Colors.grey.shade300 : vinhUniBlue.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          icon: Icon(icon, color: isLight ? Colors.blueGrey.shade400 : vinhUniBlue, size: 20),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCurriculumList() {
    // 🔥 CƠ CHẾ LỌC LOCAL 2 LỚP: Vừa lọc loại môn, vừa lọc trạng thái
    final List<dynamic> displayedList = curriculumData.where((item) {
      final String loaiMon = item['loai_mon'] ?? "Bắt buộc";
      final String trangThai = item['trang_thai'] ?? "Chưa học";

      bool passType = selectedCourseType == "ALL" || loaiMon == selectedCourseType;
      bool passStatus = selectedStatus == "ALL" || trangThai == selectedStatus;

      return passType && passStatus;
    }).toList();

    if (displayedList.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.manage_search_rounded, size: 60, color: vinhUniBlue.withOpacity(0.2)),
        const SizedBox(height: 10),
        const Text("Không có môn học phù hợp", style: TextStyle(color: Colors.grey))
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 100),
      physics: const BouncingScrollPhysics(),
      itemCount: displayedList.length,
      itemBuilder: (context, index) {
        final item = displayedList[index];
        final String status = item['trang_thai'] ?? "Chưa học";
        final bool isDone = status == "Đã học";
        
        final String loaiMon = item['loai_mon'] ?? "Bắt buộc";
        final bool isMandatory = loaiMon == "Bắt buộc";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDone ? Colors.green.shade200 : Colors.grey.shade200, width: isDone ? 1.5 : 1.0),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: isDone ? Colors.green.shade50 : vinhUniBlue.withOpacity(0.05),
              child: Text(
                "${item['stt'] ?? index + 1}", 
                style: TextStyle(
                  color: isDone ? Colors.green.shade700 : vinhUniBlue, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 14
                )
              ),
            ),
            
            title: Text(
              item['ten_mon'] ?? "Tên môn học", 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 14, 
                color: isDone ? Colors.black87 : const Color(0xFF2C3E50)
              )
            ),
            
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _badgeInfo(item['hoc_ky'] ?? "N/A", Colors.orange),
                  const SizedBox(width: 6),
                  _badgeInfo("TC: ${item['tin_chi'] ?? 0}", vinhUniBlue),
                  const SizedBox(width: 6),
                  _badgeInfo(loaiMon, isMandatory ? Colors.redAccent : Colors.teal),
                  
                  const Spacer(),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDone ? Colors.green : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: Row(
                      children: [
                        Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badgeInfo(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline_rounded, size: 50, color: Colors.redAccent),
    const SizedBox(height: 12),
    Text(errorMessage ?? "Lỗi", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _initData, child: const Text("Thử lại"))
  ]));
}