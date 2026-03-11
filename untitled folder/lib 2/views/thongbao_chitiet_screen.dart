import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

// Import service để cập nhật Badge count
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

  // DOMAIN GỐC CỦA TRƯỜNG ĐỂ GHÉP VÀO LINK FILE NẾU BỊ THIẾU
  final String _baseWebDomain = "https://congsv.vinhuni.edu.vn"; 

  @override
  void initState() {
    super.initState();
    _notifData = widget.notification;
    
    // 🔥 LỖI Ở ĐÂY: Trước đây mình chỉ gọi API khi NoiDung bị rỗng.
    // Nhưng File Đính Kèm chỉ có trong API Detail, nên giờ LUÔN LUÔN phải gọi API này!
    _fetchFullDetail();
  }

  Future<void> _fetchFullDetail() async {
    final dynamic id = _notifData['ID'] ?? _notifData['id'];
    if (id == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('https://mobi.vinhuni.edu.vn/api/get-notif-detail/$id'),
      );

      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        
        // IN RA CONSOLE ĐỂ THEO DÕI NẾU CẦN
        debugPrint("🔥 DỮ LIỆU API CHI TIẾT: $result");

        if (mounted) {
          setState(() {
            // Gộp data mới (có File) vào data cũ để giữ nguyên các cấu trúc đang có
            _notifData = {..._notifData, ...result}; 
            _isLoading = false;
          });
          _markAsRead(); 
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead() async {
    var id = _notifData['ID'] ?? _notifData['id'];
    if (id == null) return;
    if (_notifData['IsRead'] == true || _notifData['IsRead'] == 1) return;

    try {
      final response = await http.post(Uri.parse('https://mobi.vinhuni.edu.vn/api/mark-read/$id'));
      if (response.statusCode == 200) {
        if (NotificationService.onRefreshBadge != null) {
          NotificationService.onRefreshBadge!();
        }
      }
    } catch (e) {
      debugPrint("🔥 Lỗi markAsRead: $e");
    }
  }

  // HÀM MỞ LINK CHUYÊN NGHIỆP: FIX KHOẢNG TRẮNG, FIX LINK RELATIVE
  Future<void> _launchUrl(String url) async {
    try {
      String cleanUrl = url.trim().replaceAll(' ', '%20').replaceAll('~/', '/');

      // Tự động ghép tên miền nếu backend chỉ trả về link dạng /Uploads/...
      if (cleanUrl.startsWith('/')) {
        cleanUrl = '$_baseWebDomain$cleanUrl'; 
      } else if (!cleanUrl.startsWith('http')) {
        cleanUrl = 'https://$cleanUrl';
      }

      final Uri uri = Uri.parse(cleanUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication); // Mở trên Safari để xem PDF
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("🔥 Lỗi mở URL: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể tải file này!')),
        );
      }
    }
  }

  String _formatHtmlContent(String rawHtml) {
    final urlRegExp = RegExp(r'''(?<!href=["'])(https?:\/\/[^\s<]+)''');
    return rawHtml.replaceAllMapped(urlRegExp, (match) {
      final url = match.group(0);
      return '<a href="$url">$url</a>';
    });
  }

  // 🔥 THUẬT TOÁN "MẮT THẦN": QUÉT VÀ VẼ BẢNG FILE ĐÍNH KÈM
  Widget _buildAttachmentsArea() {
    List<dynamic> files = [];
    
    // Danh sách tất tần tật các Key mà dân lập trình Backend hay đặt tên cho mảng File
    final possibleKeys = [
      'Files', 'Attachments', 'FileDinhKem', 'lstFile', 'DanhSachFile',
      'files', 'attachments', 'file_dinh_kem', 'TapTin', 'TapTinDinhKem',
      'ListFile', 'lstFileDinhKem', 'TepDinhKem'
    ];

    // Lùng sục trong đống API trả về xem mảng File đang nấp ở đâu
    for (String key in possibleKeys) {
      if (_notifData.containsKey(key) && _notifData[key] is List && (_notifData[key] as List).isNotEmpty) {
        files = _notifData[key];
        debugPrint("✅ TÌM THẤY DANH SÁCH FILE Ở KEY: $key");
        break;
      }
    }

    if (files.isEmpty) return const SizedBox.shrink(); // Không có file thì ẩn mảng này đi

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(thickness: 1),
        ),
        const Text("Tài liệu đính kèm", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0054A6))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300), 
            borderRadius: BorderRadius.circular(8)
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
            itemBuilder: (context, index) {
              var file = files[index];
              
              String fileName = "Tài liệu đính kèm ${index + 1}";
              String fileUrl = "";

              // Tự động phân tích cấu trúc của từng File
              if (file is Map) {
                fileName = file['FileName'] ?? file['TenFile'] ?? file['Name'] ?? file['Ten'] ?? file['Title'] ?? fileName;
                fileUrl = file['FileUrl'] ?? file['Url'] ?? file['Link'] ?? file['Path'] ?? file['FilePath'] ?? file['File_Url'] ?? "";
              } else if (file is String) {
                fileUrl = file;
                fileName = file.split('/').last;
              }

              // Làm đẹp Icon tùy theo loại file
              IconData fileIcon = Icons.insert_drive_file;
              Color iconColor = Colors.blueGrey;
              if (fileName.toLowerCase().endsWith('.pdf')) {
                fileIcon = Icons.picture_as_pdf;
                iconColor = Colors.redAccent;
              } else if (fileName.toLowerCase().endsWith('.doc') || fileName.toLowerCase().endsWith('.docx')) {
                fileIcon = Icons.description;
                iconColor = Colors.blue;
              }

              return ListTile(
                leading: Icon(fileIcon, color: iconColor, size: 30),
                title: Text(fileName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF0054A6).withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.download_rounded, color: Color(0xFF0054A6), size: 18),
                ),
                onTap: () {
                  if (fileUrl.isNotEmpty) _launchUrl(fileUrl);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = _notifData['TieuDe'] ?? "Thông báo";
    String sender = _notifData['NguoiGui'] ?? _notifData['NguoiDang'] ?? "Nhà trường";
    String date = _notifData['NgayGui'] ?? _notifData['NgayPhatHanh'] ?? "";
    
    String rawContent = _notifData['NoiDung'] ?? "<p>Không có nội dung chi tiết.</p>";
    String processedContent = _formatHtmlContent(rawContent);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context, true), 
        ),
        title: const Text(
          "Chi tiết thông báo",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : SingleChildScrollView(
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
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.4,
                            color: Color(0xFF2D3436),
                          ),
                        ),
                        const SizedBox(height: 15),
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
                                child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sender,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    if (date.isNotEmpty)
                                      Text(
                                        date,
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        
                        // NỘI DUNG THÔNG BÁO CHÍNH
                        HtmlWidget(
                          processedContent,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                          onTapUrl: (url) async {
                            await _launchUrl(url);
                            return true;
                          },
                          customStylesBuilder: (element) {
                            switch (element.localName) {
                              case 'img': return {'max-width': '100%', 'height': 'auto', 'border-radius': '8px'};
                              case 'a': return {'color': '#0054A6', 'font-weight': '600', 'text-decoration': 'underline', 'word-break': 'break-all'};
                              case 'table': return {'border-collapse': 'collapse', 'width': '100%', 'border': '1px solid #e0e0e0'};
                              case 'th':
                              case 'td': return {'border': '1px solid #e0e0e0', 'padding': '8px'};
                            }
                            return null;
                          },
                        ),
                        
                        // 🔥 HIỂN THỊ DANH SÁCH FILE ĐÍNH KÈM Ở ĐÂY
                        _buildAttachmentsArea(),
                        
                        const SizedBox(height: 50),
                        const Divider(),
                        const Center(
                          child: Text(
                            "Đại học Vinh - Vinh University",
                            style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}