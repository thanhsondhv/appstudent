import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 

class MoDiemDanhScreen extends StatefulWidget {
  final String lecturerId;
  const MoDiemDanhScreen({super.key, required this.lecturerId});

  @override
  State<MoDiemDanhScreen> createState() => _MoDiemDanhScreenState();
}

class _MoDiemDanhScreenState extends State<MoDiemDanhScreen> {
  // --- BIẾN TRẠNG THÁI ---
  String? _selectedLhp;
  String _generatedCode = "";
  bool _isLoading = false;
  bool _isFetching = false; // Chống gọi API chồng chéo
  List _myClasses = [];
  List _attendanceReport = [];
  int _presentCount = 0;
  
  // Chỉ dùng 1 Timer duy nhất để quản lý
  Timer? _attendanceTimer;

  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void initState() {
    super.initState();
    // 1. Tải danh sách lớp ngay khi vào màn hình
    _fetchMyClasses();
  }

  @override
  void dispose() {
    // 2. Hủy Timer ngay lập tức khi thoát để tránh lỗi "Xác sống" và Timeout
    _attendanceTimer?.cancel();
    debugPrint("✅ Đã dừng cập nhật danh sách ngầm.");
    super.dispose();
  }

  // --- 1. LẤY DANH SÁCH LỚP DẠY ---
  Future<void> _fetchMyClasses() async {
    const String nam = "2025-2026"; 
    const String ky = "Học kỳ 1";
    // Đảm bảo ID cán bộ đã được dọn dẹp "CB"
    final cleanId = widget.lecturerId.replaceAll("CB", "");
    final url = "https://mobi.vinhuni.edu.vn/api/lecturer/classes-filtered?lecturer_id=$cleanId&nam=$nam&ky=$ky";
    
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(res.body);
        if (responseData['status'] == 'success') {
          setState(() {
            _myClasses = responseData['data'] ?? []; 
            if (_myClasses.isNotEmpty) {
              _selectedLhp = _myClasses[0]['ma_lop']?.toString();
            }
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Lỗi tải danh sách lớp: $e");
    }
  }

  // --- 2. SINH MÃ PIN & BẮT ĐẦU THEO DÕI ---
  Future<void> _generatePin() async {
    if (_selectedLhp == null) {
      _showSnackBar("Vui lòng chọn một lớp học phần!", Colors.orange);
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/create-session"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "lhp_code": _selectedLhp,
          "lecturer_id": widget.lecturerId,
          "type": "PIN",
          "lat": 18.659, // Tọa độ thực tế của GV
          "lon": 105.695,
        }),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          _generatedCode = data['code']?.toString() ?? "";
        });

        // 🔥 KÍCH HOẠT THEO DÕI REAL-TIME MỖI 5 GIÂY
        _attendanceTimer?.cancel();
        _attendanceTimer = Timer.periodic(const Duration(seconds: 5), (t) => _fetchAttendanceData());
        _fetchAttendanceData(); // Chạy ngay lập tức lần đầu
        
      } else {
        _showSnackBar(data['message'] ?? "Không thể sinh mã", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Lỗi kết nối Server", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 3. LẤY DỮ LIỆU ĐIỂM DANH (Gộp hàm để tránh trùng lặp) ---
  Future<void> _fetchAttendanceData() async {
    // Nếu đang bận lấy dữ liệu hoặc chưa chọn lớp thì bỏ qua
    if (_isFetching || _selectedLhp == null) return;
    
    _isFetching = true;
    try {
      final url = "https://mobi.vinhuni.edu.vn/api/attendance/session-report/$_selectedLhp";
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          if (mounted) { // Kiểm tra xem màn hình còn tồn tại không
            setState(() {
              _attendanceReport = data['data'] ?? [];
              _presentCount = data['present_count'] ?? 0;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("📡 Lỗi cập nhật danh sách ngầm: $e");
    } finally {
      _isFetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("MỞ PHIÊN ĐIỂM DANH", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("1. Chọn lớp học phần đang dạy:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),
            
            // --- DROPDOWN CHỌN LỚP ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedLhp,
                  hint: const Text("Chọn lớp..."),
                  items: _myClasses.map((c) => DropdownMenuItem<String>(
                    value: c['ma_lop']?.toString(), 
                    child: Text(c['ten_lop']?.toString() ?? "Không rõ tên", style: const TextStyle(fontSize: 13))
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedLhp = v),
                ),
              ),
            ),
            
            const SizedBox(height: 25),

            // --- NÚT SINH MÃ ---
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _generatePin,
                icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.bolt, color: Colors.white),
                label: const Text("SINH MÃ PIN ĐIỂM DANH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),

            // --- HIỂN THỊ MÃ PIN ---
            if (_generatedCode.isNotEmpty) ...[
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    const Text("MÃ ĐIỂM DANH CỦA LỚP:", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.blue.shade200, width: 2),
                        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Text(
                        _generatedCode,
                        style: TextStyle(fontSize: 65, fontWeight: FontWeight.bold, letterSpacing: 12, color: vinhUniBlue),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text("Mã có hiệu lực trong 10 phút", style: TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),

              const Divider(height: 60),

              // --- DANH SÁCH SINH VIÊN ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("DANH SÁCH LỚP (${_attendanceReport.length} SV)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                    child: Text("CÓ MẶT: $_presentCount", style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              ListView.builder(
                shrinkWrap: true, 
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _attendanceReport.length,
                itemBuilder: (ctx, idx) {
                  final sv = _attendanceReport[idx];
                  bool isPresent = sv['is_present'] ?? false;
                  final String sid = sv['sid']?.toString() ?? "";

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey.shade200,
                        // ✅ SỬA LỖI 404: Kiểm tra ID rỗng trước khi tải ảnh
                        backgroundImage: (sid.isNotEmpty) 
                          ? NetworkImage("https://mobi.vinhuni.edu.vn/api/get-avatar/$sid")
                          : null,
                        child: sid.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                      ),
                      title: Text(sv['name'] ?? "Sinh viên", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isPresent ? Colors.black : Colors.grey)),
                      subtitle: Text(sid, style: const TextStyle(fontSize: 11)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isPresent ? "ĐÃ CÓ MẶT" : "VẮNG",
                            style: TextStyle(color: isPresent ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                          if (isPresent) Text(sv['time'] ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
}