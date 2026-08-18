import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/auth/session.dart';
import '../../core/auth/user_role.dart';
import '../../services/signature_service.dart';

const Color _xanhVinhUni = Color(0xFF0054A6);

/// Màn hình ký số văn bản và kiểm tra chữ ký.
///
/// Hai thẻ riêng vì hai việc phục vụ hai đối tượng khác nhau:
///   • Ký văn bản   — chỉ cán bộ, giảng viên
///   • Kiểm tra     — mọi người, kể cả sinh viên nhận giấy tờ muốn tự xác minh
class KySoScreen extends StatefulWidget {
  const KySoScreen({super.key});

  @override
  State<KySoScreen> createState() => _KySoScreenState();
}

class _KySoScreenState extends State<KySoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  UserRole _vaiTro = UserRole.sinhVien;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _napVaiTro();
  }

  Future<void> _napVaiTro() async {
    final vt = await Session.role;
    if (!mounted) return;
    setState(() {
      _vaiTro = vt;
      // Sinh viên không ký được — mở thẳng thẻ kiểm tra để đỡ một thao tác thừa
      if (!vt.canSignDocument) _tab.index = 1;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: _xanhVinhUni,
        foregroundColor: Colors.white,
        title: const Text('Chữ ký số',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.draw_rounded), text: 'Ký văn bản'),
            Tab(icon: Icon(Icons.verified_user_rounded), text: 'Kiểm tra'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _vaiTro.canSignDocument
              ? const _TabKyVanBan()
              : const _ThongBaoKhongCoQuyen(),
          const _TabKiemTra(),
        ],
      ),
    );
  }
}

// ===========================================================================
// Thẻ 1 — Ký văn bản
// ===========================================================================

class _TabKyVanBan extends StatefulWidget {
  const _TabKyVanBan();

  @override
  State<_TabKyVanBan> createState() => _TabKyVanBanState();
}

class _TabKyVanBanState extends State<_TabKyVanBan> {
  File? _tep;
  MucKySo _muc = MucKySo.lt;
  final _lyDo = TextEditingController(text: 'Phê duyệt văn bản');
  bool _dangKy = false;
  double _tienDo = 0;
  KetQuaKy? _ketQua;
  Map<String, dynamic>? _trangThai;

  @override
  void initState() {
    super.initState();
    _kiemTraSanSang();
  }

  @override
  void dispose() {
    _lyDo.dispose();
    super.dispose();
  }

  /// Hỏi máy chủ xem hệ thống ký số đã sẵn sàng chưa, để báo trước cho người
  /// dùng thay vì để họ chọn tệp, bấm ký rồi mới nhận thông báo lỗi.
  Future<void> _kiemTraSanSang() async {
    final tt = await SignatureService.layTrangThai();
    if (mounted) setState(() => _trangThai = tt);
  }

