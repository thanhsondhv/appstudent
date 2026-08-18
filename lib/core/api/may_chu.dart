import 'package:flutter/foundation.dart';

/// Địa chỉ máy chủ mà ứng dụng gọi tới.
///
/// Trước 18/08/2026 địa chỉ này viết cứng ở hơn 30 tệp. Nay khai báo một chỗ,
/// và cho phép trỏ sang máy chủ thử **chỉ khi đang gỡ lỗi**.
///
/// Cách dùng khi cần thử với backend chạy trên máy lập trình:
///
///     flutter run --dart-define=MAY_CHU=http://10.10.1.6:8000
///
/// Bản phát hành (`flutter build --release`) LUÔN dùng máy chủ thật, kể cả khi
/// ai đó lỡ truyền tham số trên — chốt chặn nằm ở `kReleaseMode` bên dưới, để
/// một lần chạy thử không thể biến thành bản phát hành trỏ nhầm chỗ.
class MayChu {
  MayChu._();

  /// Máy chủ chính thức của trường.
  static const _chinhThuc = 'https://mobi.vinhuni.edu.vn';

  static const _thuNghiem = String.fromEnvironment('MAY_CHU');

  /// Địa chỉ gốc dùng cho mọi lời gọi API.
  static String get diaChi {
    if (kReleaseMode) return _chinhThuc;
    return _thuNghiem.isEmpty ? _chinhThuc : _thuNghiem;
  }

  /// Đúng khi đang trỏ về máy chủ thử — dùng để hiện dấu hiệu trên giao diện,
  /// tránh nhầm dữ liệu thử với dữ liệu thật.
  static bool get dangThuNghiem => diaChi != _chinhThuc;
}
