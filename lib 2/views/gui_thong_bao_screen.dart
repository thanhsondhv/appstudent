import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// =========================================================
// 1. MODEL DỮ LIỆU TÌM KIẾM
// =========================================================
class UserSearchModel {
  final String id;
  final String name;
  final String info;
  UserSearchModel({required this.id, required this.name, required this.info});
  factory UserSearchModel.fromJson(Map<String, dynamic> json) => UserSearchModel(
    id: json['id'] ?? '', name: json['name'] ?? '', info: json['info'] ?? '',
  );
}

// =========================================================
// 2. MÀN HÌNH CHÍNH: GỬI THÔNG BÁO (3 TAB)
// =========================================================
class GuiThongBaoScreen extends StatefulWidget {
  const GuiThongBaoScreen({super.key});
  @override
  State<GuiThongBaoScreen> createState() => _GuiThongBaoScreenState();
}

class _GuiThongBaoScreenState extends State<GuiThongBaoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _groupTargetController = TextEditingController();
  final _tempBulkController = TextEditingController(); 
  Timer? _debounce;

  String _selectedScope = "LHP";
  String _selectedCategory = "GENERAL"; 
  List<dynamic> _filters = [];
  List<String> _years = [];
  List<String> _semesters = [];
  String? _selectedYear, _selectedSemester, _selectedClass;
  List<dynamic> _classList = [];
  
  List<dynamic> _customGroupList = [];    
  String? _selectedCustomGroup;          
  List<Map<String, dynamic>> _verifiedStudents = []; 

  bool _isLoading = false;
  bool _isClassLoading = false;
  String _senderId = ""; 
  final Color vinhUniBlue = const Color(0xFF0054A6);
  List<dynamic> _adminClassFullList = []; // Toàn bộ lớp HC nhận từ API
  List<String> _adminCourses = [];       // Danh sách Khóa (K61, K62...)
  String? _selectedAdminCourse;         // Khóa đang chọn
  String? _selectedAdminClassId;        // ID Lớp đang chọn (Id từ DB)
  List<dynamic> _filteredAdminClasses = []; // Lớp sau khi lọc theo Khóa
  Future<http.Response>? _historyFuture;
  final List<Map<String, String>> _categories = [
    {'id': 'GENERAL', 'name': 'Thông báo chung'},
    {'id': 'CANH_BAO', 'name': 'Cảnh báo học tập'},
    {'id': 'LICH_DAY', 'name': 'Lịch dạy / Lịch thi'},
    {'id': 'LHP_MSG', 'name': 'Tin nhắn Lớp HP'},
    {'id': 'CV_MSG', 'name': 'Tin nhắn Cố vấn'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadSender();
  }

  Future<void> _loadSender() async {
  final prefs = await SharedPreferences.getInstance();
  String id = prefs.getString('user_code') ?? "";
  
  setState(() {
    _senderId = id;
    // 🔥 Chỉ khởi tạo Future gọi API khi đã có ID chắc chắn
    if (_senderId.isNotEmpty) {
      _historyFuture = http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/sent-history/$_senderId"));
    }
  });
  _loadAllFilters();
  _loadCustomGroups();
}

  // --- HÀM LOGIC ---
  Future<void> _loadAllFilters() async {
    if (_senderId.isEmpty) return;
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/get-filters/$_senderId"));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        setState(() {
          _filters = data;
          _years = data.map((e) => e['nam'].toString()).toSet().toList()..sort((a, b) => b.compareTo(a));
        });
      }
    } catch (e) { debugPrint("Lỗi tải bộ lọc"); }
  }

  Future<void> _loadCustomGroups() async {
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/custom-groups/$_senderId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _customGroupList = data['data']; });
      }
    } catch (e) { debugPrint("Lỗi tải nhóm ảo: $e"); }
  }

  Future<void> _fetchGroupMembers(String groupId) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/custom-group-members/$groupId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (var sv in data['data']) {
          _addStudentToVerified(sv['id'].toString(), sv['name'].toString());
        }
      }
    } catch (e) { debugPrint("Lỗi tải thành viên nhóm: $e"); }
    setState(() => _isLoading = false);
  }

  void _addStudentToVerified(String id, String name) {
    bool isExist = _verifiedStudents.any((e) => e['id'] == id);
    if (!isExist) {
      setState(() { _verifiedStudents.add({'id': id, 'name': name}); });
    }
  }

  Future<void> _verifyMultipleUsers(String input) async {
    if (input.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/check-multiple-users?q=${Uri.encodeComponent(input)}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        for (var sv in data['data']) { _addStudentToVerified(sv['id'].toString(), sv['name'].toString()); }
        _tempBulkController.clear();
      }
    } catch (e) { _showSnack("Lỗi check danh sách", Colors.red); }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchClasses() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() => _isClassLoading = true);
    final ky = Uri.encodeComponent(_selectedSemester!);
    final url = "https://mobi.vinhuni.edu.vn/api/lecturer/classes-filtered?lecturer_id=$_senderId&nam=$_selectedYear&ky=$ky";
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') setState(() { _classList = data['data']; _selectedClass = null; });
    }
    setState(() => _isClassLoading = false);
  }

  Future<void> _handleSend() async {
    // 1. Kiểm tra tính hợp lệ của nội dung
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      _showSnack("Vui lòng nhập đủ nội dung!", Colors.orange);
      return;
    }

    String finalTargetId = "";
    // Xác định scope dựa trên Tab đang chọn (Tab 0: Cá nhân, Tab 1: Tập thể)
    String scope = _tabController.index == 0 ? "INDIVIDUAL" : _selectedScope;
    
    // 🔥 BƯỚC 1: RẼ NHÁNH URL API VÀ TARGET_ID THEO ĐỐI TƯỢNG
    // Khởi tạo URL mặc định là API cá nhân
    String apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-individual';

    if (scope == "INDIVIDUAL") {
      // Gửi cá nhân: Lấy danh sách ID từ mảng sinh viên đã xác minh
      finalTargetId = _verifiedStudents.map((e) => e['id'].toString()).join(",");
      apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-individual';
    } 
    else if (scope == "LHP") {
      // Gửi lớp học phần: Lấy mã lớp (Chuỗi)
      finalTargetId = _selectedClass ?? "";
      apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-lhp';
    } 
    else if (scope == "LOP_HC") {
      // Gửi lớp hành chính: Lấy ID lớp (Số nguyên)
      finalTargetId = _selectedAdminClassId ?? "";
      apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification-lophc';
    } 
    else if (scope == "ALL") {
      finalTargetId = "ALL";
      apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification';
    } 
    else if (scope == "KHOA") {
      // Gửi theo khóa (K61, K62...): Lấy từ ô nhập text
      finalTargetId = _groupTargetController.text.trim();
      apiUrl = 'https://mobi.vinhuni.edu.vn/api/admin/send-notification';
    }

    // Kiểm tra nếu chưa chọn đối tượng nhận tin
    if (finalTargetId.isEmpty && scope != "ALL") {
      _showSnack("Vui lòng chọn ít nhất 1 người nhận!", Colors.red);
      return;
    }

    // 2. Bắt đầu quá trình gửi
    setState(() => _isLoading = true);
    
    try {
      final body = {
        "sender_id": _senderId, 
        "scope": scope, 
        "target_id": finalTargetId,
        "category": _selectedCategory, 
        "title": _titleController.text.trim(),
        "content": _contentController.text.trim(),
      };

      // 🔥 BƯỚC 2: GỌI ĐÚNG ĐỊA CHỈ API ĐÃ RẼ NHÁNH
      final res = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'}, 
        body: jsonEncode(body)
      );

      final result = jsonDecode(res.body);
      
      if (res.statusCode == 200 && result['status'] == 'success') {
        // Thông báo thành công và cung cấp tùy chọn xem báo cáo ngay
        _showSuccessWithReportOption(result['queue_id'] ?? 0);
        
        // Làm sạch giao diện sau khi gửi
        _titleController.clear(); 
        _contentController.clear();
        _groupTargetController.clear();
        setState(() { 
          _verifiedStudents.clear(); 
          _selectedClass = null;
          _selectedAdminClassId = null;
        });
      } else { 
        // Hiển thị lỗi từ Backend (ví dụ: Không tìm thấy sinh viên)
        _showSnack(result['message'] ?? "Gửi thất bại", Colors.red); 
      }
    } catch (e) { 
      debugPrint("Lỗi gửi thông báo: $e");
      _showSnack("Lỗi kết nối Server", Colors.red); 
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSaveGroupDialog() {
    if (_verifiedStudents.isEmpty) {
      _showSnack("Vui lòng chọn SV trước!", Colors.orange); return;
    }
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lưu nhóm ảo mới"),
        content: TextField(controller: nameCtrl, decoration: _inputDecor("Nhập tên nhóm", Icons.label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () { _saveCustomGroup(nameCtrl.text.trim()); Navigator.pop(ctx); },
            style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue),
            child: const Text("Lưu", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _saveCustomGroup(String groupName) async {
    if (groupName.isEmpty) return;
    final body = {
      "group_name": groupName, "sender_id": _senderId,
      "student_ids": _verifiedStudents.map((e) => e['id']).join(","),
    };
    final res = await http.post(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/create-custom-group"),
      headers: {"Content-Type": "application/json"}, body: jsonEncode(body));
    if (res.statusCode == 200) {
      _showSnack("Đã tạo nhóm ảo thành công!", Colors.green);
      _loadCustomGroups();
    }
  }

  void _showSuccessWithReportOption(int qId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text("Thành công")]),
        content: const Text("Thông báo đã được nạp vào hàng đợi. Xem danh sách ngay?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Để sau")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (c) => ThongKeDocTinScreen(queueId: qId, title: "Thống kê")));
            },
            style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue),
            child: const Text("Xem ngay", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  Future<void> _fetchAdminClasses() async {
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/admin-classes/$_senderId"));
      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        if (result['status'] == 'success') {
          setState(() {
            _adminClassFullList = result['data'];
            // Lấy danh sách các Khóa học (IdKhoaHoc) không trùng lặp
            _adminCourses = _adminClassFullList
                .map((e) => e['khoa'].toString())
                .toSet().toList()..sort((a, b) => b.compareTo(a));
          });
        }
      }
    } catch (e) { debugPrint("Lỗi tải lớp hành chính: $e"); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: vinhUniBlue, elevation: 0, toolbarHeight: 45, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("GỬI THÔNG BÁO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController, indicatorColor: Colors.white, indicatorWeight: 3,
          labelColor: Colors.white, unselectedLabelColor: Colors.white.withOpacity(0.7),
          tabs: const [ Tab(text: "CÁ NHÂN"), Tab(text: "TẬP THỂ"), Tab(text: "LỊCH SỬ") ],
        ),
      ),
      body: _tabController.index == 2 
          ? _buildTabHistory() 
          : Column(
              children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _tabController.index == 0 ? _buildTabPersonal() : _buildTabGroup(),
                  const SizedBox(height: 25),
                  _buildLabel("Loại thông báo"),
                  _buildDropdown("Chọn loại tin", _categories.map((e) => e['id']!).toList(), _selectedCategory, (v) => setState(() => _selectedCategory = v!),
                    displayFunc: (id) => _categories.firstWhere((e) => e['id'] == id)['name']!),
                  const SizedBox(height: 15),
                  _buildLabel("Tiêu đề"),
                  TextField(controller: _titleController, decoration: _inputDecor("VD: Thông báo nghỉ...", Icons.title)),
                  const SizedBox(height: 15),
                  _buildLabel("Nội dung"),
                  TextField(controller: _contentController, maxLines: 5, decoration: _inputDecor("Nhập nội dung...", Icons.message_rounded)),
                ]))),
                _buildBottomAction(),
              ],
            ),
    );
  }

  Widget _buildTabPersonal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- PHẦN 1: QUẢN LÝ NHÓM ẢO ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLabel("Chọn từ Nhóm ảo"),
            // 🔥 NÚT BỎ CHỌN: Hiện ra khi đã chọn 1 nhóm
            if (_selectedCustomGroup != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedCustomGroup = null;
                    _verifiedStudents.clear();
                  });
                },
                icon: const Icon(Icons.close, size: 14, color: Colors.red),
                label: const Text("Bỏ chọn", style: TextStyle(color: Colors.red, fontSize: 11)),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                "Chọn nhóm của bạn", 
                _customGroupList.map((e) => e['id'].toString()).toList(), 
                _selectedCustomGroup, 
                (v) {
                  setState(() => _selectedCustomGroup = v);
                  _fetchGroupMembers(v!); 
                },
                displayFunc: (id) => _customGroupList.firstWhere((e) => e['id'].toString() == id)['name'],
              ),
            ),
            // 🔥 CỤM NÚT SỬA & XÓA NHÓM
            if (_selectedCustomGroup != null) ...[
              IconButton(
                onPressed: _showSaveGroupDialog, // Gọi lại dialog để cập nhật tên/thành viên
                icon: const Icon(Icons.edit_note, color: Colors.orange, size: 26),
                tooltip: "Sửa tên nhóm",
              ),
              IconButton(
                onPressed: _deleteGroup, // Hàm xóa nhóm ảo
                icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 24),
                tooltip: "Xóa nhóm này",
              ),
            ]
          ],
        ),

        const SizedBox(height: 15),
        const Divider(thickness: 1, height: 30),

        // --- PHẦN 2: TÌM KIẾM & THÊM MỚI ---
        _buildLabel("Thêm người nhận (Tên hoặc MSV dấu phẩy)"),
        Row(
          children: [
            Expanded(
              child: Autocomplete<UserSearchModel>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (v) async => v.text.length < 2 
                    ? const Iterable.empty() 
                    : await _searchUsers(v.text),
                onSelected: (s) => _addStudentToVerified(s.id, s.name),
                fieldViewBuilder: (ctx, ctrl, focus, onSub) => TextField(
                  controller: ctrl,
                  focusNode: focus, 
                  onChanged: (v) => _tempBulkController.text = v, // Đồng bộ để nhấn nút check bên cạnh
                  onSubmitted: (v) { 
                    _verifyMultipleUsers(v); 
                    ctrl.clear(); 
                  },
                  decoration: _inputDecor("Nhập tên hoặc dán mã...", Icons.person_search),
                ),
                optionsViewBuilder: (context, onSelected, options) => _buildSearchOptions(context, onSelected, options),
              ),
            ),
            const SizedBox(width: 8),
            // Nút Check danh sách dán từ dấu phẩy
            IconButton(
              onPressed: () => _verifyMultipleUsers(_tempBulkController.text),
              icon: const Icon(Icons.playlist_add_check_circle, color: Colors.blue, size: 30),
            ),
          ],
        ),

        // --- PHẦN 3: HIỂN THỊ DANH SÁCH CHIP ---
        if (_verifiedStudents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
            children: [
              _buildLabel("Danh sách đã chọn (${_verifiedStudents.length} SV)"),
              // Nút xóa sạch list hiện tại
              TextButton(
                onPressed: () => setState(() => _verifiedStudents.clear()), 
                child: const Text("Xóa sạch", style: TextStyle(color: Colors.red, fontSize: 12))
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10), 
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(12), 
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, spreadRadius: 2)
              ]
            ),
            child: Wrap(
              spacing: 8, 
              runSpacing: 8, 
              children: _verifiedStudents.map((sv) => Chip(
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                avatar: CircleAvatar(
                  backgroundColor: vinhUniBlue.withOpacity(0.1),
                  child: Text(sv['name'][0], style: TextStyle(fontSize: 10, color: vinhUniBlue, fontWeight: FontWeight.bold)),
                ),
                label: Text("${sv['name']} (${sv['id']})", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                onDeleted: () => setState(() => _verifiedStudents.remove(sv)),
                deleteIconColor: Colors.red.shade400,
                backgroundColor: Colors.blue.shade50.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              )).toList(),
            ),
          ),
          const SizedBox(height: 15),
          
          // 🔥 NÚT LƯU NHÓM MỚI
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showSaveGroupDialog,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text("Lưu danh sách trên thành Nhóm ảo mới", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: vinhUniBlue,
                side: BorderSide(color: vinhUniBlue, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ] else ...[
          // Khi trống thì hiện gợi ý
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.contact_mail_outlined, color: Colors.grey, size: 40),
                  SizedBox(height: 10),
                  Text("Chưa có sinh viên nào được chọn", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabHistory() {
  // 1. Kiểm tra nếu chưa có ID người gửi thì hiện loading
  if (_senderId.isEmpty) {
    return const Center(child: CircularProgressIndicator());
  }

  return RefreshIndicator(
    // Cho phép vuốt xuống để cập nhật lại danh sách sau khi vừa gửi tin mới
    onRefresh: () async {
      setState(() {}); 
    },
    child: FutureBuilder(
      // Gọi API lấy lịch sử từ ID cán bộ đã được làm sạch (không tiền tố CB/SV)
      future: http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/sent-history/$_senderId")),
      builder: (context, snapshot) {
        // Trạng thái đang tải dữ liệu
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Xử lý lỗi kết nối hoặc không có dữ liệu trả về
        if (snapshot.hasError || !snapshot.hasData) {
          return ListView(
            children: const [
              SizedBox(height: 100),
              Center(child: Text("Không thể kết nối đến máy chủ. Hãy thử vuốt xuống để tải lại.")),
            ],
          );
        }

        try {
          // Giải mã JSON từ Backend trả về
          final data = jsonDecode(snapshot.data!.body);
          
          // Lấy mảng dữ liệu từ key 'data'
          List history = data['data'] ?? []; 
          
          if (history.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text("Bạn chưa gửi thông báo nào.")),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: history.length,
            itemBuilder: (ctx, idx) {
              final item = history[idx]; 
              // Phân biệt tin gửi cá nhân hay gửi nhóm dựa trên scope
              bool isIndi = item['scope'] == "INDIVIDUAL";

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    // Đổi màu Icon dựa trên phạm vi gửi tin
                    backgroundColor: isIndi ? Colors.orange.shade50 : Colors.blue.shade50,
                    child: Icon(
                      isIndi ? Icons.person : Icons.groups, 
                      color: isIndi ? Colors.orange : Colors.blue, 
                      size: 20
                    ),
                  ),
                  title: Text(
                    item['title'] ?? "Không có tiêu đề", 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        isIndi ? "Gửi SV: ${item['target_sid'] ?? 'N/A'}" : "Phạm vi: ${item['scope']}",
                        style: TextStyle(fontSize: 11, color: isIndi ? Colors.orange : Colors.blue)
                      ),
                      Text(
                        "Thời gian: ${item['time'] ?? '---'}", 
                        style: const TextStyle(fontSize: 11, color: Colors.grey)
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      // Đổi màu trạng thái nếu đã có người đọc
                      color: (item['read'] ?? 0) > 0 ? Colors.green.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "${item['read'] ?? 0}/${item['total'] ?? 0}", 
                          style: TextStyle(
                            color: (item['read'] ?? 0) > 0 ? Colors.green : Colors.grey, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 14
                          )
                        ),
                        const Text("ĐÃ ĐỌC", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  onTap: () {
                    // Chuyển sang màn hình thống kê chi tiết từng SV
                    Navigator.push(context, MaterialPageRoute(
                      builder: (c) => ThongKeDocTinScreen(
                        queueId: item['id'], 
                        title: item['title'] ?? "Thống kê"
                      )
                    ));
                  },
                ),
              );
            },
          );
        } catch (e) {
          return const Center(child: Text("Lỗi xử lý dữ liệu từ Server."));
        }
      },
    ),
  );
}
  Future<void> _deleteGroup() async {
  if (_selectedCustomGroup == null) return;
  final confirm = await _showConfirmDialog("Xác nhận xóa nhóm này?");
  if (confirm) {
    final res = await http.delete(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/delete-custom-group/$_selectedCustomGroup"));
    if (res.statusCode == 200) {
      _showSnack("Đã xóa nhóm thành công", Colors.green);
      setState(() { _selectedCustomGroup = null; _verifiedStudents.clear(); });
      _loadCustomGroups();
    }
  }
}

Future<bool> _showConfirmDialog(String msg) async {
  return await showDialog(context: context, builder: (ctx) => AlertDialog(
    title: const Text("Xác nhận"), content: Text(msg),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Đồng ý", style: TextStyle(color: Colors.red))),
    ],
  )) ?? false;
}
  // --- WIDGETS PHỤ TRỢ ---
  Widget _buildSearchOptions(context, onSelected, options) => Align(alignment: Alignment.topLeft, child: Material(elevation: 8, child: Container(width: MediaQuery.of(context).size.width - 40, constraints: const BoxConstraints(maxHeight: 250), child: ListView.separated(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length, separatorBuilder: (c, i) => const Divider(height: 1), itemBuilder: (ctx, idx) { final option = options.elementAt(idx); return ListTile(title: Text(option.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), subtitle: Text(option.id, style: const TextStyle(fontSize: 11)), onTap: () => onSelected(option)); }))));
 Widget _buildTabGroup() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start, 
    children: [
      _buildLabel("Phạm vi gửi tin tập thể"),
      _buildDropdown(
        "Chọn phạm vi", 
        ["LHP", "LOP_HC", "KHOA", "ALL"], 
        _selectedScope, 
        (v) {
          setState(() {
            _selectedScope = v!;
            // Tự động tải lớp hành chính nếu chưa có dữ liệu
            if (v == "LOP_HC" && _adminClassFullList.isEmpty) {
              _fetchAdminClasses(); 
            }
          });
        }, 
        displayFunc: (id) => {
          'LHP': 'Lớp Học Phần (Giảng dạy)', 
          'LOP_HC': 'Lớp Hành Chính (Cố vấn)', 
          'KHOA': 'Theo Khóa học', 
          'ALL': 'Toàn trường'
        }[id]!,
      ),
      const SizedBox(height: 15),

      // --- TRƯỜNG HỢP 1: LỚP HỌC PHẦN (LHP) ---
      if (_selectedScope == "LHP") ...[
        Row(
          children: [
            Expanded(
              child: _buildDropdown("Năm học", _years, _selectedYear, (v) {
                setState(() {
                  _selectedYear = v;
                  _semesters = _filters.where((e) => e['nam'] == v).map((e) => e['ky'].toString()).toSet().toList();
                });
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDropdown("Học kỳ", _semesters, _selectedSemester, (v) {
                setState(() => _selectedSemester = v);
                _fetchClasses();
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _isClassLoading 
          ? const LinearProgressIndicator() 
          : _buildDropdown(
              "Chọn lớp học phần", 
              _classList.map((e) => e['ma_lop'].toString()).toList(), 
              _selectedClass, 
              (v) => setState(() => _selectedClass = v),
              displayFunc: (id) => _classList.firstWhere((e) => e['ma_lop'] == id)['ten_lop'],
            ),
      ],

      // --- TRƯỜNG HỢP 2: LỚP HÀNH CHÍNH (LOP_HC) ---
      if (_selectedScope == "LOP_HC") ...[
        if (_isClassLoading) 
          const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()))
        else if (_adminClassFullList.isEmpty)
          Center(
            child: TextButton.icon(
              onPressed: _fetchAdminClasses, 
              icon: const Icon(Icons.refresh), 
              label: const Text("Tải lại danh sách lớp")
            ),
          )
        else ...[
          _buildLabel("Khóa học"),
          _buildDropdown(
            "Chọn khóa (K60, K61...)", 
            _adminCourses, 
            _selectedAdminCourse, 
            (v) {
              setState(() {
                _selectedAdminCourse = v;
                _filteredAdminClasses = _adminClassFullList.where((e) => e['khoa'] == v).toList();
                _selectedAdminClassId = null;
              });
            }
          ),
          const SizedBox(height: 12),
          _buildLabel("Lớp hành chính"),
          _buildDropdown(
            "Chọn lớp cụ thể", 
            _filteredAdminClasses.map((e) => e['id'].toString()).toList(), 
            _selectedAdminClassId, 
            (v) => setState(() => _selectedAdminClassId = v),
            displayFunc: (id) => _filteredAdminClasses.firstWhere((e) => e['id'].toString() == id)['ten'],
          ),
        ],
      ],

      // --- TRƯỜNG HỢP 3: THEO KHÓA (KHOA) ---
      if (_selectedScope == "KHOA") ...[
        _buildLabel("Nhập mã khóa học"),
        TextField(
          controller: _groupTargetController, 
          decoration: _inputDecor("VD: K61, K62...", Icons.school_outlined),
        ),
      ],

      // --- TRƯỜNG HỢP 4: TOÀN TRƯỜNG (ALL) ---
      if (_selectedScope == "ALL") 
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              // 🔥 ĐÃ FIX: Đổi orangeDeep thành deepOrange
              Expanded(child: Text("Tin nhắn sẽ được gửi tới toàn bộ sinh viên trong trường.", style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade700))),
            ],
          ),
        ),
    ],
  );
}

  Widget _buildBottomAction() => Container(padding: const EdgeInsets.all(20), color: Colors.white, child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _handleSend, style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("GỬI THÔNG BÁO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))));
  Widget _buildDropdown(String hint, List<String> items, String? val, Function(String?) onCh, {String Function(String)? displayFunc}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, hint: Text(hint, style: const TextStyle(fontSize: 13)), value: items.contains(val) ? val : null, items: items.map((e) => DropdownMenuItem(value: e, child: Text(displayFunc != null ? displayFunc(e) : e, style: const TextStyle(fontSize: 13)))).toList(), onChanged: onCh)));
  InputDecoration _inputDecor(String hint, IconData icon) => InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: vinhUniBlue, size: 20), filled: true, fillColor: const Color(0xFFF1F5F9), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: vinhUniBlue)));
  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)));
  void _showSnack(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating));
  Future<Iterable<UserSearchModel>> _searchUsers(String query) async { if (query.trim().length < 2) return const Iterable.empty(); try { final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/search-user?q=${Uri.encodeComponent(query)}")); if (res.statusCode == 200) { final List<dynamic> data = jsonDecode(res.body); return data.map((j) => UserSearchModel.fromJson(j)); } } catch (e) { debugPrint(e.toString()); } return const Iterable.empty(); }
}

// =========================================================
// 3. MÀN HÌNH THỐNG KÊ CHI TIẾT
// =========================================================
class ThongKeDocTinScreen extends StatefulWidget {
  final int queueId;
  final String title;
  const ThongKeDocTinScreen({super.key, required this.queueId, required this.title});
  @override
  State<ThongKeDocTinScreen> createState() => _ThongKeDocTinScreenState();
}

class _ThongKeDocTinScreenState extends State<ThongKeDocTinScreen> {
  List<dynamic> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final res = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/notification-report/${widget.queueId}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() { _list = data['data']; _loading = false; });
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    int readCount = _list.where((e) => e['is_read'] == true).length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0054A6),
        title: const Text("DANH SÁCH NHẬN TIN", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20), color: Colors.blue.shade50,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _buildStatItem("Tổng", _list.length, Colors.blue),
                  _buildStatItem("Đã đọc", readCount, Colors.green),
                  _buildStatItem("Chưa xem", _list.length - readCount, Colors.red),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: _list.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _list[idx];
                    return ListTile(
                      leading: Icon(item['is_read'] ? Icons.check_circle : Icons.radio_button_unchecked, color: item['is_read'] ? Colors.green : Colors.grey),
                      title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(item['sid']),
                      trailing: Text(item['is_read'] ? item['time'] : "Chưa xem", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) => Column(
    children: [
      Text(value.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  );
}