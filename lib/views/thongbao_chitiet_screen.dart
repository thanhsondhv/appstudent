import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChiTietThongBaoScreen extends StatefulWidget { // Chuyển sang StatefulWidget
  final Map<String, dynamic> notification;

  const ChiTietThongBaoScreen({super.key, required this.notification});

  @override
  State<ChiTietThongBaoScreen> createState() => _ChiTietThongBaoScreenState();
}

class _ChiTietThongBaoScreenState extends State<ChiTietThongBaoScreen> {

  @override
  void initState() {
    super.initState();
    // Gọi API ngay khi màn hình vừa khởi tạo
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    final int? notifId = widget.notification['ID'];
    if (notifId == null) return;

    try {
      // Gọi API đánh dấu đã đọc
      final response = await http.post(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/mark-read/$notifId'),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['status'] == 'SUCCESS') {
          debugPrint("✅ Đã cập nhật trạng thái đã đọc cho ID: $notifId");
        }
      }
    } catch (e) {
      debugPrint("❌ Lỗi API mark-read: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color vinhUniBlue = const Color(0xFF0054A6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context, true), // Trả về true để thông báo trang trước cần load lại
        ),
        title: const Text(
          "Chi tiết thông báo",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: double.infinity, height: 4, color: vinhUniBlue),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.notification['TieuDe'] ?? "Thông báo",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F2F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: vinhUniBlue,
                          radius: 18,
                          child: const Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.notification['NguoiDang'] ?? "Hệ thống",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                widget.notification['NgayPhatHanh'] ?? "",
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  HtmlWidget(
                    widget.notification['NoiDung'] ?? "Không có nội dung chi tiết.",
                    textStyle: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 50),
                  const Divider(),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      "Đại học Vinh - Vinh University",
                      style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}