  Future<void> _chonTep() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res?.files.single.path != null) {
      setState(() {
        _tep = File(res!.files.single.path!);
        _ketQua = null;
      });
    }
  }

  Future<void> _ky() async {
    if (_tep == null) return;
    setState(() {
      _dangKy = true;
      _tienDo = 0;
      _ketQua = null;
    });

    final kq = await SignatureService.ky(
      tepPdf: _tep!,
      lyDo: _lyDo.text.trim(),
      muc: _muc,
      tienDo: (gui, tong) {
        if (tong > 0 && mounted) setState(() => _tienDo = gui / tong);
      },
    );

    if (!mounted) return;
    setState(() {
      _dangKy = false;
      _ketQua = kq;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chuaSanSang = _trangThai != null && _trangThai!['da_cau_hinh'] != true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (chuaSanSang) ...[
          _Bang(
            mau: const Color(0xFFB23A2E),
            bieuTuong: Icons.error_outline_rounded,
            tieuDe: 'Hệ thống ký số chưa được cấu hình',
            noiDung: 'Quản trị viên cần khai báo chứng thư số trong tệp cấu hình '
                'trước khi chức năng này dùng được.',
          ),
          const SizedBox(height: 14),
        ] else if (_trangThai?['co_dau_thoi_gian'] == false) ...[
          _Bang(
            mau: const Color(0xFF96631A),
            bieuTuong: Icons.schedule_rounded,
            tieuDe: 'Chưa có dịch vụ cấp dấu thời gian',
            noiDung: 'Chữ ký sẽ mất hiệu lực khi chứng thư hết hạn, '
                'chưa đủ điều kiện dùng cho hồ sơ dịch vụ công.',
          ),
          const SizedBox(height: 14),
        ],

        // --- Chọn tệp ---
        _The(
          tieuDe: '1. Chọn văn bản',
          con: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tep != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EFF8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: _xanhVinhUni),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tep!.path.split(Platform.pathSeparator).last,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(_tep!.lengthSync() / 1024).toStringAsFixed(0)} KB',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        _tep = null;
                        _ketQua = null;
                      }),
                    ),
                  ]),
                )
              else
                OutlinedButton.icon(
                  onPressed: _chonTep,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Chọn tệp PDF'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: _xanhVinhUni,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // --- Thông tin ký ---
        _The(
          tieuDe: '2. Thông tin ký',
          con: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _lyDo,
                decoration: const InputDecoration(
                  labelText: 'Lý do ký',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Mức chữ ký',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              ...MucKySo.values.map(
                (m) => RadioListTile<MucKySo>(
                  value: m,
                  groupValue: _muc,
                  onChanged: (v) => setState(() => _muc = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: _xanhVinhUni,
                  title: Text(m.ten, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(m.moTa,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // --- Nút ký ---
        if (_dangKy) ...[
          LinearProgressIndicator(value: _tienDo > 0 ? _tienDo : null),
          const SizedBox(height: 8),
          const Center(
            child: Text('Đang ký, vui lòng đợi…',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          ),
        ] else
          FilledButton.icon(
            onPressed: (_tep == null || chuaSanSang) ? null : _ky,
            icon: const Icon(Icons.draw_rounded),
            label: const Text('KÝ SỐ VĂN BẢN'),
            style: FilledButton.styleFrom(
              backgroundColor: _xanhVinhUni,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        if (_ketQua != null) ...[
          const SizedBox(height: 18),
          _KetQuaKyWidget(ketQua: _ketQua!),
        ],
      ],
    );
  }
}

class _KetQuaKyWidget extends StatelessWidget {
  const _KetQuaKyWidget({required this.ketQua});

  final KetQuaKy ketQua;

  @override
  Widget build(BuildContext context) {
    if (!ketQua.thanhCong) {
      return _Bang(
        mau: const Color(0xFFB23A2E),
        bieuTuong: Icons.cancel_rounded,
        tieuDe: 'Ký không thành công',
        noiDung: ketQua.loi,
      );
    }

    return _The(
      tieuDe: 'Đã ký thành công',
      mauTieuDe: const Color(0xFF1D6A4C),
      con: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Dong('Mã văn bản', ketQua.maVanBan),
          _Dong('Mức đạt được', ketQua.mucDatDuoc),
          _Dong('Thời điểm ký', ketQua.thoiDiemKy),
          _Dong('Mã kiểm tra', '${ketQua.maBamDaKy.substring(0, 16)}…'),
          if (ketQua.canhBao.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...ketQua.canhBao.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Color(0xFF96631A)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(c,
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF96631A))),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Thẻ 2 — Kiểm tra chữ ký
// ===========================================================================

class _TabKiemTra extends StatefulWidget {
  const _TabKiemTra();

  @override
  State<_TabKiemTra> createState() => _TabKiemTraState();
}

class _TabKiemTraState extends State<_TabKiemTra> {
  File? _tep;
  bool _dangKiemTra = false;
  KetQuaKiemTra? _ketQua;
  String? _loi;

  Future<void> _chonVaKiemTra() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res?.files.single.path == null) return;

    setState(() {
      _tep = File(res!.files.single.path!);
      _dangKiemTra = true;
      _ketQua = null;
      _loi = null;
    });

    final kq = await SignatureService.kiemTra(_tep!);
    if (!mounted) return;
    setState(() {
      _dangKiemTra = false;
      _ketQua = kq;
      if (kq == null) _loi = 'Không kiểm tra được. Vui lòng thử lại.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Bang(
          mau: _xanhVinhUni,
          bieuTuong: Icons.info_outline_rounded,
          tieuDe: 'Xác minh văn bản bạn nhận được',
          noiDung: 'Chọn tệp PDF để kiểm tra ai đã ký, ký lúc nào, '
              'và nội dung có bị sửa sau khi ký hay không.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _dangKiemTra ? null : _chonVaKiemTra,
          icon: const Icon(Icons.file_open_rounded),
          label: Text(_tep == null ? 'Chọn tệp PDF để kiểm tra' : 'Chọn tệp khác'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: _xanhVinhUni,
          ),
        ),
        if (_dangKiemTra) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_loi != null) ...[
          const SizedBox(height: 16),
          _Bang(
            mau: const Color(0xFFB23A2E),
            bieuTuong: Icons.error_outline_rounded,
            tieuDe: 'Lỗi',
            noiDung: _loi!,
          ),
        ],
        if (_ketQua != null) ...[
          const SizedBox(height: 16),
          _KetQuaKiemTraWidget(ketQua: _ketQua!),
        ],
      ],
    );
  }
}

class _KetQuaKiemTraWidget extends StatelessWidget {
  const _KetQuaKiemTraWidget({required this.ketQua});

  final KetQuaKiemTra ketQua;

  @override
  Widget build(BuildContext context) {
    if (!ketQua.coChuKy) {
      return const _Bang(
        mau: Color(0xFF96631A),
        bieuTuong: Icons.help_outline_rounded,
        tieuDe: 'Văn bản chưa được ký số',
        noiDung: 'Tệp này không chứa chữ ký số nào. '
            'Nếu đây là giấy tờ do trường cấp, hãy liên hệ đơn vị phát hành.',
      );
    }

    final tot = ketQua.tatCaHopLe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bang(
          mau: tot ? const Color(0xFF1D6A4C) : const Color(0xFFB23A2E),
          bieuTuong: tot ? Icons.verified_rounded : Icons.gpp_bad_rounded,
          tieuDe: tot ? 'Văn bản hợp lệ' : 'Chữ ký có vấn đề',
          noiDung: ketQua.ketLuan,
        ),
        const SizedBox(height: 14),
        ...ketQua.chuKy.map((ck) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _The(
                tieuDe: ck.nguoiKy.isEmpty ? 'Chữ ký' : ck.nguoiKy,
                con: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DongTrangThai('Nội dung nguyên vẹn', ck.nguyenVen),
                    _DongTrangThai('Chứng thư tin cậy', ck.chungThuTinCay),
                    _DongTrangThai('Có dấu thời gian', ck.coDauThoiGian),
                    const SizedBox(height: 8),
                    if (ck.toChucCap.isNotEmpty) _Dong('Tổ chức cấp', ck.toChucCap),
                    if (ck.thoiDiemKy.isNotEmpty) _Dong('Thời điểm ký', ck.thoiDiemKy),
                    _Dong('Mức chữ ký', ck.mucDatDuoc),
                    ...ck.canhBao.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('⚠️ $c',
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF96631A))),
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

// ===========================================================================
// Thành phần dùng lại
// ===========================================================================

class _ThongBaoKhongCoQuyen extends StatelessWidget {
  const _ThongBaoKhongCoQuyen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 56, color: Colors.black26),
            SizedBox(height: 16),
            Text('Chức năng dành cho cán bộ, giảng viên',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text('Bạn vẫn có thể dùng thẻ "Kiểm tra" để xác minh '
                'các văn bản do trường cấp.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _The extends StatelessWidget {
  const _The({required this.tieuDe, required this.con, this.mauTieuDe});

  final String tieuDe;
  final Widget con;
  final Color? mauTieuDe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE3EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tieuDe,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: mauTieuDe ?? _xanhVinhUni,
              )),
          const SizedBox(height: 12),
          con,
        ],
      ),
    );
  }
}

class _Bang extends StatelessWidget {
  const _Bang({
    required this.mau,
    required this.bieuTuong,
    required this.tieuDe,
    required this.noiDung,
  });

  final Color mau;
  final IconData bieuTuong;
  final String tieuDe;
  final String noiDung;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mau.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: mau, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(bieuTuong, color: mau, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tieuDe,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: mau)),
            const SizedBox(height: 4),
            Text(noiDung,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _Dong extends StatelessWidget {
  const _Dong(this.nhan, this.giaTri);

  final String nhan;
  final String giaTri;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 118,
          child: Text(nhan,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        Expanded(
          child: Text(giaTri,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _DongTrangThai extends StatelessWidget {
  const _DongTrangThai(this.nhan, this.dat);

  final String nhan;
  final bool dat;

  @override
  Widget build(BuildContext context) {
    final mau = dat ? const Color(0xFF1D6A4C) : const Color(0xFFB23A2E);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(dat ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 17, color: mau),
        const SizedBox(width: 8),
        Text(nhan, style: const TextStyle(fontSize: 13.5)),
      ]),
    );
  }
}
