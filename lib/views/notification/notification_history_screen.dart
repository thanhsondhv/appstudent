import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api.dart';
class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});
  @override
  State<NotificationHistoryScreen> createState() => _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _historyList = [], _filteredList = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
  // 1. Bắt đầu trạng thái loading
  setState(() => _isLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    
    // 🔥 QUAN TRỌNG: Sơn kiểm tra xem lúc GỬI TIN bạn lưu vào bảng Queue là 
    // 'user_id' (CB123) hay 'user_code' (123) để lấy cho đúng nhé.
    // Ở đây mình dùng 'user_id' theo logic log của bạn.
    final String id = prefs.getString('user_id') ?? "";

    if (id.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 2. Gọi API lấy lịch sử
    final response = await Api.get(
      "/api/lecturer/sent-history/$id",
      hanCho: const Duration(seconds: 15),
    );

    // 3. Kiểm tra xem Widget còn trên màn hình không trước khi setState
    if (!mounted) return;

    if (response.thanhCong) {
      final Map<String, dynamic> responseData = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      
      if (responseData['status'] == 'success') {
        setState(() {
          // Gán dữ liệu vào danh sách chính và danh sách lọc
          _historyList = responseData['data'] ?? [];
          _filteredList = _historyList;
          _isLoading = false;
        });
      } else {
        // Nếu Backend trả về status: error
        setState(() => _isLoading = false);
        _showError("Lỗi dữ liệu: ${responseData['message']}");
      }
    } else {
      // Nếu mã lỗi HTTP (404, 500, ...)
      setState(() => _isLoading = false);
      _showError("Server lỗi (Mã: ${response.statusCode})");
    }

  } catch (e) {
    // 4. Xử lý lỗi kết nối, lỗi mạng, lỗi parse JSON
    debugPrint("🔥 Lỗi loadHistory: $e");
    if (mounted) {
      setState(() => _isLoading = false);
      _showError("Không thể kết nối máy chủ. Vui lòng thử lại!");
    }
  }
}

// Hàm bổ trợ để hiện thông báo lỗi nhanh
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

  void _filter(String q) {
    setState(() => _filteredList = _historyList.where((i) => i['title'].toString().toLowerCase().contains(q.toLowerCase())).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0054A6),
        elevation: 0,
        centerTitle: true,
        // 🔥 NÚT BACK MÀU TRẮNG ĐÂY SƠN NHÉ
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "LỊCH SỬ GỬI TIN", 
          style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.orange,
          indicatorWeight: 3,
          tabs: const [Tab(text: "Tất cả"), Tab(text: "Lớp/Nhóm"), Tab(text: "Khoa/Viện")],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: "Tìm kiếm tiêu đề...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : TabBarView(
                  controller: _tabController,
                  children: [ _buildList(0), _buildList(1), _buildList(2) ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(int tab) {
  // 1. Khởi tạo danh sách dựa trên dữ liệu đã search
  List<dynamic> list = List.from(_filteredList);

  // 2. Logic lọc theo Tab
  if (tab == 1) {
    // Tab: Nhóm / Lớp (Các loại lớp học phần, hành chính)
    list = list.where((e) => 
      ["LHP", "LOP_HC", "LHP_LOW"].contains(e['scope'])
    ).toList();
  } else if (tab == 2) {
    // Tab: Khoa / Trường (Các tin gửi diện rộng Admin mới có)
    // 🔥 Đã thêm 'GLOBAL' và 'ALL' để không bị sót tin Toàn trường
    list = list.where((e) => 
      ["DEPT", "DEPT_COHORT", "GLOBAL", "ALL"].contains(e['scope'])
    ).toList();
  }

  // 3. Hiển thị giao diện khi không có dữ liệu (Tránh màn hình trắng)
  if (list.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 50, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 10),
          const Text(
            "Chưa có lịch sử gửi tin trong mục này",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // 4. Danh sách chính (Sử dụng Card thiết kế bo góc hiện đại)
  return ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: list.length,
    itemBuilder: (ctx, idx) {
      final item = list[idx];
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // Biểu tượng loại tin nhắn
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getScopeColor(item['scope']).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getScopeIcon(item['scope']),
              color: _getScopeColor(item['scope']),
              size: 20,
            ),
          ),
          title: Text(
            item['title'] ?? "Không có tiêu đề",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item['time'] ?? "--:--",
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
          // Phần trăm và số lượng đọc tin (Badge)
          trailing: _buildBadge(item['read'] ?? 0, item['total'] ?? 0),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => ThongKeChiTietScreen(
                queueId: item['id'],
                title: item['title'] ?? "Chi tiết",
                scope: item['scope'], // 🔥 Truyền scope sang để check tin diện rộng
                total: item['total'] ?? 0,
                read: item['read'] ?? 0,
              ),
            ),
          ),
        ),
      );
    },
  );
}

// --- CÁC HÀM BỔ TRỢ ĐỂ GIAO DIỆN CHUYÊN NGHIỆP HƠN ---

