/// So sánh số phiên bản ứng dụng.
///
/// Dạng chuỗi: `1.3.5+21` — phần trước dấu cộng là số phiên bản, phần sau là
/// số lần dựng.
///
/// ⚠️ TÁCH RA THÀNH TỆP RIÊNG 19/08/2026 để kiểm thử được.
///
/// Trước đó hàm này nằm trong `home_screen.dart` và viết:
///
///     if (curParts[0] != latParts[0]) return true;
///
/// Nó so KHÁC NHAU rồi kết luận "có bản mới", kể cả khi bản đang cài MỚI HƠN.
/// Đo thực tế: ứng dụng 1.3.5+21, máy chủ khai 1.3.3+20 — đã mới hơn hai bậc
/// mà vẫn hiện hộp "Đã có phiên bản mới" mỗi lần mở, không bao giờ tắt.
///
/// Với người dùng, một lời nhắc sai lặp mãi sẽ khiến họ bỏ qua cả những lời
/// nhắc thật — kể cả bản cập nhật bắt buộc vì lý do bảo mật.
library;

import 'package:flutter/foundation.dart';

/// `"1.3.5+21"` → `([1, 3, 5], 21)`
({List<int> so, int lanDung}) tachPhienBan(String chuoi) {
  final phan = chuoi.trim().split('+');
  final so = phan[0]
      .split('.')
      .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final lanDung = phan.length > 1 ? (int.tryParse(phan[1].trim()) ?? 0) : 0;
  return (so: so, lanDung: lanDung);
}

/// Đúng khi [banMoi] thực sự mới hơn [dangCai].
///
/// Trả `false` khi bằng nhau, khi bản đang cài mới hơn, hoặc khi chuỗi không
/// đọc được — nhắc nhầm phiền hơn là bỏ sót một lần.
bool coBanMoiHon(String dangCai, String banMoi) {
  try {
    final cu = tachPhienBan(dangCai);
    final moi = tachPhienBan(banMoi);

    final n = cu.so.length > moi.so.length ? cu.so.length : moi.so.length;
    for (var i = 0; i < n; i++) {
      final a = i < cu.so.length ? cu.so[i] : 0;
      final b = i < moi.so.length ? moi.so[i] : 0;
      if (b != a) return b > a;
    }
    return moi.lanDung > cu.lanDung;
  } catch (e) {
    debugPrint("⚠️ Không đọc được số phiên bản: $e");
    return false;
  }
}
