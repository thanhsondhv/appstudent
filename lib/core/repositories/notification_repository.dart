import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // 2. Trả nợ những lần đánh dấu đã đọc chưa báo được lên máy chủ.
    //    Phải chạy TRƯỚC khi tải danh sách mới, nếu không máy chủ sẽ trả về
    //    trạng thái cũ và ghi đè lên phần người dùng đã đọc tại máy.
    await _traNoDanhDau(maNguoiDung);

    // 3. Gọi máy chủ ở nền
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

    // Rồi mới CHỜ máy chủ xác nhận.
    //
    // ⚠️ SỬA 19/08/2026: bản trước không chờ. Giao diện gọi làm mới huy hiệu
    // ngay sau đó, máy chủ chưa kịp ghi, nên con số trả về vẫn là số cũ —
    // người dùng đọc một tin mà huy hiệu đứng yên.
    //
    // Chờ ở đây KHÔNG làm giao diện chậm: phần hiển thị đã đổi ở dòng trên.
    final res = await Api.post('/api/mark-read/$maTin',
        duLieu: {'student_id': maNguoiDung});
    if (!res.thanhCong) {
      debugPrint('⚠️ [ThôngBáo] Máy chủ chưa ghi nhận đã đọc tin $maTin: '
          '${res.thongDiepLoi}');
      await _xepHang(maNguoiDung, '$maTin');
    }
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
      await _xepHang(maNguoiDung, _CA_DANH_SACH);
      return false;
    }
    await _xoaHang(maNguoiDung);
    return true;
  }

  // -- Hàng đợi đồng bộ ------------------------------------------------------
  //
  // Đánh dấu đã đọc ghi vào máy trước rồi mới báo máy chủ. Khi máy chủ không
  // nhận được — mất mạng, máy chủ bận, hoặc bản trên máy chủ chưa có endpoint —
  // thì việc đó phải được nhớ lại và làm lại, nếu không trạng thái đọc chỉ tồn
  // tại trên một máy và sẽ biến mất khi cài lại ứng dụng.
  //
  // Thêm 18/08/2026: trước đó giao diện có báo "sẽ thử lại khi có mạng" nhưng
  // thực tế không có chỗ nào thử lại cả.

  /// Giá trị đánh dấu "toàn bộ danh sách", để phân biệt với mã của từng tin.
  static const _CA_DANH_SACH = 'TAT_CA';

  static String _khoaHang(String maNguoiDung) => 'tb_cho_dong_bo_$maNguoiDung';

  Future<void> _xepHang(String maNguoiDung, String muc) async {
    if (maNguoiDung.isEmpty) return;
    final bo = await SharedPreferences.getInstance();
    final khoa = _khoaHang(maNguoiDung);
    final dsCu = bo.getStringList(khoa) ?? const [];

    // Đã nợ cả danh sách thì không cần nhớ thêm từng tin lẻ nữa
    if (dsCu.contains(_CA_DANH_SACH)) return;
    if (muc == _CA_DANH_SACH) {
      await bo.setStringList(khoa, [_CA_DANH_SACH]);
      return;
    }
    if (dsCu.contains(muc)) return;

    // Chặn hàng đợi phình vô hạn khi máy chủ hỏng lâu ngày: quá 200 tin lẻ thì
    // gộp thành một lệnh đánh dấu tất cả, vừa nhẹ vừa cho kết quả tương đương.
    if (dsCu.length >= 200) {
      await bo.setStringList(khoa, [_CA_DANH_SACH]);
      return;
    }
    await bo.setStringList(khoa, [...dsCu, muc]);
  }

  Future<void> _xoaHang(String maNguoiDung) async {
    final bo = await SharedPreferences.getInstance();
    await bo.remove(_khoaHang(maNguoiDung));
  }

  /// Gửi lại những lần đánh dấu đã đọc còn nợ. Im lặng khi không có gì nợ.
  Future<void> _traNoDanhDau(String maNguoiDung) async {
    final bo = await SharedPreferences.getInstance();
    final khoa = _khoaHang(maNguoiDung);
    final dsNo = bo.getStringList(khoa) ?? const [];
    if (dsNo.isEmpty) return;

    if (dsNo.contains(_CA_DANH_SACH)) {
      final res = await Api.post('/api/mark-all-read/$maNguoiDung');
      if (res.thanhCong) {
        await bo.remove(khoa);
        debugPrint('✅ [ThôngBáo] Đã đồng bộ lại lệnh đánh dấu tất cả đã đọc');
      }
      return;
    }

    final conNo = <String>[];
    for (final maTin in dsNo) {
      final res = await Api.post('/api/mark-read/$maTin',
          duLieu: {'student_id': maNguoiDung});
      // 404 nghĩa là tin không còn tồn tại trên máy chủ — nợ này vô nghĩa,
      // giữ lại chỉ làm hàng đợi không bao giờ vơi.
      if (!res.thanhCong && res.statusCode != 404) conNo.add(maTin);
    }

    if (conNo.isEmpty) {
      await bo.remove(khoa);
      debugPrint('✅ [ThôngBáo] Đã đồng bộ lại ${dsNo.length} tin đã đọc');
    } else {
      await bo.setStringList(khoa, conNo);
      debugPrint('⚠️ [ThôngBáo] Còn ${conNo.length}/${dsNo.length} tin chưa đồng bộ được');
    }
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

  /// Số chưa đọc dùng cho huy hiệu ở thanh điều hướng.
  ///
  /// Hỏi máy chủ trước; chỉ dùng số tại máy khi không gọi được.
  ///
  /// ⚠️ ĐÂY LÀ LẦN SỬA THỨ HAI của cùng một chỗ, chép lại đủ để lần sau không
  /// đi vòng lại:
  ///
  ///   • Ban đầu huy hiệu hỏi thẳng máy chủ còn danh sách đọc từ SQLite. Khi
  ///     máy chủ chưa có endpoint đánh dấu tất cả đã đọc, hai bên lệch nhau:
  ///     huy hiệu báo 12 mà mở ra không còn tin nào chưa đọc.
  ///   • 18/08/2026 tôi đổi sang đếm tại máy cho khớp danh sách. Nhưng máy chỉ
  ///     giữ những tin ĐÃ TẢI VỀ — trang đầu 20 tin. Đo trên tài khoản thật:
  ///     máy đếm 13 trong khi số thật là 386. Huy hiệu khớp danh sách nhưng
  ///     nói sai sự thật.
  ///
  /// Nguyên nhân của lần lệch đầu tiên nay đã hết: máy chủ đã có endpoint đánh
  /// dấu tất cả đã đọc, `count-unread` đã đếm cả hai nguồn dữ liệu, và
  /// [danhDauDaDoc] chờ máy chủ xác nhận xong mới để giao diện làm mới. Vậy
  /// máy chủ trở lại là nguồn đúng — nó biết cả những tin chưa tải về.
  Future<int> soChuaDocChoHuyHieu() async {
    final maNguoiDung = await Session.userCode;
    if (maNguoiDung.isEmpty) return 0;

    final res = await Api.get('/api/count-unread/$maNguoiDung');
    if (res.thanhCong && res.data is Map) {
      final so = (res.data as Map)['unread_count'];
      if (so is int) return so;
      if (so is String) return int.tryParse(so) ?? 0;
    }

    // Mất mạng thì vẫn hiện một con số có ý nghĩa, còn hơn để trống
    debugPrint('⚠️ [ThôngBáo] Không hỏi được máy chủ, dùng số tại máy');
    return _db.getUnreadCount(maNguoiDung);
  }
}

/// Chạy một Future ở nền mà không chờ, đồng thời nói rõ ý định đó trong mã.
void unawaited(Future<void> tuongLai) {
  tuongLai.catchError((Object e) {
    debugPrint('⚠️ [ThôngBáo] Lỗi tác vụ nền: $e');
  });
}
