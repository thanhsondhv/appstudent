import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ThongKeChiTietScreen extends StatefulWidget {
  final int queueId;
  final String title;
  final String? scope; // Loại tin: GLOBAL, DEPT, LHP...
  final int total;     // Tổng số sinh viên nhận tin
  final int read;      // Số sinh viên đã mở xem

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
  bool _isLargeScope = false;

  @override
  void initState() {
    super.initState();
    // 🔥 Kiểm tra: Nếu là tin gửi diện rộng (Khoa/Trường) thì KHÔNG gọi API load danh sách
    // Việc này giúp App của Sơn chạy mượt, không bao giờ bị "xoay" hay treo do dữ liệu quá lớn.
    _isLargeScope = ["GLOBAL", "ALL", "DEPT", "DEPT_COHORT"].contains(widget.scope);

    if (_isLargeScope) {
      _loading = false; // Hiện bảng thống kê luôn
    } else {
      _fetchDetails(); // Chỉ load danh sách nếu là tin Nhóm/Lớp (số lượng ít)
    }
  }

  Future<void> _fetchDetails() async {
    try {
      final res = await http.get(Uri.parse(
          "https://mobi.vinhuni.edu.vn/api/lecturer/notification-report/${widget.queueId}"));
      
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] ?? [];
        setState(() {
          _list = data;
          _displayList = _list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("🔥 Lỗi fetch chi tiết: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Màu nền xám nhẹ hiện đại
      appBar: AppBar(
        backgroundColor: const Color(0xFF0054A6), // Xanh Vinh Uni
        elevation: 0,
        centerTitle: true,
        title: Text(widget.title, 
          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(), // Bảng thống kê con số
                if (!_isLargeScope) _buildSearchBox(), // Ô tìm kiếm (chỉ cho tin Nhóm)
                Expanded(
                  child: _isLargeScope 
                    ? _buildLargeScopeView() 
                    : _buildStudentList(),
                ),
              ],
            ),
    );
  }

  // --- 1. Bảng thống kê Tổng gửi / Đã đọc ---
  Widget _buildSummaryCard() {
    double percent = widget.total > 0 ? (widget.read / widget.total) * 100 : 0;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem("TỔNG GỬI", widget.total.toString(), Colors.blue),
          _buildStatItem("ĐÃ ĐỌC", widget.read.toString(), Colors.green),
          _buildStatItem("TỶ LỆ", "${percent.toInt()}%", Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // --- 2. Ô tìm kiếm sinh viên ---
  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        onChanged: (q) => setState(() => _displayList = _list.where((s) => 
          s['name'].toString().toLowerCase().contains(q.toLowerCase()) || 
          s['sid'].toString().contains(q)).toList()),
        decoration: InputDecoration(
          hintText: "Tìm tên hoặc mã sinh viên...",
          prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // --- 3. Giao diện cho tin diện rộng (Khoa/Trường) ---
  Widget _buildLargeScopeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.query_stats_rounded, size: 80, color: Colors.blue.withOpacity(0.2)),
            const SizedBox(height: 20),
            const Text("Thống kê tin diện rộng", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Text(
              "Do danh sách người nhận lên tới hàng vạn sinh viên, hệ thống chỉ hiển thị số lượng tổng quát để đảm bảo hiệu năng tối ưu nhất cho App.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. Danh sách sinh viên chi tiết ---
  Widget _buildStudentList() {
    if (_displayList.isEmpty) {
      return const Center(child: Text("Không có dữ liệu chi tiết", style: TextStyle(color: Colors.grey)));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _displayList.length,
      itemBuilder: (c, i) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _displayList[i]['is_read'] ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            child: Text(_displayList[i]['name'][0], style: TextStyle(color: _displayList[i]['is_read'] ? Colors.green : Colors.grey)),
          ),
          title: Text(_displayList[i]['name'] ?? "N/A", 
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text(_displayList[i]['sid'] ?? ""),
          trailing: Icon(
            _displayList[i]['is_read'] ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: _displayList[i]['is_read'] ? Colors.green : Colors.grey,
            size: 20,
          ),
        ),
      ),
    );
  }
}