import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'vinhuni_api_client.dart';

/// Mức chữ ký số theo chuẩn PAdES.
///
/// Với hồ sơ dịch vụ công cần tối thiểu [lt]: chữ ký vẫn kiểm tra được sau khi
/// chứng thư của người ký hết hạn. Mức [b] chỉ dùng cho văn bản nội bộ ngắn hạn.
enum MucKySo {
  b('PAdES-B-B', 'Cơ bản', 'Hết hiệu lực khi chứng thư hết hạn'),
  t('PAdES-B-T', 'Có dấu thời gian', 'Chứng minh được thời điểm ký'),
  lt('PAdES-B-LT', 'Lưu trữ dài hạn', 'Kiểm tra được sau nhiều năm — dùng cho dịch vụ công'),
  lta('PAdES-B-LTA', 'Lưu trữ vĩnh viễn', 'Gia hạn được nhiều thập kỷ');

  const MucKySo(this.ma, this.ten, this.moTa);

  final String ma;
  final String ten;
  final String moTa;
}

/// Kết quả một lần ký.
class KetQuaKy {
  const KetQuaKy({
    required this.thanhCong,
    this.maVanBan = '',
    this.mucDatDuoc = '',
    this.thoiDiemKy = '',
    this.maBamDaKy = '',
    this.duongDanTai = '',
    this.canhBao = const [],
    this.loi = '',
  });

  final bool thanhCong;
  final String maVanBan;
  final String mucDatDuoc;
  final String thoiDiemKy;
  final String maBamDaKy;
  final String duongDanTai;
  final List<String> canhBao;
  final String loi;

