import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';

// Import service để cập nhật Badge count ngoài màn hình chính
import '../services/notification_service.dart';

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

  // Domain dùng để mở các link file nếu backend trả về link tương đối
  final String _baseWebDomain = "https://congsv.vinhuni.edu.vn"; 

  @override
  void initState() {
    super.initState();
    _notifData = widget.notification;
    // Tải chi tiết nội dung và đánh dấu đã đọc ngay khi mở màn hình
    _fetchFullDetail();
  }

  // 🔥 HÀM LẤY CHI TIẾT VÀ FILE ĐÍNH KÈM TỪ SERVER
  Future<void> _fetchFullDetail() async {
    final dynamic id = _notifData['ID'] ?? _notifData['id'];
    final String type = _notifData['LoaiTin'] ?? _notifData['category'] ?? "";

    if (id == null) return;

    setState(() => _isLoading = true);

    try {
      // Gọi API Detail kèm theo type để rẽ nhánh đúng bảng (Library hoặc ThongBao)
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/get-notif-detail/$id?type=$type'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        
        if (mounted) {
          setState(() {
            // Gộp dữ liệu mới (có FileName) vào dữ liệu cũ
            _notifData = {..._notifData, ...result}; 
            _isLoading = false;
          });
          _markAsRead(); // Đánh dấu đã đọc trên hệ thống
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Lỗi tải chi tiết: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔥 HÀM ĐÁNH DẤU ĐÃ ĐỌC (GỬI STUDENT_ID ĐỂ KHÔNG BỊ UNKNOWN)
  Future<void> _markAsRead() async {
    var id = _notifData['ID'] ?? _notifData['id'];
    if (id == null) return;
    if (_notifData['IsRead'] == true || _notifData['IsRead'] == 1) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? sid = prefs.getString('user_code'); // Lấy mã cán bộ/sinh viên thực tế

      if (sid == null) return;

      final response = await http.post(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/mark-read/$id'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": sid}),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Đã ghi nhận đã đọc cho ID: $id");
        if (NotificationService.onRefreshBadge != null) {
          NotificationService.onRefreshBadge!(); // Làm mới dấu chấm đỏ ngoài hòm thư
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi markAsRead: $e");
    }
  }

  // 🔥 WIDGET HIỂN THỊ NÚT MỞ FILE PDF TỪ ĐĨA CỨNG SERVER
  Widget _buildPdfButton() {
    String? fileName = _notifData['FileName'] ?? _notifData['file_name'];
    
    if (fileName == null || fileName.isEmpty || fileName == "null") {
      return const SizedBox.shrink();
    }

    // Đường dẫn tuyệt đối đến thư mục uploads/docs trên server
    final String pdfUrl = "https://mobi.vinhuni.edu.vn/uploads/docs/$fileName";

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 25),
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(18),
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        icon: const Icon(Icons.picture_as_pdf, size: 28),
        label: const Text("XEM VĂN BẢN PDF", 
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerPage(url: pdfUrl, title: _notifData['TieuDe'] ?? "Văn bản"),
            ),
          );
        },
      ),
    );
  }

  // Quét các tệp đính kèm phụ khác nếu có trong mảng
  Widget _buildAttachmentsArea() {
    List<dynamic> files = [];
    final possibleKeys = ['Files', 'Attachments', 'FileDinhKem', 'lstFile'];

    for (String key in possibleKeys) {
      if (_notifData.containsKey(key) && _notifData[key] is List && (_notifData[key] as List).isNotEmpty) {
        files = _notifData[key];
        break;
      }
    }

    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
        const Text("Tài liệu kèm theo:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0054A6))),
        const SizedBox(height: 10),
        ...files.map((file) {
          String name = "Tài liệu đính kèm";
          String url = "";
          if (file is Map) {
            name = file['FileName'] ?? file['TenFile'] ?? name;
            url = file['FileUrl'] ?? file['Url'] ?? "";
          }
          return ListTile(
            leading: const Icon(Icons.attach_file, color: Colors.blue),
            title: Text(name, style: const TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.download, size: 20),
            onTap: () => _launchUrl(url),
          );
        }).toList(),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    String cleanUrl = url.trim().replaceAll(' ', '%20');
    if (cleanUrl.startsWith('/')) cleanUrl = '$_baseWebDomain$cleanUrl';
    final Uri uri = Uri.parse(cleanUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatHtmlContent(String rawHtml) {
    final urlRegExp = RegExp(r'''(?<!href=["'])(https?:\/\/[^\s<]+)''');
    return rawHtml.replaceAllMapped(urlRegExp, (match) => '<a href="${match.group(0)}">${match.group(0)}</a>');
  }

  @override
  Widget build(BuildContext context) {
    String title = _notifData['TieuDe'] ?? "Thông báo";
    String sender = _notifData['NguoiDang'] ?? "Vinh University";
    String date = _notifData['NgayPhatHanh'] ?? "";
    String rawContent = _notifData['NoiDung'] ?? "<p>Không có nội dung chi tiết.</p>";
    String processedContent = _formatHtmlContent(rawContent);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Chi tiết", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(width: 15),
                      const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Expanded(child: Text(sender, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1)),
                  
                  // NỘI DUNG VĂN BẢN (TRÍCH YẾU)
                  HtmlWidget(
                    processedContent,
                    textStyle: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                    onTapUrl: (url) async { await _launchUrl(url); return true; },
                  ),

                  // 🔥 HIỂN THỊ NÚT PDF CHÍNH Ở ĐÂY
                  _buildPdfButton(),

                  // HIỂN THỊ CÁC FILE ĐÍNH KÈM KHÁC
                  _buildAttachmentsArea(),

                  const SizedBox(height: 50),
                  const Center(child: Text("Đại học Vinh - Vinh University", style: TextStyle(color: Colors.grey, fontSize: 11))),
                ],
              ),
            ),
    );
  }
}

// --- MÀN HÌNH XEM PDF TÍCH HỢP TRONG APP ---
class PdfViewerPage extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0054A6),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(url, subject: title), // Chia sẻ văn bản qua Zalo, Mail...
          ),
        ],
      ),
      body: SfPdfViewer.network(
        url,
        onDocumentLoadFailed: (details) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không thể tải file PDF. Vui lòng kiểm tra kết nối mạng.")));
        },
      ),
    );
  }
}