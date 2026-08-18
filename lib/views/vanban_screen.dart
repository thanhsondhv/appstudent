import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io'; // 🔥 Sửa lỗi: Platform, Directory
import 'package:dio/dio.dart'; // 🔥 Sửa lỗi: Dio
import 'package:path_provider/path_provider.dart'; // 🔥 Sửa lỗi: getExternalStorageDirectory...
import 'package:permission_handler/permission_handler.dart'; // 🔥 Sửa lỗi: Permission
// 🔥 QUAN TRỌNG: Sửa đường dẫn này cho đúng với cấu trúc project của Sơn
import 'package:vinhuni_app/services/database_helper.dart'; 
import '../core/api/api.dart';

class VanBanScreen extends StatefulWidget {
  const VanBanScreen({super.key});

  @override
  State<VanBanScreen> createState() => _VanBanScreenState();
}

class _VanBanScreenState extends State<VanBanScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> documents = [];
  bool isAiSearch = false; 
  bool isLoading = false;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  // --- CÁC BIẾN QUẢN LÝ BỘ LỌC ---
  String selectedCategory = "Tất cả";
  int selectedMonth = 0; 
  DateTime? startDate;
  DateTime? endDate;
  final List<String> categories = ["Tất cả", "Quyết định", "Thông báo", "Báo cáo", "Công văn", "Kế hoạch"];

  @override
  void initState() {
    super.initState();
    _loadCachedData(); // Hiện dữ liệu cũ từ SQLite ngay lập tức
    _performSearch();   // Gọi API lấy dữ liệu mới nhất
  }

  // 1. Lấy dữ liệu từ SQLite (Dùng khi vừa mở app hoặc mất mạng)
  Future<void> _loadCachedData() async {
    try {
      final cachedDocs = await DatabaseHelper.instance.getCachedDocuments();
      if (cachedDocs.isNotEmpty && documents.isEmpty) {
        setState(() {
          documents = cachedDocs;
        });
        debugPrint("📱 Đã nạp ${cachedDocs.length} văn bản từ SQLite");
      }
    } catch (e) {
      debugPrint("❌ Lỗi load SQLite: $e");
    }
  }

  // 2. Logic gọi API tích hợp BỘ LỌC và CACHE
  Future<void> _performSearch() async {
    String query = _searchController.text.trim();
    setState(() => isLoading = true);

    try {
      // Xây dựng URL với đầy đủ tham số lọc
      // Dùng map tham số thay vì tự nối chuỗi — Dio lo phần mã hoá,
      // không còn nguy cơ quên Uri.encodeComponent ở một nhánh nào đó.
      final thamSo = <String, dynamic>{
        "query": query,
        "is_ai": isAiSearch ? 1 : 0,
      };
      if (selectedCategory != "Tất cả") thamSo["category"] = selectedCategory;
      if (selectedMonth > 0) thamSo["month"] = selectedMonth;
      if (startDate != null && endDate != null) {
        thamSo["start_date"] = startDate!.toIso8601String().split('T')[0];
        thamSo["end_date"] = endDate!.toIso8601String().split('T')[0];
      }

      final response = await Api.get(
        "/api/docs/search",
        thamSo: thamSo,
        hanCho: const Duration(seconds: 15),
      );

      if (response.thanhCong) {
        final List<dynamic> newDocs =
            response.data is List ? response.data as List : const [];
        setState(() {
          documents = newDocs;
          isLoading = false;
        });

        // 💾 Lưu vào SQLite để dùng Offline
        if (newDocs.isNotEmpty) {
          await DatabaseHelper.instance.saveDocumentsCache(newDocs);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi API: $e. Sử dụng dữ liệu Offline.");
      await _loadCachedData();
      setState(() => isLoading = false);
    }
  }

  // 3. Hiển thị bảng chọn bộ lọc (Bottom Sheet)
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Bộ lọc văn bản", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              const Text("Loại văn bản", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: categories.map((cat) => ChoiceChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selectedCategory == cat,
                  selectedColor: vinhUniBlue.withOpacity(0.2),
                  onSelected: (val) => setSheetState(() => selectedCategory = cat),
                )).toList(),
              ),
              const SizedBox(height: 20),
              const Text("Khoảng ngày ban hành", style: TextStyle(fontWeight: FontWeight.bold)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range, color: Colors.orange),
                title: Text(startDate == null ? "Chọn khoảng ngày" : "${startDate!.day}/${startDate!.month} - ${endDate!.day}/${endDate!.month}"),
                trailing: startDate != null ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setSheetState(() { startDate = null; endDate = null; })) : null,
                onTap: () async {
                  final picked = await showDateRangePicker(context: context, firstDate: DateTime(2022), lastDate: DateTime.now());
                  if (picked != null) setSheetState(() { startDate = picked.start; endDate = picked.end; });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, padding: const EdgeInsets.symmetric(vertical: 15)),
                  onPressed: () { Navigator.pop(context); _performSearch(); },
                  child: const Text("Áp dụng bộ lọc", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _openPdf(String? url, String? title) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chưa có bản PDF số hóa")));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => PdfViewerPage(url: url, title: title ?? "Văn bản")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Tra cứu văn bản", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white), 
          onPressed: () => Navigator.pop(context)
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _showFilterSheet, // Mở bảng lọc ở màn hình danh sách
              icon: const Icon(Icons.filter_list, color: Colors.white, size: 20),
              label: const Text(
                "Lọc", 
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: isLoading 
              ? Center(child: CircularProgressIndicator(color: vinhUniBlue)) 
              : _buildDocumentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _performSearch(),
            decoration: InputDecoration(
              hintText: isAiSearch ? "Hỏi trợ lý AI về nội dung..." : "Số hiệu, tên văn bản...",
              prefixIcon: Icon(isAiSearch ? Icons.psychology : Icons.search, color: vinhUniBlue),
              filled: true, fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: Icon(Icons.send, color: vinhUniBlue), onPressed: _performSearch),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Chế độ Trợ lý AI", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            value: isAiSearch,
            onChanged: (val) { setState(() { isAiSearch = val; }); _performSearch(); },
          )
        ],
      ),
    );
  }

  Widget _buildDocumentList() {
    if (documents.isEmpty && !isLoading) {
      return const Center(child: Text("Không tìm thấy văn bản nào", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        String rawDate = doc['publish_date'] ?? "";
        String fmtDate = rawDate.length >= 10 ? rawDate.substring(0, 10).split('-').reversed.join('/') : "Đang cập nhật";

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: const CircleAvatar(backgroundColor: Color(0xFFFFEBEE), child: Icon(Icons.picture_as_pdf, color: Colors.red)),
            title: Text(doc['title'] ?? "Văn bản", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                Text("Loại: ${doc['category']}", style: const TextStyle(fontSize: 11)),
                Text("Ngày: $fmtDate", style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _openPdf(doc['url'], doc['title']),
          ),
        );
      },
    );
  }
}

