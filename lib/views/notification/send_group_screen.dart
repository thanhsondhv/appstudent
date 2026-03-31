import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart';

class SendGroupScreen extends StatefulWidget {
  final String? initialScope; 
  const SendGroupScreen({super.key, this.initialScope});

  @override
  State<SendGroupScreen> createState() => _SendGroupScreenState();
}

class _SendGroupScreenState extends State<SendGroupScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _thresholdController = TextEditingController(text: "20");
  final _imageUrlController = TextEditingController();

  String _selectedScope = "LHP";
  String _selectedCategory = "GENERAL";
  String _senderId = "";
  String _userRole = "canbo"; 
  bool _isLoading = false, _isClassLoading = false, _isSearching = false;

  // Data bộ lọc chung (Năm, Kỳ)
  List<dynamic> _filters = [];
  List<String> _years = [], _semesters = [];
  String? _selectedYear, _selectedSemester, _selectedClass;
  List<dynamic> _classList = [];

  // Data Lớp Hành Chính cũ (Cố vấn)
  List<dynamic> _adminClassFullList = [];
  List<String> _adminCourses = [];
  String? _selectedAdminCourse, _selectedAdminClassId;
  List<dynamic> _filteredAdminClasses = [];

  // Data 2 API MỚI: LỚP THUỘC KHOA QUẢN LÝ
  List<dynamic> _assignedClasses = []; 
  String? _selectedAssignedClassName;

  // Data Khoa & Khóa
  List<dynamic> _faculties = [];
  String? _selectedFaculty, _selectedCohort;
  final List<String> _cohortList = ["61", "62", "63", "64", "65", "66", "67"];

  // Data Lớp ít SV
  List<dynamic> _lowEnrollmentClasses = [];
  List<dynamic> _allLowStudents = []; 
  Set<String> _selectedMultiClassIds = {}; 

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('user_code') ?? ""; // Lấy mã cán bộ trước
    
    setState(() { 
      _senderId = code; 
      _userRole = (prefs.getString('user_role') ?? "canbo").toLowerCase();
      if (widget.initialScope != null) _selectedScope = widget.initialScope!;
    });

    // Truyền trực tiếp 'code' vào các hàm để đảm bảo không bị rỗng do độ trễ setState
    _loadAllFilters(code);
    _fetchFaculties(); 
    _fetchAdminClasses(code); 
    _fetchAssignedClasses(code); 
  }

  List<String> _getAvailableScopes() {
    if (_userRole == 'admin' || _userRole == 'ad') {
      return ["LHP", "LOP_HC", "ASSIGNED_CLASSES", "LHP_LOW", "DEPT_COHORT"];
    } else if (_userRole == 'covan') {
      return ["LHP", "LOP_HC", "ASSIGNED_CLASSES", "LHP_LOW","DEPT_COHORT"];
    }
    return ["LHP"];
  }

  // =========================================================
  // 📡 PHẦN API LOGIC
  // =========================================================

  Future<void> _loadAllFilters(String code) async {
    if (code.isEmpty) return;
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/get-filters/$code"));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        setState(() {
          _filters = data;
          _years = data.map((e) => e['nam'].toString()).toSet().toList()..sort((a, b) => b.compareTo(a));
        });
      }
    } catch (e) { debugPrint("Lỗi load filters: $e"); }
  }

  Future<void> _fetchAssignedClasses(String code) async {
    if (code.isEmpty) return;
    setState(() => _isClassLoading = true);
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/assigned-classes?lecturer_id=$code"));
      if (res.statusCode == 200) {
        setState(() => _assignedClasses = jsonDecode(res.body)['data'] ?? []);
      }
    } finally { setState(() => _isClassLoading = false); }
  }

  Future<void> _fetchAdminClasses(String code) async {
    if (code.isEmpty) return;
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/admin-classes/$code"));
      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        setState(() {
          _adminClassFullList = result['data'];
          _adminCourses = _adminClassFullList.map((e) => e['khoa'].toString()).toSet().toList()..sort((a, b) => b.compareTo(a));
        });
      }
    } catch (e) {}
  }

  Future<void> _fetchClasses() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() => _isClassLoading = true);
    final url = "https://mobi.vinhuni.edu.vn/api/lecturer/classes-filtered?lecturer_id=$_senderId&nam=$_selectedYear&ky=${Uri.encodeComponent(_selectedSemester!)}";
    try {
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') setState(() { _classList = data['data']; _selectedClass = null; });
    } finally { setState(() => _isClassLoading = false); }
  }

  // --- CÁC HÀM XỬ LÝ MODAL & SEND (GIỮ NGUYÊN) ---
  void _showAssignedClassDetails(String tenLop) async {
    showDialog(context: context, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/class-details?ten_lop=${Uri.encodeComponent(tenLop)}"));
      Navigator.pop(context);
      if (res.statusCode == 200) {
        final List<dynamic> students = jsonDecode(res.body)['data'] ?? [];
        _showStudentDetailModal(tenLop, students);
      }
    } catch (e) { Navigator.pop(context); }
  }

  void _showStudentDetailModal(String title, List<dynamic> students) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, expand: false,
        builder: (c, scroll) => Column(children: [
          Padding(padding: const EdgeInsets.all(15), child: Text("CHI TIẾT SINH VIÊN LỚP $title", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0054A6)))),
          Expanded(child: ListView.builder(
            controller: scroll, itemCount: students.length,
            itemBuilder: (ctx, i) => ListTile(
              leading: CircleAvatar(child: Text("${i+1}", style: const TextStyle(fontSize: 10))),
              title: Text(students[i]['ho_ten'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text("${students[i]['ma_sv']} - ${students[i]['trang_thai']}"),
            ),
          ))
        ]),
      ),
    );
  }

  Future<void> _fetchFaculties() async {
  // Lấy lại code từ SharedPreferences nếu biến truyền vào bị rỗng
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString('user_code') ?? "";
  
  if (code.isEmpty) return;

  try {
    // 🔥 Sửa link: Thêm /$code vào cuối để khớp với API Path Parameter
    final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/get-faculties/$code"));
    if (res.statusCode == 200) {
      // Backend trả về: {"status": "success", "data": {"id_khoa": "...", "ten_khoa": "..."}}
      // Vì data trả về là 1 Object chứ không phải List, Sơn bọc nó lại thành List để Dropdown đọc được
      final result = jsonDecode(res.body)['data'];
      setState(() => _faculties = [result]); 
    }
  } catch (e) {
    debugPrint("Lỗi fetch faculties: $e");
  }
}
List<String> _classesInCohort = [];
String? _selectedClassInCohort; // Giá trị "ALL" hoặc tên lớp

