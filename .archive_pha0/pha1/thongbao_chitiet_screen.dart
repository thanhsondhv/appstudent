import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';

import '../services/notification_service.dart';
import '../services/database_helper.dart';

class ChiTietThongBaoScreen extends StatefulWidget {
  final Map<String, dynamic> notification;

  const ChiTietThongBaoScreen({super.key, required this.notification});

  @override
  State<ChiTietThongBaoScreen> createState() => _ChiTietThongBaoScreenState();
}

class _ChiTietThongBaoScreenState extends State<ChiTietThongBaoScreen> {
  bool _isLoading = false;
  late Map<String, dynamic> _notifData;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void initState() {
    super.initState();
    _notifData = widget.notification;
    _fetchFullDetail();
  }

  Future<void> _fetchFullDetail() async {
    final dynamic id = _notifData['ID'] ?? _notifData['id'];
    final String type = _notifData['LoaiTin'] ?? _notifData['category'] ?? "GENERAL";

    if (id == null) return;

    String currentContent = _notifData['NoiDung'] ?? _notifData['content'] ?? "";
    
    if (currentContent.trim().isEmpty) {
      setState(() => _isLoading = true);
    } else {
      // Nếu đã có dữ liệu, đánh dấu đọc ngay
      await _markAsRead();
    }

    try {
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/get-notif-detail/$id?type=$type'));
      
      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _notifData = {..._notifData, ...result}; 
            _isLoading = false;
          });
          // Nếu sau khi fetch mới có dữ liệu thì mới đánh dấu đọc
          await _markAsRead(); 
        }
      }
    } catch (e) {
      debugPrint("❌ Lỗi lấy chi tiết từ Server: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // HÀM ĐÁNH DẤU ĐỌC ĐÃ ĐƯỢC LÀM AN TOÀN
  Future<void> _markAsRead() async {
    final dynamic id = _notifData['id'] ?? _notifData['ID'];
    if (id == null || _notifData['IsRead'] == 1) return; 

    try {
      // 1. Lưu Local ngay
      await DatabaseHelper.instance.updateReadStatus(int.parse(id.toString()));
      
      // 2. Cập nhật UI
      if (mounted) setState(() => _notifData['IsRead'] = 1);

      // 3. Gọi Server
      final prefs = await SharedPreferences.getInstance();
      String? rawSid = prefs.getString('user_code');
      String sid = rawSid?.replaceAll(RegExp(r'[^0-9]'), '') ?? "";

      final response = await http.post(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/mark-read/$id'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": sid}),
      );
      
      if (response.statusCode == 200) {
         // Badge chỉ refresh khi Server xác nhận thành công
         if (NotificationService.onRefreshBadge != null) NotificationService.onRefreshBadge!();
      }
    } catch (e) {
      debugPrint("❌ Lỗi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    dynamic getVal(String k1, String k2, String def) => _notifData[k1] ?? _notifData[k2] ?? def;

    String title = getVal('title', 'TieuDe', 'Thông báo');
    String content = getVal('content', 'NoiDung', '');
    String date = getVal('date', 'NgayPhatHanh', '');
    String author = getVal('author', 'NguoiDang', 'Vinh University');
    String? fileName = _notifData['file_name'] ?? _notifData['FileName'];

    return WillPopScope(
      onWillPop: () async {
        // Gọi đánh dấu đọc lần cuối để đảm bảo trước khi thoát
        await _markAsRead();
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text("Chi tiết bản tin", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0.5,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
            onPressed: () async {
              await _markAsRead();
              Navigator.pop(context, true);
            },
          ),
        ),
        body: _isLoading 
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.4, color: Color(0xFF003366))),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.access_time, size: 12, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(width: 15),
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(author, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ]),
                  const Divider(height: 35),
                  HtmlWidget(
                    content, 
                    textStyle: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                  ),
                  if (fileName != null && fileName.toString().toLowerCase() != "null" && fileName.toString().isNotEmpty) 
                    _buildPdfButton(fileName, title),
                  const SizedBox(height: 50),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildPdfButton(String fileName, String title) {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade800, 
          foregroundColor: Colors.white, 
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("XEM VĂN BẢN ĐÍNH KÈM", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
          context, 
          MaterialPageRoute(builder: (context) => PdfViewerPage(
            url: "https://mobi.vinhuni.edu.vn/uploads/docs/$fileName", 
            title: title
          ))
        ),
      ),
    );
  }
}

class PdfViewerPage extends StatelessWidget {
  final String url;
  final String title;
  const PdfViewerPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 13, color: Colors.white), overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF0054A6),
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white), 
            onPressed: () => Share.share("Văn bản VinhUni: $url")
          )
        ],
      ),
      body: SfPdfViewer.network(url),
    );
  }
}