// --- TRANG XEM PDF ---
class PdfViewerPage extends StatefulWidget {
  final String url;
  final String title;

  const PdfViewerPage({super.key, required this.url, required this.title});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  bool _isProcessing = false; // Trạng thái khi đang tải hoặc đang chuẩn bị share
  double _progress = 0;
  String _statusText = "";

  // 1. Hàm làm sạch tên file để tránh lỗi hệ thống
  String _getSafeFileName() {
    return widget.title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
  }

  // 2. Hàm xử lý tải file về máy (Lưu vĩnh viễn vào Downloads)
  Future<void> _downloadPdf() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusText = "Đang tải về máy...";
    });

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String savePath = "${directory!.path}/${_getSafeFileName()}.pdf";

      await Dio().download(
        widget.url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Đã lưu vào thư mục Downloads"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _showErrorSnackBar("Không thể tải file về máy.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 3. Hàm chia sẻ file vật lý (Để giấu link gốc server)
  Future<void> _sharePhysicalFile() async {
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusText = "Đang chuẩn bị file...";
    });

    try {
      // Tải vào thư mục tạm (Temporary Directory)
      final tempDir = await getTemporaryDirectory();
      final tempPath = "${tempDir.path}/${_getSafeFileName()}_share.pdf";

      // Tải file về máy trước khi share
      await Dio().download(
        widget.url,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() => _progress = received / total);
          }
        },
      );

      // Chia sẻ file vật lý thực tế qua XFile
      await Share.shareXFiles(
        [XFile(tempPath)],
        text: 'Văn bản được chia sẻ từ ứng dụng.',
      );
    } catch (e) {
      _showErrorSnackBar("Không thể chia sẻ văn bản lúc này.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showErrorSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $msg"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF0054A6),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Hiển thị vòng xoay tiến độ nếu đang xử lý
          if (_isProcessing)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    value: _progress,
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_for_offline),
              onPressed: _downloadPdf,
              tooltip: "Lưu về máy",
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _sharePhysicalFile,
              tooltip: "Chia sẻ file",
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          SfPdfViewer.network(widget.url),
          // Hiển thị dòng trạng thái nhỏ khi đang tải/share
          if (_isProcessing)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "$_statusText (${(_progress * 100).toStringAsFixed(0)}%)",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}