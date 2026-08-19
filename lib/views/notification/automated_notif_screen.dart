import 'package:flutter/material.dart';

import '../../core/api/api.dart';
import 'notification_helper.dart';

/// Cấu hình gửi thông báo tự động theo sự kiện.
///
/// ⚠️ VIẾT LẠI 19/08/2026.
///
/// Trước đó màn này là giao diện suông: hai công tắc chỉ đổi biến trong bộ nhớ
/// (rời màn là mất), ba mẫu tin có mũi tên nhưng bấm không ra gì, và phía máy
/// chủ KHÔNG có gì cả — không endpoint, không bảng cấu hình, không tác vụ nền.
///
/// Cán bộ bật "Chúc mừng sinh nhật" rồi tin rằng hệ thống sẽ tự gửi, mà nó
/// không bao giờ gửi.
///
/// Nay đã có đủ phía máy chủ:
///   • bảng `tbl_ThongBao_TuDong`, `tbl_ThongBao_TuDong_Log`, `tbl_NgayLe`
///   • hai tác vụ nền trong sync_and_notify_worker_new.py
///   • hai endpoint GET/POST /api/notifications/tu-dong
class AutomatedNotifScreen extends StatefulWidget {
  const AutomatedNotifScreen({super.key});

  @override
  State<AutomatedNotifScreen> createState() => _AutomatedNotifScreenState();
}

class _AutomatedNotifScreenState extends State<AutomatedNotifScreen> {
  bool _dangTai = true;
  String _loi = '';
  List<dynamic> _cauHinh = [];
  List<dynamic> _ngayLe = [];
  int _soSinhNhatHomNay = 0;

  @override
  void initState() {
    super.initState();
    _nap();
  }

  Future<void> _nap() async {
    setState(() { _dangTai = true; _loi = ''; });

    final res = await Api.get('/api/notifications/tu-dong');
    if (!mounted) return;

    if (!res.thanhCong) {
      setState(() {
        _dangTai = false;
        // 503 nghĩa là chưa chạy kịch bản tạo bảng trên máy chủ — nói thẳng
        // thay vì hiện một màn hình trống khó hiểu.
        _loi = res.thongDiepLoi.isNotEmpty
            ? res.thongDiepLoi
            : 'Không tải được cấu hình.';
      });
      return;
    }

    final d = res.data is Map ? res.data as Map : const {};
    setState(() {
      _dangTai = false;
      _cauHinh = (d['cau_hinh'] as List?) ?? [];
      _ngayLe = (d['ngay_le'] as List?) ?? [];
      _soSinhNhatHomNay = (d['so_sinh_nhat_hom_nay'] as int?) ?? 0;
    });
  }

  Future<void> _doiTrangThai(Map muc, bool bat) async {
    final truocDo = muc['bat'];
    setState(() => muc['bat'] = bat);

    final res = await Api.post('/api/notifications/tu-dong',
        duLieu: {'ma': muc['ma'], 'bat': bat});
    if (!mounted) return;

    if (res.thanhCong) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bat
              ? 'Đã bật. Hệ thống sẽ tự gửi lúc ${muc['gio_gui']}h hằng ngày.'
              : 'Đã tắt.'),
          backgroundColor: const Color(0xFF1D6A4C),
        ),
      );
      return;
    }

    // Máy chủ từ chối thì TRẢ LẠI trạng thái cũ — để công tắc bật mà không lưu
    // được là đúng cái sai của bản trước.
    setState(() => muc['bat'] = truocDo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Chưa lưu được. ${res.thongDiepLoi}'),
        backgroundColor: const Color(0xFFB3261E),
      ),
    );
  }

  Future<void> _doiGioGui(Map muc) async {
    final chon = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chọn giờ gửi hằng ngày',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var gio = 5; gio <= 20; gio++)
              ListTile(
                title: Text('$gio giờ'),
                trailing: muc['gio_gui'] == gio
                    ? const Icon(Icons.check, color: Color(0xFF0054A6))
                    : null,
                onTap: () => Navigator.pop(ctx, gio),
              ),
          ],
        ),
      ),
    );
    if (chon == null || !mounted) return;

    final truocDo = muc['gio_gui'];
    setState(() => muc['gio_gui'] = chon);

    final res = await Api.post('/api/notifications/tu-dong',
        duLieu: {'ma': muc['ma'], 'gio_gui': chon});
    if (!mounted) return;
    if (!res.thanhCong) {
      setState(() => muc['gio_gui'] = truocDo);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chưa lưu được. ${res.thongDiepLoi}'),
            backgroundColor: const Color(0xFFB3261E)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("TỰ ĐỘNG & SỰ KIỆN",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: NotificationHelper.vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _dangTai
          ? const Center(child: CircularProgressIndicator())
          : _loi.isNotEmpty
              ? _buildLoi()
              : RefreshIndicator(onRefresh: _nap, child: _buildNoiDung()),
    );
  }

  Widget _buildLoi() => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 46, color: Colors.grey),
              const SizedBox(height: 14),
              Text(_loi, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
              const SizedBox(height: 18),
              OutlinedButton(onPressed: _nap, child: const Text('Thử lại')),
            ],
          ),
        ),
      );

  Widget _buildNoiDung() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTieuDe("Cài đặt tự động"),
        for (final muc in _cauHinh) _buildTheCauHinh(muc as Map),
        const SizedBox(height: 22),
        _buildTieuDe("Ngày lễ đang theo dõi"),
        _buildDanhSachNgayLe(),
      ],
    );
  }

  Widget _buildTheCauHinh(Map muc) {
    final laSinhNhat = muc['ma'] == 'SINH_NHAT';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (laSinhNhat ? Colors.pink : Colors.orange).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  laSinhNhat ? Icons.cake_rounded : Icons.celebration_rounded,
                  color: laSinhNhat ? Colors.pink : Colors.orange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${muc['ten']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('${muc['tieu_de']}'.replaceAll('{ten}', 'bạn'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Switch(
                value: muc['bat'] == true,
                onChanged: (v) => _doiTrangThai(muc, v),
                activeThumbColor: NotificationHelper.vinhUniBlue,
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 17, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Gửi lúc ${muc['gio_gui']} giờ hằng ngày',
                    style: const TextStyle(fontSize: 12.5)),
              ),
              TextButton(onPressed: () => _doiGioGui(muc), child: const Text('Đổi giờ')),
            ],
          ),
          // Cho người dùng thấy con số thật thay vì bật một công tắc mù.
          if (laSinhNhat)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _soSinhNhatHomNay > 0
                      ? 'Hôm nay có $_soSinhNhatHomNay người sinh nhật đang dùng ứng dụng.'
                      : 'Hôm nay không có ai sinh nhật trong số người đang dùng ứng dụng.',
                  style: const TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDanhSachNgayLe() {
    if (_ngayLe.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Chưa khai ngày lễ nào.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey)),
      );
    }
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          for (final n in _ngayLe)
            ListTile(
              dense: true,
              leading: const Icon(Icons.event_rounded, size: 20, color: Colors.blueGrey),
              title: Text('${n['ten']}', style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${n['ngay']}/${n['thang']}'
                '${n['doi_tuong'] == 'CB' ? ' · chỉ cán bộ' : n['doi_tuong'] == 'SV' ? ' · chỉ sinh viên' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Icon(
                n['bat'] == true ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: n['bat'] == true ? const Color(0xFF1D6A4C) : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTieuDe(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1.2)),
      );
}
