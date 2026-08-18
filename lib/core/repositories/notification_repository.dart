import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/database_helper.dart';
import '../api/api.dart';
import '../auth/session.dart';

/// Kho dữ liệu thông báo — nơi duy nhất gom việc gọi máy chủ và ghi SQLite.
///
/// Trước ngày 18/08/2026, logic thông báo nằm rải ở ba nơi với ba cách làm khác
/// nhau: `NotificationService` (gọi `package:http`, địa chỉ viết cứng),
/// `ThongBaoScreen` (gọi trực tiếp trong hàm dựng giao diện), và
/// `DatabaseHelper` (chỉ phần SQLite). Hệ quả là hai chức năng bị hỏng lặng lẽ:
///
///   • Nút "Đánh dấu tất cả đã đọc" chỉ đóng hộp thoại rồi thôi
///   • Lệnh báo đã đọc lên máy chủ bị chú thích, nên trạng thái đọc chỉ nằm
///     trên máy — đổi điện thoại hoặc cài lại là mất sạch
///
/// Lớp này thay cho cả ba, theo nguyên tắc **ghi tại chỗ trước, đồng bộ sau**:
/// giao diện đổi ngay để người dùng thấy phản hồi tức thì, việc báo lên máy chủ
/// chạy nền. Nếu máy chủ lỗi thì trạng thái tại máy vẫn giữ, lần mở sau đồng bộ lại.
class NotificationRepository {
  NotificationRepository._();

  static final instance = NotificationRepository._();

  final _db = DatabaseHelper.instance;

  // -- Đọc danh sách ---------------------------------------------------------

  /// Lấy danh sách thông báo: hiện dữ liệu đã lưu ngay, rồi cập nhật từ máy chủ.
  ///
  /// [khiCoDuLieuMoi] được gọi lần thứ hai nếu máy chủ trả về dữ liệu khác với
  /// bản đã lưu — giao diện chỉ cần dựng lại khi thực sự có thay đổi.
  Future<List<dynamic>> layDanhSach({
    void Function(List<dynamic> duLieuMoi)? khiCoDuLieuMoi,
  }) async {
    final maNguoiDung = await Session.userCode;
    if (maNguoiDung.isEmpty) return [];

    // 1. Trả dữ liệu đã lưu trước — mở màn hình là thấy nội dung ngay
    final duLieuCu = await _db.getOfflineNotifs(maNguoiDung);

    // 2. Gọi máy chủ ở nền
    unawaited(
      _capNhatTuMayChu(maNguoiDung).then((duLieuMoi) {
        if (duLieuMoi != null && khiCoDuLieuMoi != null) {
          khiCoDuLieuMoi(duLieuMoi);
        }
      }),
    );

    return duLieuCu;
  }

  Future<List<dynamic>?> _capNhatTuMayChu(String maNguoiDung) async {
    final res = await Api.get('/api/get-notifs/$maNguoiDung');
    if (!res.thanhCong) {
      debugPrint('⚠️ [ThôngBáo] Không tải được từ máy chủ: ${res.thongDiepLoi}');
      return null;
    }

    try {
      final duLieu = res.data is String ? jsonDecode(res.body) : res.data;
      final danhSach = (duLieu is Map ? duLieu['data'] : duLieu) as List? ?? [];

      for (final tin in danhSach) {
        await _db.insertNotification(Map<String, dynamic>.from(tin as Map), maNguoiDung);
      }
      return await _db.getOfflineNotifs(maNguoiDung);
    } catch (e) {
      debugPrint('❌ [ThôngBáo] Dữ liệu máy chủ sai định dạng: $e');
      return null;
    }
  }

  // -- Đánh dấu đã đọc -------------------------------------------------------

  /// Đánh dấu một thông báo đã đọc.
  ///
  /// Ghi vào SQLite trước để giao diện đổi ngay, rồi báo máy chủ ở nền. Trước
  /// đây phần báo máy chủ bị chú thích nên trạng thái đọc không bao giờ rời
  /// khỏi máy người dùng.
  Future<void> danhDauDaDoc(int maTin) async {
    await _db.updateReadStatus(maTin);

    final maNguoiDung = await Session.userCode;
    unawaited(
      Api.post('/api/mark-read/$maTin', duLieu: {'student_id': maNguoiDung})
          .then((res) {
        if (!res.thanhCong) {
          debugPrint('⚠️ [ThôngBáo] Máy chủ chưa ghi nhận đã đọc tin $maTin: '
              '${res.thongDiepLoi}');
        }
      }),
    );
  }

  /// Đánh dấu toàn bộ thông báo đã đọc.
  ///
  /// Khác với [danhDauDaDoc], hàm này CHỜ máy chủ trả lời rồi mới báo kết quả:
  /// đây là thao tác người dùng chủ động bấm và mong thấy xác nhận, không phải
  /// việc ngầm.
  ///
  /// Trả về `true` khi máy chủ đã ghi nhận. Trả về `false` khi chỉ đổi được ở
  /// máy — giao diện nên nói rõ điều đó thay vì báo thành công.
  Future<bool> danhDauTatCaDaDoc() async {
    final maNguoiDung = await Session.userCode;
    if (maNguoiDung.isEmpty) return false;

    // Đổi tại máy trước để danh sách cập nhật ngay
    await _db.markAllAsRead(maNguoiDung);

    final res = await Api.post('/api/mark-all-read/$maNguoiDung');
    if (!res.thanhCong) {
      debugPrint('⚠️ [ThôngBáo] Máy chủ chưa ghi nhận đánh dấu tất cả: '
          '${res.thongDiepLoi}');
      return false;
    }
    return true;
  }

  // -- Ẩn thông báo ----------------------------------------------------------

  Future<bool> an(int maTin) async {
    await _db.softDeleteNotification(maTin);
    final maNguoiDung = await Session.userCode;
    final res = await Api.post(
      '/api/hide-notif/$maTin',
      duLieu: {'student_id': maNguoiDung},
    );
    return res.thanhCong;
  }

  // -- Số chưa đọc -----------------------------------------------------------

  /// Số thông báo chưa đọc, lấy từ dữ liệu tại máy.
  ///
  /// Cố ý không hỏi máy chủ: con số này hiển thị trên huy hiệu ứng dụng và cần
  /// có ngay cả khi mất mạng. Máy chủ là nguồn đúng khi đồng bộ, còn để hiển
  /// thị thì dữ liệu tại máy đủ và nhanh hơn.
  Future<int> soChuaDoc() async => _db.getUnreadCount(await Session.userCode);
}

/// Chạy một Future ở nền mà không chờ, đồng thời nói rõ ý định đó trong mã.
void unawaited(Future<void> tuongLai) {
  tuongLai.catchError((Object e) {
    debugPrint('⚠️ [ThôngBáo] Lỗi tác vụ nền: $e');
  });
}
