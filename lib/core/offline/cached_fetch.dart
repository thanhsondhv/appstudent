import 'package:flutter/foundation.dart';

import '../api/api.dart';

/// Nguồn của dữ liệu vừa được trả về.
enum NguonDuLieu {
  /// Lấy từ SQLite trên máy — có ngay, có thể đã cũ.
  tuMay,

  /// Vừa tải mới từ máy chủ.
  tuMayChu,

  /// Gọi máy chủ thất bại, dữ liệu đang hiển thị là bản cũ trên máy.
  tuMayDoLoiMang,
}

/// Kết quả một lần lấy dữ liệu.
class KetQuaTai<T> {
  const KetQuaTai(this.duLieu, this.nguon, {this.thongDiepLoi = ''});

  final T duLieu;
  final NguonDuLieu nguon;

  /// Chỉ có giá trị khi [nguon] là [NguonDuLieu.tuMayDoLoiMang].
  final String thongDiepLoi;

  bool get laDuLieuMoi => nguon == NguonDuLieu.tuMayChu;
  bool get dangDungBanCu => nguon == NguonDuLieu.tuMayDoLoiMang;
}

/// Lấy dữ liệu theo lối "hiện bản cũ ngay, cập nhật bản mới sau".
///
/// Bốn màn lịch (thời khoá biểu sinh viên, lịch thi, lịch giảng dạy, lịch công
/// tác cán bộ) trước ngày 18/08/2026 mỗi màn tự viết lại đúng đoạn logic này
/// theo một cách khác nhau — khác cả ở chỗ xử lý lỗi và thời điểm gọi
/// `setState`. Hàm này gom về một chỗ.
///
/// [khiCoDuLieu] được gọi **hai lần** trong trường hợp thông thường:
///   1. ngay lập tức với dữ liệu đã lưu trên máy, để màn hình có nội dung liền
///   2. sau đó với dữ liệu mới từ máy chủ
///
/// Nếu máy chủ lỗi hoặc mất mạng, lần gọi thứ hai vẫn xảy ra nhưng mang
/// [NguonDuLieu.tuMayDoLoiMang] — giao diện nên báo cho người dùng biết đang
/// xem dữ liệu cũ, thay vì im lặng hiển thị số liệu có thể đã lỗi thời.
///
/// ```dart
/// await cachedFetch<List<dynamic>>(
///   duongDan: '/api/get-filters/$maSinhVien',
///   docTuMay: () => db.getScheduleFilters(maSinhVien),
///   ghiVaoMay: (duLieu) => db.saveScheduleFilters(maSinhVien, duLieu),
///   khiCoDuLieu: (kq) {
///     if (!mounted) return;
///     setState(() {
///       danhSach = kq.duLieu;
///       dangXemBanCu = kq.dangDungBanCu;
///     });
///   },
/// );
/// ```
Future<void> cachedFetch<T>({
  required String duongDan,
  required Future<T?> Function() docTuMay,
  required Future<void> Function(T duLieu) ghiVaoMay,
  required void Function(KetQuaTai<T> ketQua) khiCoDuLieu,
  Map<String, dynamic>? thamSo,
  Duration hanCho = const Duration(seconds: 15),

  /// Chuyển dữ liệu thô từ máy chủ sang kiểu [T]. Bỏ trống thì ép kiểu thẳng.
  T Function(dynamic thoServer)? chuyenDoi,

  /// Chỉ đọc dữ liệu trên máy, không gọi mạng. Dùng khi người dùng đang ở chế
  /// độ tiết kiệm dữ liệu, hoặc khi vừa gọi mạng xong ở bước trước.
  bool chiDocTuMay = false,
}) async {
  // --- 1. Trả bản trên máy trước ---
  T? banCu;
  try {
    banCu = await docTuMay();
  } catch (e) {
    debugPrint('⚠️ [Đệm] Không đọc được dữ liệu đã lưu cho $duongDan: $e');
  }

  final bool coBanCu = banCu != null && !_rong(banCu);
  if (coBanCu) {
    khiCoDuLieu(KetQuaTai<T>(banCu, NguonDuLieu.tuMay));
  }

  if (chiDocTuMay) return;

  // --- 2. Gọi máy chủ ---
  final res = await Api.get(duongDan, thamSo: thamSo, hanCho: hanCho);

  if (!res.thanhCong) {
    debugPrint('⚠️ [Đệm] $duongDan lỗi: ${res.thongDiepLoi}');
    if (coBanCu) {
      // Báo lại cùng dữ liệu cũ, nhưng nói rõ là đang dùng bản cũ
      khiCoDuLieu(KetQuaTai<T>(
        banCu,
        NguonDuLieu.tuMayDoLoiMang,
        thongDiepLoi: res.thongDiepLoi,
      ));
    } else if (banCu != null) {
      // Không có gì để hiện, nhưng vẫn phải báo để màn hình tắt vòng xoay chờ
      khiCoDuLieu(KetQuaTai<T>(
        banCu,
        NguonDuLieu.tuMayDoLoiMang,
        thongDiepLoi: res.thongDiepLoi,
      ));
    }
    return;
  }

  // --- 3. Chuyển đổi và ghi vào máy ---
  final T? duLieuMoi;
  try {
    duLieuMoi = chuyenDoi != null ? chuyenDoi(res.data) : res.data as T?;
  } catch (e) {
    debugPrint('❌ [Đệm] $duongDan trả về kiểu dữ liệu không dùng được: $e');
    return;
  }
  if (duLieuMoi == null) return;

  try {
    await ghiVaoMay(duLieuMoi);
  } catch (e) {
    // Ghi đệm hỏng không được làm hỏng việc hiển thị — vẫn trả dữ liệu mới
    debugPrint('⚠️ [Đệm] Không ghi được vào máy cho $duongDan: $e');
  }

  khiCoDuLieu(KetQuaTai<T>(duLieuMoi, NguonDuLieu.tuMayChu));
}

bool _rong(Object? giaTri) {
  if (giaTri == null) return true;
  if (giaTri is Iterable) return giaTri.isEmpty;
  if (giaTri is Map) return giaTri.isEmpty;
  if (giaTri is String) return giaTri.isEmpty;
  return false;
}
