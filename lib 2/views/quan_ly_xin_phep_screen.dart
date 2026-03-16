import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class QuanLyXinPhepScreen extends StatefulWidget {
  final String studentId;
  const QuanLyXinPhepScreen({super.key, required this.studentId});

  @override
  State<QuanLyXinPhepScreen> createState() => _QuanLyXinPhepScreenState();
}

class _QuanLyXinPhepScreenState extends State<QuanLyXinPhepScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  // Form State
  String? _selectedLhpId;
  String _selectedCategory = 'VANG_HOC';
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("QUẢN LÝ NGHỈ HỌC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "TẠO ĐƠN MỚI"),
            Tab(text: "LỊCH SỬ GỬI"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewRequestTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // --- TAB 1: TẠO ĐƠN MỚI ---
  Widget _buildNewRequestTab() {
    return FutureBuilder(
      future: http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/student/my-classes/${widget.studentId}")),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        List classes = snapshot.hasData ? jsonDecode(snapshot.data!.body) : [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel("1. Chọn lớp học phần"),
              _buildDropdownContainer(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Bấm để chọn lớp..."),
                    value: _selectedLhpId,
                    items: classes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'], style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setState(() => _selectedLhpId = v),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildLabel("2. Hình thức xin phép"),
              _buildDropdownContainer(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedCategory,
                    items: const [
                      DropdownMenuItem(value: 'VANG_HOC', child: Text("Vắng học (Cả buổi)")),
                      DropdownMenuItem(value: 'MUON_HOC', child: Text("Đi muộn (Vào sau)")),
                      DropdownMenuItem(value: 'LY_DO_KHAC', child: Text("Lý do khác")),
                    ],
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildLabel("3. Lý do chi tiết"),
              TextField(
                controller: _reasonController,
                maxLines: 4,
                decoration: _inputDecor("Nhập lý do cụ thể...", Icons.edit_note),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("GỬI ĐƠN XIN PHÉP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TAB 2: LỊCH SỬ ---
  Widget _buildHistoryTab() {
  return FutureBuilder(
    // Gọi API lấy lịch sử xin phép của sinh viên
    future: http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/student/attendance-history/${widget.studentId}")),
    builder: (context, snapshot) {
      // 1. Trạng thái chờ dữ liệu
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      
      // 2. Xử lý lỗi hoặc không có dữ liệu
      if (snapshot.hasError || !snapshot.hasData) {
        return const Center(child: Text("Lỗi kết nối máy chủ!"));
      }

      final List history = jsonDecode(snapshot.data!.body)['data'] ?? [];
      
      if (history.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off_rounded, size: 60, color: Colors.grey),
              SizedBox(height: 10),
              Text("Bạn chưa có đơn xin phép nào.", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }

      return ListView.separated(
        itemCount: history.length,
        padding: const EdgeInsets.all(15),
        separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
        itemBuilder: (ctx, idx) {
          final item = history[idx];
          
          // --- LOGIC XỬ LÝ TRẠNG THÁI (Status từ DB) ---
          int status = item['status'] ?? 0; // 0: Chờ, 1: Chấp nhận, 2: Từ chối
          Color statusColor = status == 1 ? Colors.green : (status == 2 ? Colors.red : Colors.orange);
          String statusText = status == 1 ? "Đã duyệt" : (status == 2 ? "Từ chối" : "Chờ duyệt");
          IconData statusIcon = status == 1 ? Icons.check_circle : (status == 2 ? Icons.cancel : Icons.hourglass_top_rounded);

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              // Icon đại diện cho trạng thái đơn
              leading: CircleAvatar(
                backgroundColor: statusColor.withOpacity(0.1),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              // Tên lớp học phần
              title: Text(
                item['lhp_name'] ?? "Mã lớp: ${item['lhp_id']}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Nội dung lý do và hình thức
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Lý do: ${item['reason']}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      "Loại: ${item['category'] == 'VANG_HOC' ? 'Vắng học' : 'Đi muộn'}",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                    ),
                  ],
                ),
              ),
              // Badge trạng thái và Thời gian ở góc phải
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['time'] ?? "",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  // --- HELPERS ---
  Future<void> _submitRequest() async {
    if (_selectedLhpId == null || _reasonController.text.isEmpty) {
      _showSnack("Vui lòng nhập đủ thông tin!", Colors.orange); return;
    }
    setState(() => _isSubmitting = true);
    try {
      final res = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/student/send-attendance-request"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": widget.studentId,
          "lhp_code": _selectedLhpId,
          "category": _selectedCategory,
          "reason": _reasonController.text.trim(),
        }),
      );
      if (res.statusCode == 200) {
        _showSnack("Đã gửi đơn thành công!", Colors.green);
        _reasonController.clear();
        _tabController.animateTo(1); // Chuyển sang tab lịch sử
      }
    } catch (e) { _showSnack("Lỗi kết nối Server", Colors.red); }
    setState(() => _isSubmitting = false);
  }

  Widget _buildStatusIcon(int status) {
    IconData icon = Icons.hourglass_empty; Color color = Colors.orange;
    if (status == 1) { icon = Icons.check_circle; color = Colors.green; }
    if (status == 2) { icon = Icons.cancel; color = Colors.red; }
    return Icon(icon, color: color);
  }

  Widget _buildStatusTag(int status) {
    String text = "Chờ duyệt"; Color color = Colors.orange;
    if (status == 1) { text = "Đã xem"; color = Colors.green; }
    if (status == 2) { text = "Từ chối"; color = Colors.red; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)));
  
  Widget _buildDropdownContainer({required Widget child}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: child);

  InputDecoration _inputDecor(String hint, IconData icon) => InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: vinhUniBlue), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)));

  void _showSnack(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
}