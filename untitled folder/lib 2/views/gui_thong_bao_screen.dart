import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// Model dữ liệu tìm kiếm
class UserSearchModel {
  final String id;
  final String name;
  final String info;
  UserSearchModel({required this.id, required this.name, required this.info});

  factory UserSearchModel.fromJson(Map<String, dynamic> json) {
    return UserSearchModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      info: json['info'] ?? '',
    );
  }
}

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
  Timer? _debounce;

  List<dynamic> _filters = [];
  List<String> _years = [];
  List<String> _semesters = [];
  List<int> _weeks = [];
  String? _selectedYear, _selectedSemester, _selectedClass;
  int? _selectedWeek;
  List<dynamic> _classList = [];

  bool _isLoading = false;
  bool _isFilterLoading = true;
  bool _isClassLoading = false;
  String _senderId = "CanBo";
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadSender();
    _loadAllFilters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _studentIdController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- HÀM TÌM KIẾM ---
  Future<Iterable<UserSearchModel>> _searchUsers(String query) async {
    if (query.trim().length < 2) return const Iterable.empty();
    try {
      final response = await http.get(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/admin/search-user?q=${Uri.encodeComponent(query)}")
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => UserSearchModel.fromJson(json));
      }
    } catch (e) { debugPrint("Search Error: $e"); }
    return const Iterable.empty();
  }

  Future<void> _loadSender() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _senderId = prefs.getString('user_code') ?? "UnknownCB");
  }

  Future<void> _loadAllFilters() async {
    try {
      final response = await http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/get-filters/$_senderId"));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _filters = data;
          _years = data.map((e) => e['nam'].toString()).toSet().toList();
          _years.sort((a, b) => b.compareTo(a));
          _isFilterLoading = false;
        });
      }
    } catch (e) { _showSnack("Lỗi tải bộ lọc", Colors.red); }
  }

  Future<void> _fetchClasses() async {
    if (_selectedYear == null || _selectedSemester == null || _selectedWeek == null) return;
    setState(() => _isClassLoading = true);
    try {
      final String encodedKy = Uri.encodeComponent(_selectedSemester!);
      final String url = "https://mobi.vinhuni.edu.vn/api/lecturer/classes-filtered?lecturer_id=$_senderId&nam=$_selectedYear&ky=$encodedKy&tuan=$_selectedWeek";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') setState(() { _classList = data['data']; _selectedClass = null; });
      }
    } finally { if (mounted) setState(() => _isClassLoading = false); }
  }

  Future<void> _handleSend() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      _showSnack("Vui lòng nhập đầy đủ tiêu đề và nội dung!", Colors.orange);
      return;
    }
    
    String endpoint = _tabController.index == 0 ? '/api/admin/send-personal-notification' : '/api/lecturer/send-notification';
    Map<String, dynamic> body = _tabController.index == 0 
  ? {
      "sender_id": _senderId, 
      "student_id": _studentIdController.text.trim(), 
      "title": _titleController.text.trim(), 
      "content": _contentController.text.trim(),
    }
  : {
      "sender_id": _senderId, // 👈 Thêm dòng này để Backend biết ai là người gửi cho lớp
      "title": _titleController.text.trim(), 
      "content": _contentController.text.trim(), 
      "type": "LHP", // Có thể tùy biến thêm nếu bạn chọn gửi theo lớp Hành chính (LHC)
      "target_id": _selectedClass,
    };
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('https://mobi.vinhuni.edu.vn$endpoint'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      final result = jsonDecode(response.body);
      if (result['status'] == 'success') {
        _showSuccessDialog("Gửi thông báo thành công!");
        _titleController.clear(); _contentController.clear(); _studentIdController.clear();
      } else { _showSnack("Lỗi: ${result['message']}", Colors.red); }
    } catch (e) { _showSnack("Lỗi kết nối Server", Colors.red); }
    finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: vinhUniBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        title: const Text("GỬI THÔNG BÁO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        // Giữ lại TabBar nhưng bọc trong PreferredSize chuẩn để không che nút back
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white),
              labelColor: vinhUniBlue,
              unselectedLabelColor: Colors.white,
              tabs: const [ Tab(text: "CÁ NHÂN"), Tab(text: "THEO LỚP") ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _isFilterLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoBanner(),
                        const SizedBox(height: 20),
                        _tabController.index == 0 ? _buildTabPersonal() : _buildTabClass(),
                        const Divider(height: 40, thickness: 1, color: Color(0xFFEEEEEE)),
                        _buildLabel("Tiêu đề thông báo"),
                        TextField(controller: _titleController, decoration: _inputDecor("VD: Thông báo nghỉ học...", Icons.title)),
                        const SizedBox(height: 15),
                        _buildLabel("Nội dung chi tiết"),
                        TextField(controller: _contentController, maxLines: 4, decoration: _inputDecor("Nhập nội dung...", Icons.message_outlined)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
      // ĐƯA NÚT GỬI VÀ MENU VÀO ĐÂY ĐỂ KHÔNG BỊ MẤT
      bottomNavigationBar: _buildCompleteBottomBar(),
    );
  }

  // --- GIAO DIỆN TAB ---
  Widget _buildTabPersonal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel("Người nhận"),
        Autocomplete<UserSearchModel>(
          displayStringForOption: (option) => option.id,
          optionsBuilder: (textValue) async {
            if (textValue.text.length < 2) return const Iterable.empty();
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            final c = Completer<Iterable<UserSearchModel>>();
            _debounce = Timer(const Duration(milliseconds: 500), () async {
              final res = await _searchUsers(textValue.text);
              c.complete(res);
            });
            return c.future;
          },
          onSelected: (sel) => setState(() => _studentIdController.text = sel.id),
          fieldViewBuilder: (ctx, ctrl, fNode, onSub) => TextField(
            controller: ctrl, focusNode: fNode,
            decoration: _inputDecor("Nhập tên hoặc MSV để tìm...", Icons.person_search),
            onChanged: (v) => _studentIdController.text = v,
          ),
          optionsViewBuilder: (ctx, onSel, opts) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4, borderRadius: BorderRadius.circular(10),
              child: Container(
                width: MediaQuery.of(ctx).size.width - 40,
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero, shrinkWrap: true,
                  itemCount: opts.length,
                  itemBuilder: (ctx, i) {
                    final o = opts.elementAt(i);
                    return ListTile(
                      title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text("${o.id} - ${o.info}", style: const TextStyle(fontSize: 11)),
                      onTap: () => onSel(o),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabClass() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildDropdown("Năm học", _years, _selectedYear, (val) {
            setState(() { _selectedYear = val; _semesters = _filters.where((e) => e['nam'] == val).map((e) => e['ky'].toString()).toSet().toList(); _selectedSemester = null; });
          })),
          const SizedBox(width: 10),
          Expanded(child: _buildDropdown("Học kỳ", _semesters, _selectedSemester, (val) {
            setState(() { _selectedSemester = val; _weeks = _filters.where((e) => e['nam'] == _selectedYear && e['ky'] == val).map((e) => e['tuan'] as int).toList(); _selectedWeek = null; });
          })),
        ]),
        const SizedBox(height: 12),
        _buildDropdown("Tuần dạy", _weeks.map((e) => e.toString()).toList(), _selectedWeek?.toString(), (val) {
          setState(() => _selectedWeek = int.parse(val!)); _fetchClasses();
        }),
        const SizedBox(height: 12),
        _isClassLoading ? const LinearProgressIndicator() : _buildDropdown(
          _classList.isEmpty ? "Danh sách lớp" : "Chọn lớp học phần",
          _classList.map((e) => e['ma_lop'].toString()).toList(),
          _selectedClass, (val) => setState(() => _selectedClass = val),
          displayFunc: (id) => _classList.firstWhere((e) => e['ma_lop'] == id)['ten_lop']
        ),
      ],
    );
  }

  // --- MENU DƯỚI & NÚT GỬI ---
  Widget _buildCompleteBottomBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nút Gửi Thông Báo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
          child: SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSend,
              style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("GỬI THÔNG BÁO NGAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        // Thanh Menu Điều Hướng (Home/Profile)
        BottomAppBar(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(icon: const Icon(Icons.home, color: Colors.grey), onPressed: () => Navigator.pop(context)),
              IconButton(icon: const Icon(Icons.notifications, color: Color(0xFF0054A6)), onPressed: () {}),
              IconButton(icon: const Icon(Icons.person, color: Colors.grey), onPressed: () {}),
            ],
          ),
        ),
      ],
    );
  }

  // --- HỖ TRỢ GIAO DIỆN ---
  Widget _buildDropdown(String hint, List<String> items, String? value, Function(String?) onChanged, {String Function(String)? displayFunc}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        isExpanded: true, hint: Text(hint, style: const TextStyle(fontSize: 13)),
        value: value, items: items.map((e) => DropdownMenuItem(value: e, child: Text(displayFunc != null ? displayFunc(e) : e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      )),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)));

  InputDecoration _inputDecor(String hint, IconData icon) => InputDecoration(
    hintText: hint, prefixIcon: Icon(icon, color: vinhUniBlue, size: 18), filled: true, fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.all(12),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: vinhUniBlue)),
  );

  Widget _buildInfoBanner() => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.info, color: Colors.blue, size: 18), SizedBox(width: 10), Expanded(child: Text("Thông báo sẽ được gửi tức thì đến ứng dụng của sinh viên.", style: TextStyle(fontSize: 11, color: Colors.blue)))]));

  void _showSnack(String msg, Color color) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));

  void _showSuccessDialog(String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Thành công"), content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
    ));
  }
}