  factory KetQuaKy.tuJson(Map<String, dynamic> json) => KetQuaKy(
        thanhCong: json['thanh_cong'] == true,
        maVanBan: json['ma_van_ban']?.toString() ?? '',
        mucDatDuoc: json['muc_dat_duoc']?.toString() ?? '',
        thoiDiemKy: json['thoi_diem_ky']?.toString() ?? '',
        maBamDaKy: json['ma_bam_da_ky']?.toString() ?? '',
        duongDanTai: json['duong_dan_tai']?.toString() ?? '',
        canhBao: (json['canh_bao'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        loi: json['loi']?.toString() ?? '',
      );
}

/// Thông tin một chữ ký tìm thấy trong văn bản.
class ChuKy {
  const ChuKy({
    required this.hopLe,
    required this.nguyenVen,
    required this.chungThuTinCay,
    this.nguoiKy = '',
    this.toChucCap = '',
    this.thoiDiemKy = '',
    this.coDauThoiGian = false,
    this.mucDatDuoc = '',
    this.canhBao = const [],
  });

  final bool hopLe;

  /// Nội dung văn bản có bị sửa sau khi ký không. Đây là điều người nhận
  /// quan tâm nhất — chữ ký đúng nhưng nội dung đã sửa thì văn bản vô giá trị.
  final bool nguyenVen;

  final bool chungThuTinCay;
  final String nguoiKy;
  final String toChucCap;
  final String thoiDiemKy;
  final bool coDauThoiGian;
  final String mucDatDuoc;
  final List<String> canhBao;

  factory ChuKy.tuJson(Map<String, dynamic> json) => ChuKy(
        hopLe: json['hop_le'] == true,
        nguyenVen: json['nguyen_ven'] == true,
        chungThuTinCay: json['chung_thu_tin_cay'] == true,
        nguoiKy: json['nguoi_ky']?.toString() ?? '',
        toChucCap: json['to_chuc_cap']?.toString() ?? '',
        thoiDiemKy: json['thoi_diem_ky']?.toString() ?? '',
        coDauThoiGian: json['co_dau_thoi_gian'] == true,
        mucDatDuoc: json['muc_dat_duoc']?.toString() ?? '',
        canhBao: (json['canh_bao'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// Kết quả kiểm tra một văn bản.
class KetQuaKiemTra {
  const KetQuaKiemTra({
    required this.coChuKy,
    required this.tatCaHopLe,
    required this.ketLuan,
    this.chuKy = const [],
  });

  final bool coChuKy;
  final bool tatCaHopLe;
  final String ketLuan;
  final List<ChuKy> chuKy;

  factory KetQuaKiemTra.tuJson(Map<String, dynamic> json) => KetQuaKiemTra(
        coChuKy: json['co_chu_ky'] == true,
        tatCaHopLe: json['tat_ca_hop_le'] == true,
        ketLuan: json['ket_luan']?.toString() ?? '',
        chuKy: (json['chu_ky'] as List?)
                ?.map((e) => ChuKy.tuJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
}

/// Gọi các API ký số của máy chủ.
///
/// Đi qua [VinhUniClient] nên tự có token, mã thiết bị và xử lý lỗi 401/403
/// tập trung — không tự gọi `package:http` như phần lớn mã cũ.
class SignatureService {
  static const _duongDan = '/api/chu-ky-so';

  /// Tình trạng sẵn sàng của hệ thống ký số. Gọi trước khi hiện nút ký để
  /// báo trước cho người dùng thay vì để họ bấm rồi mới nhận lỗi.
  static Future<Map<String, dynamic>?> layTrangThai() async {
    try {
      final res = await VinhUniClient.instance.get('$_duongDan/trang-thai');
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      debugPrint('❌ [KýSố] Không lấy được trạng thái: ${e.message}');
      return null;
    }
  }

  /// Ký một tệp PDF.
  ///
  /// Người ký được máy chủ xác định từ token — ứng dụng không gửi lên tên người
  /// ký, vì nếu nhận được thì ai cũng ký thay lãnh đạo được.
  static Future<KetQuaKy> ky({
    required File tepPdf,
    String lyDo = 'Phê duyệt văn bản',
    String chucDanh = '',
    MucKySo muc = MucKySo.lt,
    bool hienThiChuKy = true,
    void Function(int daGui, int tong)? tienDo,
  }) async {
    try {
      final form = FormData.fromMap({
        'tep': await MultipartFile.fromFile(
          tepPdf.path,
          filename: tepPdf.path.split(Platform.pathSeparator).last,
        ),
        'ly_do': lyDo,
        'chuc_danh': chucDanh,
        'muc': muc.ma,
        'hien_thi_chu_ky': hienThiChuKy,
      });

      final res = await VinhUniClient.instance.post(
        '$_duongDan/ky',
        data: form,
        onSendProgress: tienDo,
      );
      return KetQuaKy.tuJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      return KetQuaKy(thanhCong: false, loi: _thongDiepLoi(e));
    } catch (e) {
      return KetQuaKy(thanhCong: false, loi: 'Lỗi không xác định: $e');
    }
  }

  /// Kiểm tra chữ ký của một văn bản. Sinh viên cũng dùng được để tự xác minh
  /// giấy tờ mình nhận.
  static Future<KetQuaKiemTra?> kiemTra(File tepPdf) async {
    try {
      final form = FormData.fromMap({
        'tep': await MultipartFile.fromFile(
          tepPdf.path,
          filename: tepPdf.path.split(Platform.pathSeparator).last,
        ),
      });
      final res = await VinhUniClient.instance.post('$_duongDan/kiem-tra', data: form);
      return KetQuaKiemTra.tuJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      debugPrint('❌ [KýSố] Kiểm tra thất bại: ${_thongDiepLoi(e)}');
      return null;
    }
  }

  /// Tải văn bản đã ký về máy.
  static Future<File?> taiVanBan(String maVanBan, String thuMucLuu) async {
    try {
      final duongDan = '$thuMucLuu/VinhUni_$maVanBan.pdf';
      await VinhUniClient.instance.download('$_duongDan/tai/$maVanBan', duongDan);
      return File(duongDan);
    } on DioException catch (e) {
      debugPrint('❌ [KýSố] Tải thất bại: ${_thongDiepLoi(e)}');
      return null;
    }
  }

  /// Diễn giải lỗi mạng thành câu người dùng hiểu được và biết phải làm gì.
  static String _thongDiepLoi(DioException e) {
    final chiTiet = e.response?.data is Map
        ? (e.response!.data as Map)['detail']?.toString()
        : null;

    return switch (e.response?.statusCode) {
      401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      403 => chiTiet ?? 'Bạn không có quyền ký số văn bản.',
      413 => 'Tệp quá lớn. Giới hạn 25 MB.',
      415 => 'Chỉ ký được tệp PDF. Hãy chuyển văn bản sang PDF trước.',
      503 => chiTiet ?? 'Hệ thống ký số chưa sẵn sàng. Liên hệ quản trị viên.',
      _ => e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout
          ? 'Máy chủ phản hồi chậm. Vui lòng thử lại.'
          : chiTiet ?? 'Không kết nối được máy chủ ký số.',
    };
  }
}