// Hàm lấy Icon tương ứng với Scope
IconData _getScopeIcon(String? scope) {
  switch (scope) {
    case 'GLOBAL': case 'ALL': return Icons.public;
    case 'DEPT': case 'DEPT_COHORT': return Icons.domain;
    case 'LOP_HC': return Icons.school;
    default: return Icons.groups_rounded;
  }
}

// Hàm lấy màu sắc tương ứng với Scope
Color _getScopeColor(String? scope) {
  switch (scope) {
    case 'GLOBAL': case 'ALL': return Colors.purple;
    case 'DEPT': case 'DEPT_COHORT': return Colors.red;
    case 'LOP_HC': return Colors.blue;
    default: return Colors.orange;
  }
}

  Widget _buildBadge(int read, int total) {
    double p = total > 0 ? (read / total) : 0;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("${(p * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
      Text("$read/$total", style: const TextStyle(fontSize: 9, color: Colors.grey)),
    ]);
  }
}

class ThongKeChiTietScreen extends StatefulWidget {
  final int queueId; 
  final String title;
  final String? scope; // 🔥 Thêm tham số này để nhận scope
  final int total;     // 🔥 Thêm tham số này để nhận tổng số
  final int read;      // 🔥 Thêm tham số này để nhận số đã đọc

  // Cập nhật Constructor để chấp nhận các tham số mới
  const ThongKeChiTietScreen({
    super.key, 
    required this.queueId, 
    required this.title,
    this.scope,
    this.total = 0,
    this.read = 0,
  });

  @override
  State<ThongKeChiTietScreen> createState() => _ThongKeChiTietScreenState();
}

class _ThongKeChiTietScreenState extends State<ThongKeChiTietScreen> {
  List<dynamic> _list = [], _displayList = [];
  bool _loading = true;
  bool _isLargeScope = false; // Biến kiểm tra tin nhắn diện rộng

  @override
  void initState() { 
    super.initState(); 
    // Kiểm tra: Nếu là tin gửi diện rộng (Khoa/Trường) thì KHÔNG load danh sách SV để tránh treo
    _isLargeScope = ["GLOBAL", "ALL", "DEPT", "DEPT_COHORT"].contains(widget.scope);
    
    if (_isLargeScope) {
      _loading = false; // Tắt xoay ngay lập tức vì không gọi API load list
    } else {
      _fetch(); 
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await Api.get("/api/lecturer/notification-report/${widget.queueId}");

      if (!mounted) return;

      if (res.thanhCong) {
        setState(() { 
          _list = jsonDecode(res.body)['data'] ?? []; 
          _displayList = _list;
          _loading = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0054A6), 
        title: Text(widget.title, style: const TextStyle(fontSize: 13, color: Colors.white))
      ),
      body: _loading 
          ? const Center(child: CircularProgressIndicator()) 
          : Column(
              children: [
                _buildSummaryHeader(), // Luôn hiện bảng thống kê Tổng/Đọc/Tỷ lệ
                if (!_isLargeScope) _buildSearchBox(),
                Expanded(
                  child: _isLargeScope 
                      ? _buildLargeScopeInfo() // Hiện thông báo cho tin diện rộng
                      : _buildStudentList(),   // Hiện danh sách cho tin nhóm lớp
                ),
              ],
            ),
    );
  }

  // --- CÁC WIDGET GIAO DIỆN CON ---

  Widget _buildSummaryHeader() {
    double percent = widget.total > 0 ? (widget.read / widget.total) * 100 : 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("TỔNG GỬI", widget.total.toString(), Colors.blue),
          _statItem("ĐÃ ĐỌC", widget.read.toString(), Colors.green),
          _statItem("TỶ LỆ", "${percent.toInt()}%", Colors.orange),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        onChanged: (q) => setState(() => _displayList = _list.where((s) => s['name'].toString().toLowerCase().contains(q.toLowerCase()) || s['sid'].toString().contains(q)).toList()),
        decoration: InputDecoration(
          hintText: "Tìm tên hoặc mã SV...",
          prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildLargeScopeInfo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 70, color: Colors.blue.withOpacity(0.2)),
            const SizedBox(height: 15),
            const Text("Thống kê tin diện rộng", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              "Hệ thống chỉ hiển thị thống kê tổng quát cho các tin gửi Toàn khoa/Trường để đảm bảo tốc độ tải.",
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    if (_displayList.isEmpty) return const Center(child: Text("Không có dữ liệu chi tiết"));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _displayList.length,
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (c, i) => ListTile(
        title: Text(_displayList[i]['name'] ?? "N/A", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text(_displayList[i]['sid'] ?? ""),
        trailing: Icon(_displayList[i]['is_read'] ? Icons.check_circle : Icons.radio_button_unchecked, color: _displayList[i]['is_read'] ? Colors.green : Colors.grey, size: 20),
      ),
    );
  }
}