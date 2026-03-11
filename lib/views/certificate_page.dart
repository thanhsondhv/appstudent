import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CertificatePage extends StatefulWidget {
  final String studentId;

  CertificatePage({required this.studentId});

  @override
  _CertificatePageState createState() => _CertificatePageState();
}

class _CertificatePageState extends State<CertificatePage> {
  final String apiUrl = "https://mobi.vinhuni.edu.vn/api/certificate";
  List certList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCertificates(); 
  }

  Future<void> _fetchCertificates() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(
          "$apiUrl/student/${widget.studentId}?type_id=ALL"));
      
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            certList = json.decode(response.body) ?? [];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showError("Lỗi kết nối dữ liệu");
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        // 🔥 NÚT QUAY VỀ: Giúp học viên thoát màn hình này để về Menu Home
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context), 
        ),
        title: const Text("Hồ sơ Chứng chỉ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0054A6),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchCertificates,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6)))
            : certList.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    // 🔥 KHOẢNG ĐỆM DƯỚI: Đảm bảo không bị che khuất
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), 
                    itemCount: certList.length,
                    itemBuilder: (context, index) => _buildCertCard(certList[index]),
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 150),
        Center(
          child: Column(
            children: [
              Icon(Icons.assignment_late_outlined, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text("Bạn chưa có dữ liệu chứng chỉ nào", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCertCard(dynamic cert) {
    // 🔥 XỬ LÝ NULL AN TOÀN: Chuyển tất cả về String để không bị lỗi "subtype of string"
    String tenCC = (cert['ten'] ?? cert['loai'] ?? "Chứng chỉ").toString();
    String loaiCC = (cert['loai'] ?? "Văn bằng").toString();
    String ngayCap = (cert['ngay_cap'] ?? "--/--/----").toString();
    String soQD = (cert['so_qd'] ?? "Đang cập nhật").toString();
    String diem = (cert['diem'] ?? "---").toString();
    bool isDat = cert['is_dat'] == true; // Ép kiểu bool an toàn

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: isDat ? Colors.blue : Colors.grey, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tenCC,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0054A6)),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.category_outlined, "Loại", loaiCC),
            _buildInfoRow(Icons.calendar_today_outlined, "Ngày cấp", ngayCap),
            _buildInfoRow(Icons.description_outlined, "Số quyết định", soQD),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  children: [
                    const TextSpan(text: "Kết quả: "),
                    TextSpan(
                      text: diem,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
          // Đảm bảo Text luôn nhận String
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }
}