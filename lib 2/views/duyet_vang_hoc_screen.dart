import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DuyetVangHocScreen extends StatefulWidget {
  final String lecturerId; // Đây là mã CB
  const DuyetVangHocScreen({super.key, required this.lecturerId});

  @override
  State<DuyetVangHocScreen> createState() => _DuyetVangHocScreenState();
}

class _DuyetVangHocScreenState extends State<DuyetVangHocScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  Widget build(BuildContext context) {
    // Làm sạch mã CB (Bỏ tiền tố CB nếu có)
    String cleanId = widget.lecturerId.toUpperCase().replaceFirst('CB', '');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("DUYỆT VẮNG HỌC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder(
        // API này Sơn cần viết ở Backend để lấy đơn gửi cho GV này
        future: http.get(Uri.parse("https://mobi.vinhuni.edu.vn/api/lecturer/student-messages/$cleanId")),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text("Không có dữ liệu hoặc lỗi kết nối"));
          }

          final List data = jsonDecode(snapshot.data!.body)['data'] ?? [];
          
          if (data.isEmpty) {
            return const Center(child: Text("Hiện không có đơn xin phép nào mới."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: data.length,
            itemBuilder: (ctx, idx) {
              final item = data[idx];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  title: Text(
                    "SV: ${item['student_name']} (${item['student_id']})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 5),
                      Text("Lớp: ${item['lhp_name']}", style: const TextStyle(color: Colors.blue, fontSize: 12)),
                      Text("Lý do: ${item['reason']}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      const SizedBox(height: 5),
                      Text("Ngày gửi: ${item['time']}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  trailing: Icon(Icons.chevron_right, color: vinhUniBlue),
                  onTap: () {
                    // Chỗ này Sơn có thể mở Popup để bấm "Duyệt" hoặc "Từ chối"
                    _showActionDialog(item);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
  Future<void> _handleUpdateStatus(int requestId, int newStatus) async {
  try {
    final response = await http.post(
      Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/lecturer/update-attendance-status"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "request_id": requestId,
        "status": newStatus, // 1: Duyệt, 2: Từ chối
      }),
    );

    if (response.statusCode == 200) {
      final resData = jsonDecode(response.body);
      if (resData['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus == 1 
              ? "✅ Đã duyệt và gửi thông báo cho SV" 
              : "❌ Đã từ chối đơn xin phép"),
            backgroundColor: newStatus == 1 ? Colors.green : Colors.red,
          ),
        );
        // Tải lại dữ liệu để cập nhật giao diện
        setState(() {}); 
      }
    }
  } catch (e) {
    debugPrint("🔥 Lỗi cập nhật: $e");
  }
}
  void _showActionDialog(dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xử lý đơn xin phép", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text("Bạn muốn xử lý đơn của sinh viên ${item['student_name']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ĐÓNG")),
          ElevatedButton(
            onPressed: () { /* Logic Duyệt đơn */ Navigator.pop(ctx); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("DUYỆT", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}