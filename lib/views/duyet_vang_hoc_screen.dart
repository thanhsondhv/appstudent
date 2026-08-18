import 'package:flutter/material.dart';

import '../core/api/api.dart';

/// Màn hình cán bộ, giảng viên duyệt đơn xin phép nghỉ học của sinh viên.
///
/// Sửa ngày 18/08/2026 (Pha 1) — ba vấn đề ở bản cũ:
///
///   1. `future: http.get(...)` đặt thẳng trong `build()`, nên mỗi lần màn hình
///      vẽ lại là gọi mạng thêm một lần. Việc "làm mới danh sách" cũng dựa vào
///      lỗi này: gọi `setState(() {})` cho `build()` chạy lại rồi vô tình gọi
///      API. Nay danh sách được nạp có chủ đích qua [_taiDanhSach].
///
///   2. Nút "DUYỆT" trong hộp thoại chỉ đóng hộp thoại chứ không gọi gì:
///      `onPressed: () { /* Logic Duyệt đơn */ Navigator.pop(ctx); }`
///      Hàm `_handleUpdateStatus` có sẵn nhưng không nơi nào gọi tới — nghĩa là
///      chức năng duyệt đơn xin phép chưa từng hoạt động. Cũng không có nút từ
///      chối. Nay cả hai nút đều nối vào máy chủ thật.
///
///   3. Máy chủ trả lỗi thì không báo gì, cán bộ tưởng đã duyệt xong.
class DuyetVangHocScreen extends StatefulWidget {
  final String lecturerId; // Đây là mã CB
  const DuyetVangHocScreen({super.key, required this.lecturerId});

  @override
  State<DuyetVangHocScreen> createState() => _DuyetVangHocScreenState();
}

class _DuyetVangHocScreenState extends State<DuyetVangHocScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);

  List<dynamic> _danhSach = [];
  bool _dangTai = true;
  String _loi = '';

  /// Mã cán bộ đã bỏ tiền tố CB.
  ///
  /// Dùng `replaceFirst` chứ không phải `replaceAll`: mã nào có "CB" ở giữa thì
  /// `replaceAll` sẽ cắt nhầm.
  String get _maCanBo => widget.lecturerId.toUpperCase().replaceFirst('CB', '');

  @override
  void initState() {
    super.initState();
    _taiDanhSach();
  }

  Future<void> _taiDanhSach() async {
    if (mounted) setState(() => _dangTai = true);

    final res = await Api.get('/api/lecturer/student-messages/$_maCanBo');
    if (!mounted) return;

    if (!res.thanhCong) {
      setState(() {
        _dangTai = false;
        _loi = res.thongDiepLoi;
      });
      return;
    }

    final duLieu = res.data;
    setState(() {
      _danhSach = (duLieu is Map ? duLieu['data'] : duLieu) as List? ?? [];
      _dangTai = false;
      _loi = '';
    });
  }

  /// Duyệt (status 1) hoặc từ chối (status 2) một đơn.
  Future<void> _capNhatTrangThai(int maDon, int trangThaiMoi) async {
    final res = await Api.post(
      '/api/attendance/lecturer/update-attendance-status',
      duLieu: {
        'request_id': maDon,
        'status': trangThaiMoi, // 1: Duyệt, 2: Từ chối
      },
    );
    if (!mounted) return;

    final duLieu = res.data is Map ? res.data as Map : const {};
    final thanhCong = res.thanhCong && duLieu['status'] == 'success';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          thanhCong
              ? (trangThaiMoi == 1
                  ? "✅ Đã duyệt và gửi thông báo cho sinh viên"
                  : "Đã từ chối đơn xin phép")
              : "Chưa xử lý được đơn: ${duLieu['message'] ?? res.thongDiepLoi}",
        ),
        backgroundColor: thanhCong
            ? (trangThaiMoi == 1 ? Colors.green : Colors.orange)
            : Colors.red,
      ),
    );

    if (thanhCong) await _taiDanhSach();
  }

  void _moHopThoaiXuLy(dynamic don) {
    final maDon = int.tryParse(
      (don['request_id'] ?? don['id'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xử lý đơn xin phép",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Sinh viên: ${don['student_name']}",
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text("Lớp: ${don['lhp_name']}", style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text("Lý do: ${don['reason']}", style: const TextStyle(fontSize: 13)),
            if (maDon == null) ...[
              const SizedBox(height: 12),
              const Text(
                "Không đọc được mã đơn nên chưa xử lý được. "
                "Vui lòng báo bộ phận kỹ thuật.",
                style: TextStyle(fontSize: 12.5, color: Color(0xFFB23A2E)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ĐÓNG", style: TextStyle(color: Colors.grey)),
          ),
          if (maDon != null) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _capNhatTrangThai(maDon, 2);
              },
              child: const Text("TỪ CHỐI", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _capNhatTrangThai(maDon, 1);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("DUYỆT", style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("DUYỆT VẮNG HỌC",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _taiDanhSach,
            tooltip: "Tải lại",
          ),
        ],
      ),
      body: _dungThan(),
    );
  }

  Widget _dungThan() {
    if (_dangTai) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loi.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.black26),
              const SizedBox(height: 12),
              Text(_loi, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _taiDanhSach, child: const Text("Thử lại")),
            ],
          ),
        ),
      );
    }

    if (_danhSach.isEmpty) {
      return const Center(child: Text("Hiện không có đơn xin phép nào mới."));
    }

    return RefreshIndicator(
      onRefresh: _taiDanhSach,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _danhSach.length,
        itemBuilder: (ctx, idx) {
          final item = _danhSach[idx];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(15),
              title: Text(
                "SV: ${item['student_name']} (${item['student_id']})",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 5),
                  Text("Lớp: ${item['lhp_name']}",
                      style: const TextStyle(color: Colors.blue, fontSize: 12)),
                  Text("Lý do: ${item['reason']}",
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 5),
                  Text("Ngày gửi: ${item['time']}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              trailing: Icon(Icons.chevron_right, color: vinhUniBlue),
              onTap: () => _moHopThoaiXuLy(item),
            ),
          );
        },
      ),
    );
  }
}
