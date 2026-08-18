import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChungChiTraCuuScreen extends StatefulWidget {
  final String userMaSV;

  const ChungChiTraCuuScreen({super.key, required this.userMaSV});

  @override
  State<ChungChiTraCuuScreen> createState() => _ChungChiTraCuuScreenState();
}

class _ChungChiTraCuuScreenState extends State<ChungChiTraCuuScreen> {
  // Cấu hình URL Backend (Sử dụng 10.0.2.2 cho Android Emulator)
  final String baseUrl = "https://mobi.vinhuni.edu.vn";

  // Palette màu chuẩn VinhUni
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  // State Variables
  List<dynamic> dsChungChi = [];
  List<dynamic> dsDotThi = [];
  String? selectedLoaiCC;
  String? selectedDotThi;

  bool _isLoading = false;
  List<dynamic>? _examResult;

  @override
  void initState() {
    super.initState();
    _loadChungChi();
  }

  // ── LOGIC API ──────────────────────────────────────────────────────

  // 1. Tải danh sách chứng chỉ
  Future<void> _loadChungChi() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/chung-chi'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          dsChungChi = data['ds_chung_chi'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải chứng chỉ: $e");
    }
  }

  // 2. Tải đợt thi dựa trên loại chứng chỉ đã chọn
  Future<void> _loadDotThi(String loaiId) async {
    setState(() {
      dsDotThi = [];
      selectedDotThi = null;
    });
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/dot-thi?loai=$loaiId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          dsDotThi = data['ds_dot_thi'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải đợt thi: $e");
    }
  }

  // 3. Thực hiện tra cứu (POST JSON)
  Future<void> _traCuu() async {
    if (selectedLoaiCC == null) {
      _showSnackBar("Vui lòng chọn loại chứng chỉ!");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/tra-cuu'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "ma_sv": widget.userMaSV,
          "loai_chung_chi": selectedLoaiCC,
          "dot_thi": selectedDotThi
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _examResult = data['lich_thi'];
        });
      } else {
        setState(() => _examResult = []);
        _showSnackBar(data['error'] ?? "Không tìm thấy dữ liệu.");
      }
    } catch (e) {
      _showSnackBar("Lỗi kết nối máy chủ.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── GUI COMPONENTS ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: const Text("TRA CỨU CHỨNG CHỈ",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, letterSpacing: 1.1)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : _buildResultArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          _buildInfoRow("Mã sinh viên:", widget.userMaSV),
          const SizedBox(height: 12),

          // Loại chứng chỉ: Dùng key 'id' và 'ten' từ API
          _buildDropdown(
              "Loại chứng chỉ",
              selectedLoaiCC,
              dsChungChi.map((cc) => DropdownMenuItem(
                  value: cc['id'].toString(),
                  child: Text(cc['ten'] ?? "N/A", style: const TextStyle(fontSize: 13))
              )).toList(),
                  (val) {
                setState(() => selectedLoaiCC = val);
                _loadDotThi(val!);
              },
              Icons.school_rounded
          ),

          const SizedBox(height: 12),

          // Đợt thi: Dùng key 'id' và 'ten' từ API
          _buildDropdown(
              "Đợt thi (Tùy chọn)",
              selectedDotThi,
              dsDotThi.map((dt) => DropdownMenuItem(
                  value: dt['id'].toString(),
                  child: Text(dt['ten_dot'] ?? "N/A", style: const TextStyle(fontSize: 13))
              )).toList(),
                  (val) => setState(() => selectedDotThi = val),
              Icons.calendar_today_rounded
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _traCuu,
              icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
              label: const Text("TRA CỨU KẾT QUẢ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: vinhUniBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea() {
    if (_examResult == null) {
      return const Center(child: Text("Chọn thông tin và ấn tra cứu", style: TextStyle(color: Colors.grey)));
    }
    if (_examResult!.isEmpty) {
      return const Center(child: Text("Không có dữ liệu kết quả thi."));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: _examResult!.length,
      itemBuilder: (context, index) => _buildExamCard(_examResult![index]),
    );
  }

  Widget _buildExamCard(Map<String, dynamic> item) {
    final diem = item['diem'] ?? {};
    String fmt(dynamic v) => (v == null || v.toString().isEmpty) ? "---" : v.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: vinhUniBlue),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: vinhUniBlue.withOpacity(0.04),
                      child: Row(
                        children: [
                          Icon(Icons.assignment_turned_in_rounded, size: 18, color: vinhUniBlue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item['ten_mon'] ?? "Chứng chỉ",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF34495E))),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _infoMini("Phòng", item['phong_thi'] ?? "---", Icons.location_on),
                              _infoMini("Ngày thi", item['ngay_thi'] ?? "---", Icons.calendar_month),
                              _infoMini("Bậc đạt", diem['bac'] ?? "---", Icons.military_tech),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                          Row(
                            children: [
                              _scoreBox("Nghe", fmt(diem['nghe'])),
                              _scoreBox("Nói", fmt(diem['noi'])),
                              _scoreBox("Đọc", fmt(diem['doc'])),
                              _scoreBox("Viết", fmt(diem['viet'])),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: vinhUniBlue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("TỔNG ĐIỂM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(fmt(diem['tong']),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: vinhUniBlue)),
                              ],
                            ),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────────

  Widget _buildDropdown(String label, String? value, List<DropdownMenuItem<String>> items, Function(String?) onChanged, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: vinhUniBlue.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vinhUniBlue.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Text(label, style: TextStyle(fontSize: 13, color: vinhUniBlue.withOpacity(0.6))),
          icon: Icon(icon, color: vinhUniBlue.withOpacity(0.7), size: 20),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(width: 8),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: vinhUniBlue)),
      ],
    );
  }

  Widget _infoMini(String label, String val, IconData icon) => Column(
    children: [
      Icon(icon, size: 16, color: Colors.grey),
      const SizedBox(height: 4),
      Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
    ],
  );

  Widget _scoreBox(String label, String score) => Expanded(
    child: Column(
      children: [
        Text(score, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2C3E50))),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
  );
}