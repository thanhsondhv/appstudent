import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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

  // Logic gọi API tìm kiếm Vector
  Future<void> _performSearch() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => isLoading = true);

    try {
      final String url = "https://mobi.vinhuni.edu.vn/api/docs/search"
          "?query=${Uri.encodeComponent(query)}"
          "&is_ai=${isAiSearch ? 1 : 0}";

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        setState(() {
          documents = jsonDecode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi: $e");
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi kết nối máy chủ!")),
        );
      }
    }
  }

  // Mở màn hình PDF nội bộ
  void _openPdf(String? url, String? title) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Văn bản này chưa có bản PDF số hóa")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerPage(
          url: url,
          title: title ?? "Chi tiết văn bản",
        ),
      ),
    );
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
        ]
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _performSearch(),
            decoration: InputDecoration(
              hintText: isAiSearch ? "Hỏi AI về nội dung văn bản..." : "Tên văn bản, số hiệu...",
              prefixIcon: Icon(isAiSearch ? Icons.psychology : Icons.search, color: vinhUniBlue),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30), 
                borderSide: BorderSide.none
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.send, color: vinhUniBlue), 
                onPressed: _performSearch
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Chế độ Trợ lý AI (Beta)", 
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text(
              isAiSearch ? "Đang sử dụng Vector Search để tìm nội dung" : "Tìm kiếm chính xác theo tiêu đề",
              style: const TextStyle(fontSize: 11)
            ),
            value: isAiSearch,
            activeColor: vinhUniBlue,
            onChanged: (val) {
              setState(() => isAiSearch = val);
            },
          )
        ],
      ),
    );
  }

  Widget _buildDocumentList() {
    if (documents.isEmpty && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text("Nhập từ khóa để tìm kiếm văn bản", 
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.grey.shade200)
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10)
              ),
              child: const Icon(Icons.picture_as_pdf, color: Colors.red),
            ),
            title: Text(
              doc['title'] ?? "Văn bản không tiêu đề", 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("Loại: ${doc['category'] ?? 'Quy định'}", 
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            onTap: () => _openPdf(doc['url'], doc['title']),
          ),
        );
      },
    );
  }
}

// Màn hình xem PDF
class PdfViewerPage extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: const Color(0xFF0054A6),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SfPdfViewer.network(url),
    );
  }
}