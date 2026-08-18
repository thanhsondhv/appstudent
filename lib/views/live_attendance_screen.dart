import 'package:flutter/material.dart';
import '../core/api/may_chu.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'qr_generator_screen.dart';
import '../core/api/api.dart';

class LiveAttendanceScreen extends StatefulWidget {
  final int buoiHocId;
  final String lhpCode;
  final String lecturerId;

  const LiveAttendanceScreen({super.key, required this.buoiHocId, required this.lhpCode, required this.lecturerId});

  @override
  State<LiveAttendanceScreen> createState() => _LiveAttendanceScreenState();
}

class _LiveAttendanceScreenState extends State<LiveAttendanceScreen> {
  List<dynamic> _list = []; 
  int _present = 0;
  String _currentPin = "----";
  Timer? _timer;
  
  double _durationMinutes = 10; // Thời gian mặc định cho mã mới
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Cập nhật cả mã PIN và danh sách mỗi 4 giây
    _timer = Timer.periodic(const Duration(seconds: 4), (t) {
      _fetchLiveInfo();
      _fetchAttendanceList();
    });
    _fetchLiveInfo();
    _fetchAttendanceList();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  // 1. Lấy thông tin mã PIN
  Future<void> _fetchLiveInfo() async {
  try {
    final res = await Api.get("/api/attendance/current-session-info/${widget.buoiHocId}");
    if (res.thanhCong) {
      final data = res.data is Map ? res.data as Map : const {};
      if (mounted) {
        setState(() {
          if (data['code'] == "EXPIRED") {
            _currentPin = "HẾT HẠN";
            // 🔥 NGỪNG REQUEST: Hết hạn thì không cần quét PIN nữa
            _timer?.cancel(); 
            print("🛑 Đã dừng Timer vì phiên điểm danh hết hạn.");
          } else {
            _currentPin = data['code'].toString();
          }
        });
      }
    }
  } catch (e) {
    debugPrint("Lỗi PIN: $e");
  }
}

  // 2. Lấy danh sách SV
  Future<void> _fetchAttendanceList() async {
    try {
      final res = await Api.get("/api/attendance/session-report/${widget.buoiHocId}");
      if (res.thanhCong) {
        final data = res.data is Map ? res.data as Map : const {};
        if (mounted && data['status'] == 'success') {
          setState(() {
            _list = data['data'] ?? [];
            _present = data['present_count'] ?? 0;
          });
        }
      }
    } catch (e) { debugPrint("Lỗi List: $e"); }
  }