Future<void> _fetchClassesByCohort() async {
  if (_selectedFaculty == null || _selectedCohort == null) return;
  setState(() => _isClassLoading = true);
  try {
    final res = await http.get(Uri.parse(
        "https://mobi.vinhuni.edu.vn/api/admin/get-classes-by-cohort?id_khoa=$_selectedFaculty&cohort=$_selectedCohort"));
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body)['data'] ?? [];
      setState(() {
        _classesInCohort = ["ALL", ...data.map((e) => e.toString())];
        _selectedClassInCohort = "ALL"; // Mặc định là chọn tất cả
      });
    }
  } finally {
    setState(() => _isClassLoading = false);
  }
}
  Future<void> _searchLowEnrollmentData() async {
    if (_selectedYear == null || _selectedSemester == null) {
      NotificationHelper.showSnack(context, "Vui lòng chọn Năm và Kỳ học!", Colors.orange); return;
    }
    setState(() => _isSearching = true);
    final queryParams = "nam=$_selectedYear&ky=${Uri.encodeComponent(_selectedSemester!)}&threshold=${_thresholdController.text}";
    try {
      final resClasses = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/low-enrollment-theory-classes?$queryParams"));
      final resStudents = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/low-enrollment-students?$queryParams"));
      if (resClasses.statusCode == 200 && resStudents.statusCode == 200) {
        setState(() {
          _lowEnrollmentClasses = jsonDecode(resClasses.body)['data'] ?? [];
          _allLowStudents = jsonDecode(resStudents.body)['data'] ?? [];
          _selectedMultiClassIds.clear();
        });
      }
    } finally { setState(() => _isSearching = false); }
  }

  Future<void> _handleSend() async {
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      NotificationHelper.showSnack(context, "Vui lòng nhập nội dung!", Colors.orange); return;
    }
    String target = ""; String apiUrl = "";
    if (_selectedScope == "LHP") { target = _selectedClass ?? ""; apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-lhp'; } 
    else if (_selectedScope == "LOP_HC") { target = _selectedAdminClassId ?? ""; apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-lophc'; } 
    else if (_selectedScope == "ASSIGNED_CLASSES") { target = _selectedAssignedClassName ?? ""; apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-lophc'; }
    else if (_selectedScope == "LHP_LOW") { target = _selectedMultiClassIds.join(","); apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-multi-lhp-theory'; } 
    else if (_selectedScope == "DEPT_COHORT") { target = "${_selectedFaculty}|K${_selectedCohort}"; apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-dept-cohort'; }

    if (target.isEmpty) { NotificationHelper.showSnack(context, "Vui lòng chọn đối tượng!", Colors.red); return; }
    setState(() => _isLoading = true);
    try {
      final body = { "sender_id": _senderId, "scope": _selectedScope, "target_id": target, "title": _titleController.text.trim(), "content": _contentController.text.trim(), "image_url": _imageUrlController.text.trim() };
      final res = await http.post(Uri.parse(apiUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      if (res.statusCode == 200) { NotificationHelper.showSnack(context, "Gửi thành công!", Colors.green); Navigator.pop(context); }
    } catch (e) { NotificationHelper.showSnack(context, "Lỗi kết nối", Colors.red); }
    finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("GỬI TIN TẬP THỂ",
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0054A6),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NotificationHelper.buildLabel("Phạm vi gửi tin"),
            NotificationHelper.buildDropdown(
              hint: "Chọn phạm vi",
              items: _getAvailableScopes(),
              value: _selectedScope,
              onChanged: (v) => setState(() {
                _selectedScope = v!;
                _selectedYear = null;
                _selectedSemester = null;
                _selectedClass = null;
                _selectedFaculty = null;
                _selectedCohort = null;
                _selectedClassInCohort = null;
                _classesInCohort = [];
              }),
              displayFunc: (id) => {
                'LHP': 'Lớp học phần (Giảng dạy)',
                'LOP_HC': 'Lớp hành chính (Cố vấn)',
                'ASSIGNED_CLASSES': 'All Lớp hành chính của khoa',
                'LHP_LOW': 'Lớp lý thuyết ít SV',
                'DEPT_COHORT': 'Toàn Khoa theo Khóa'
              }[id]!,
            ),
            const SizedBox(height: 20),

            // --- 1. UI CHO LỚP HP / LỚP ÍT SV ---
            if (_selectedScope == "LHP" || _selectedScope == "LHP_LOW") ...[
              Row(children: [
                Expanded(
                    child: NotificationHelper.buildDropdown(
                        hint: "Năm học",
                        items: _years,
                        value: _selectedYear,
                        onChanged: (v) {
                          setState(() {
                            _selectedYear = v;
                            _selectedSemester = null;
                            _selectedClass = null;
                            _classList = [];
                            _semesters = _filters
                                .where((e) => e['nam'].toString() == v)
                                .map((e) => e['ky'].toString())
                                .toSet()
                                .toList();
                          });
                        })),
                const SizedBox(width: 10),
                Expanded(
                    child: NotificationHelper.buildDropdown(
                        hint: "Học kỳ",
                        items: _semesters,
                        value: _selectedSemester,
                        onChanged: (v) {
                          setState(() {
                            _selectedSemester = v;
                            _selectedClass = null;
                          });
                          if (_selectedScope == "LHP") _fetchClasses();
                        })),
              ]),
              const SizedBox(height: 12),
              if (_selectedScope == "LHP") ...[
                if (_isClassLoading)
                  const LinearProgressIndicator()
                else
                  NotificationHelper.buildDropdown(
                      hint: "Chọn lớp HP",
                      items: _classList.map((e) => e['ma_lop'].toString()).toList(),
                      value: _selectedClass,
                      onChanged: (v) => setState(() => _selectedClass = v),
                      displayFunc: (id) => _classList
                          .firstWhere((e) => e['ma_lop'] == id)['ten_lop']),
              ]
            ],

            // --- 2. UI CHO LỚP THUỘC KHOA QUẢN LÝ ---
            if (_selectedScope == "ASSIGNED_CLASSES") ...[
              NotificationHelper.buildLabel("Chọn lớp hành chính thuộc khoa"),
              if (_isClassLoading)
                const LinearProgressIndicator()
              else
                NotificationHelper.buildDropdown(
                  hint: "Danh sách lớp thuộc Khoa",
                  items: _assignedClasses
                      .map((e) => e['ten_lop'].toString())
                      .toList(),
                  value: _selectedAssignedClassName,
                  onChanged: (v) => setState(() => _selectedAssignedClassName = v),
                  displayFunc: (tenLop) {
                    final item = _assignedClasses
                        .firstWhere((e) => e['ten_lop'] == tenLop);
                    return "$tenLop (${item['dang_hoc']} SV đang học)";
                  },
                ),
              if (_selectedAssignedClassName != null)
                TextButton.icon(
                    onPressed: () =>
                        _showAssignedClassDetails(_selectedAssignedClassName!),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text("Xem danh sách sinh viên lớp này",
                        style: TextStyle(fontSize: 12))),
            ],

            // --- 3. UI CHO LỚP HÀNH CHÍNH (CỐ VẤN) ---
            if (_selectedScope == "LOP_HC") ...[
              NotificationHelper.buildDropdown(
                  hint: "Chọn khóa",
                  items: _adminCourses,
                  value: _selectedAdminCourse,
                  onChanged: (v) {
                    setState(() {
                      _selectedAdminCourse = v;
                      _filteredAdminClasses = _adminClassFullList
                          .where((e) => e['khoa'] == v)
                          .toList();
                      _selectedAdminClassId = null;
                    });
                  }),
              const SizedBox(height: 12),
              NotificationHelper.buildDropdown(
                  hint: "Chọn lớp HC",
                  items: _filteredAdminClasses
                      .map((e) => e['id'].toString())
                      .toList(),
                  value: _selectedAdminClassId,
                  onChanged: (v) => setState(() => _selectedAdminClassId = v),
                  displayFunc: (id) => _filteredAdminClasses
                      .firstWhere((e) => e['id'].toString() == id)['ten']),
            ],

            // --- 4. 🔥 UI MỚI: TOÀN KHOA THEO KHÓA & LỚP ---
            if (_selectedScope == "DEPT_COHORT") ...[
              NotificationHelper.buildLabel("Chọn Khoa và Khóa quản lý"),
              NotificationHelper.buildDropdown(
                hint: "Chọn Khoa",
                items: _faculties.map((e) => e['id_khoa'].toString()).toList(),
                value: _selectedFaculty,
                onChanged: (v) => setState(() => _selectedFaculty = v),
                displayFunc: (id) => _faculties
                    .firstWhere((e) => e['id_khoa'] == id)['ten_khoa'],
              ),
              const SizedBox(height: 12),
              NotificationHelper.buildDropdown(
                hint: "Chọn Khóa",
                items: _cohortList,
                value: _selectedCohort,
                onChanged: (v) {
                  setState(() {
                    _selectedCohort = v;
                    _selectedClassInCohort = null;
                  });
                  _fetchClassesByCohort(); // Gọi API lấy lớp khi chọn xong Khóa
                },
                displayFunc: (id) => "Khóa $id (K$id)",
              ),
              const SizedBox(height: 12),
              if (_isClassLoading)
                const LinearProgressIndicator()
              else if (_classesInCohort.isNotEmpty)
                NotificationHelper.buildDropdown(
                  hint: "Chọn Lớp (hoặc Tất cả)",
                  items: _classesInCohort,
                  value: _selectedClassInCohort,
                  onChanged: (v) => setState(() => _selectedClassInCohort = v),
                  displayFunc: (val) => val == "ALL"
                      ? "--- GỬI TẤT CẢ KHÓA $_selectedCohort ---"
                      : "Lớp $val",
                ),
            ],

            // --- 5. UI LỚP LÝ THUYẾT ÍT SINH VIÊN ---
            if (_selectedScope == "LHP_LOW") ...[
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _thresholdController,
                        keyboardType: TextInputType.number,
                        decoration: NotificationHelper.inputDecor(
                            "Sĩ số < X", Icons.person_search))),
                const SizedBox(width: 10),
                ElevatedButton(
                    onPressed: _searchLowEnrollmentData,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                    child: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text("TÌM LỚP",
                            style: TextStyle(color: Colors.white))),
              ]),
              const SizedBox(height: 15),
              if (_lowEnrollmentClasses.isNotEmpty) ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _lowEnrollmentClasses.length,
                      itemBuilder: (ctx, idx) {
                        final item = _lowEnrollmentClasses[idx];
                        return CheckboxListTile(
                            title: Text(item['ten_lop'],
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: Text("SS: ${item['si_so']}"),
                            value: _selectedMultiClassIds
                                .contains(item['ma_lop'].toString()),
                            onChanged: (v) => setState(() => v!
                                ? _selectedMultiClassIds
                                    .add(item['ma_lop'].toString())
                                : _selectedMultiClassIds
                                    .remove(item['ma_lop'].toString())));
                      }),
                ),
              ],
            ],

            const Divider(height: 40),
            
            // --- PHẦN NHẬP NỘI DUNG CHUNG ---
            TextField(
                controller: _titleController,
                decoration: NotificationHelper.inputDecor("Tiêu đề", Icons.title)),
            const SizedBox(height: 12),
            TextField(
                controller: _contentController,
                maxLines: 3,
                decoration:
                    NotificationHelper.inputDecor("Nội dung...", Icons.message)),
            const SizedBox(height: 12),
            TextField(
                controller: _imageUrlController,
                decoration: NotificationHelper.inputDecor(
                    "Link ảnh minh họa", Icons.image_outlined),
                onChanged: (v) => setState(() {})),
            if (_imageUrlController.text.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.all(10),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(_imageUrlController.text,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const SizedBox()))),

            const SizedBox(height: 30),
            SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSend,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0054A6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("XÁC NHẬN GỬI TIN",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
  }
} 