  // 3. Cấp mã mới với thời gian tùy chỉnh
  Future<void> _renewPin() async {
  setState(() => _isRefreshing = true);
  try {
    final res = await Api.post(
      "/api/attendance/refresh-pin",
      duLieu: {"buoi_id": widget.buoiHocId, "duration": _durationMinutes.toInt()},
    );
    if (!mounted) return;

    if (!res.thanhCong) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.thongDiepLoi), backgroundColor: Colors.red),
      );
    } else {
      // 🔥 KÍCH HOẠT LẠI TIMER: Nếu trước đó đã dừng, giờ phải chạy lại để cập nhật SV mới quét
      _timer?.cancel(); // Xóa timer cũ nếu còn
      _timer = Timer.periodic(const Duration(seconds: 4), (t) {
        _fetchLiveInfo();
        _fetchAttendanceList();
      });
      
      _fetchLiveInfo();
      _fetchAttendanceList();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Đã cấp mã mới: ${_durationMinutes.toInt()} phút. Đang đồng bộ...")));
    }
  } finally {
    setState(() => _isRefreshing = false);
  }
}

  // 4. Điểm danh thủ công
  Future<void> _updateManualStatus(String sid, int loaiVang) async {
    try {
      final res = await Api.post(
        "/api/attendance/manual-submit",
        duLieu: {
          "buoi_hoc_id": widget.buoiHocId,
          "student_id": sid,
          "loai_vang": loaiVang,
        },
      );
      if (!mounted) return;

      if (!res.thanhCong) {
        // Sửa 18/08/2026: bản cũ gọi rồi bỏ qua phản hồi. Máy chủ từ chối thì
        // giảng viên vẫn thấy màn hình như đã ghi nhận — nhưng dữ liệu điểm
        // danh không được lưu, ảnh hưởng trực tiếp tới điểm chuyên cần.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Chưa ghi được điểm danh cho $sid: ${res.thongDiepLoi}"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      _fetchAttendanceList();
    } catch (e) {
      debugPrint("Lỗi điểm danh thủ công: $e");
    }
  }

  // 5. Kết thúc buổi học
  Future<void> _endSession() async {
  bool confirm = await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Xác nhận"),
      content: const Text("Bạn muốn kết thúc buổi điểm danh này ngay lập tức?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
        TextButton(onPressed: () => Navigator.pop(ctx, true), 
          child: const Text("KẾT THÚC", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ),
  ) ?? false;

  if (confirm) {
    final res = await Api.post("/api/attendance/end-session/${widget.buoiHocId}");
    if (!mounted) return;

    if (!res.thanhCong) {
      // Không báo lỗi thì giảng viên tưởng đã đóng phiên, rời đi, trong khi mã
      // PIN vẫn còn hiệu lực và sinh viên vắng mặt vẫn điểm danh được.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Chưa đóng được phiên: ${res.thongDiepLoi}"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _currentPin = "ĐÃ ĐÓNG";
      // 🔥 NGỪNG REQUEST NGAY LẬP TỨC
      _timer?.cancel();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🚩 Phiên điểm danh đã đóng. Đã ngừng đồng bộ dữ liệu.")),
    );
  }
}

  // 6. Thống kê nhanh
  void _showStats() {
    int muon = _list.where((e) => e['loai_vang'] == 1).length;
    int coPhep = _list.where((e) => e['loai_vang'] == 2).length;
    int vang = _list.where((e) => (e['status'] == 'Vang' && e['loai_vang'] != 2) || e['loai_vang'] == 3).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Thống kê lớp học", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statRow("Sĩ số:", "${_list.length}", Colors.black),
            _statRow("✅ Có mặt:", "$_present", Colors.green),
            _statRow("🕒 Muộn:", "$muon", Colors.orange),
            _statRow("📝 Có phép:", "$coPhep", Colors.blue),
            _statRow("❌ Vắng:", "$vang", Colors.red),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ĐÓNG"))],
      ),
    );
  }

  Widget _statRow(String label, String val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(val, style: TextStyle(fontWeight: FontWeight.bold, color: c))]),
  );

  // 7. Xuất Excel
  Future<void> _exportExcel() async {
    final String urlStr = "${MayChu.diaChi}/api/attendance/export-excel/${Uri.encodeComponent(widget.lhpCode)}";
    if (await canLaunchUrl(Uri.parse(urlStr))) {
      await launchUrl(Uri.parse(urlStr), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isExpired = _currentPin == "HẾT HẠN";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text("LIVE: ${widget.lhpCode}", style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0054A6),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart, color: Colors.white), onPressed: _showStats),
          IconButton(icon: const Icon(Icons.file_download, color: Colors.white), onPressed: _exportExcel),
        ],
      ),
      body: Column(
        children: [
          // PANEL ĐIỀU KHIỂN PIN
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.blue.shade50, border: Border(bottom: BorderSide(color: Colors.blue.shade100))),
            child: Column(children: [
              Text(isExpired ? "MÃ ĐÃ HẾT HẠN" : "MÃ PIN ĐANG HIỆU LỰC", 
                style: TextStyle(fontSize: 11, color: isExpired ? Colors.red : Colors.blueGrey, fontWeight: FontWeight.bold)),
              Text(_currentPin, style: TextStyle(fontSize: 55, fontWeight: FontWeight.bold, letterSpacing: 8, color: isExpired ? Colors.red : const Color(0xFF0054A6))),
              
              // SLIDER THỜI GIAN
              Row(children: [
                const Icon(Icons.timer_outlined, size: 18, color: Colors.orange),
                Expanded(
                  child: Slider(
                    value: _durationMinutes,
                    min: 5, max: 30, divisions: 5,
                    label: "${_durationMinutes.toInt()} phút",
                    activeColor: Colors.orange,
                    onChanged: (v) => setState(() => _durationMinutes = v),
                  ),
                ),
                Text("${_durationMinutes.toInt()} p", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ]),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => QRGeneratorScreen(attendanceCode: _currentPin, className: widget.lhpCode))),
                  icon: const Icon(Icons.qr_code_2), label: const Text("QR TO"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.black),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isRefreshing ? null : _renewPin,
                  icon: _isRefreshing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                  label: const Text("CẤP MÃ"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _endSession,
                  icon: const Icon(Icons.power_settings_new, size: 18), label: const Text("ĐÓNG"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                ),
              ]),
              const SizedBox(height: 10),
              Text("Đã có mặt: $_present / ${_list.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0054A6))),
            ]),
          ),

          // DANH SÁCH SINH VIÊN
          Expanded(
            child: _list.isEmpty 
              ? const Center(child: Text("Đang tải danh sách..."))
              : ListView.separated(
                  itemCount: _list.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final sv = _list[idx];
                    bool ok = sv['status'] == 'CoMat';
                    int loai = sv['loai_vang'] ?? 0;
                    
                    // Xác định màu sắc Icon
                    Color statusColor = Colors.grey;
                    if (ok) statusColor = (loai == 1) ? Colors.orange : Colors.green;
                    else if (loai == 2) statusColor = Colors.blue;
                    else if (loai == 3) statusColor = Colors.red;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage("${MayChu.diaChi}/api/get-avatar/${sv['sid']}"),
                      ),
                      title: Text(sv['name'] ?? "Không rõ tên", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text("${sv['sid']} | ${sv['time'] ?? '---'}"),
                      trailing: PopupMenuButton<int>(
                        icon: Icon(ok ? Icons.check_circle : Icons.more_horiz, color: statusColor, size: 28),
                        onSelected: (v) => _updateManualStatus(sv['sid'], v),
                        itemBuilder: (c) => [
                          const PopupMenuItem(value: 0, child: Text("✅ Có mặt")),
                          const PopupMenuItem(value: 1, child: Text("🕒 Đi muộn")),
                          const PopupMenuItem(value: 2, child: Text("📝 Có phép")),
                          const PopupMenuItem(value: 3, child: Text("❌ Vắng")),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}