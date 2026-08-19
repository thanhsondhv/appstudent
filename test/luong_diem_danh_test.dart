// Giữ cho hai đường điểm danh không lệch nhau.
//
// Ứng dụng có HAI cách điểm danh: quét mã QR (home_screen) và nhập mã PIN
// (diem_danh_sv_screen). Cả hai gọi cùng một endpoint và phải xử lý giống nhau.
//
// Ngày 18/08/2026 tôi sửa đường PIN, và ngày 19/08 phát hiện đường QR vẫn còn
// nguyên ba lỗi cũ. Đây là lần thứ ba trong dự án gặp kiểu "hai đường song
// song, sửa một quên một" — nên phải có máy kiểm.
//
// Ba điều bắt buộc, mỗi điều đều làm sinh viên mất điểm chuyên cần nếu sai:
//
//   1. Xem MÃ TRẢ VỀ trước khi đọc nội dung. Máy chủ trả 500 kèm trang lỗi
//      HTML, hoặc 401 khi hết phiên, thì `jsonDecode` ném ngoại lệ và sinh viên
//      chỉ thấy "Lỗi kết nối" — dù vấn đề nằm chỗ khác.
//   2. KHÔNG ép dùng sinh trắc học. Máy không có vân tay hay khuôn mặt thì
//      `biometricOnly: true` ném lỗi, và sinh viên không điểm danh được bằng
//      bất kỳ cách nào.
//   3. Lấy vị trí phải có HẠN CHỜ. Trong phòng học kín, GPS có thể tìm mãi
//      không ra; màn hình đứng im, sinh viên tưởng treo rồi bỏ đi.
//
// Chạy:  flutter test test/luong_diem_danh_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _duongDiemDanh = {
  'lib/views/home_screen.dart': 'quét mã QR',
  'lib/views/diem_danh_sv_screen.dart': 'nhập mã PIN',
};

/// Đọc mã nguồn, BỎ phần chú thích.
///
/// Cần bước này vì chính lời giải thích cho bản sửa lại nhắc tới đoạn mã sai
/// (`biometricOnly: true`), và phép thử đầu tiên đã báo nhầm vào đó. Máy kiểm
/// phải đọc MÃ, không đọc lời kể về mã.
String _doc(String duongDan) {
  final nguon = File(duongDan).readAsStringSync();
  return nguon
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .where((dong) => !dong.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  group('Hai đường điểm danh xử lý giống nhau', () {
    _duongDiemDanh.forEach((tep, ten) {
      group('Đường $ten', () {
        test('xem mã trả về trước khi đọc nội dung', () {
          final nguon = _doc(tep);
          expect(
            nguon.contains('response.thanhCong') || nguon.contains('res.thanhCong'),
            isTrue,
            reason: '$tep gửi điểm danh mà không xem mã trạng thái.\n'
                'Máy chủ trả 500 kèm trang lỗi HTML thì jsonDecode ném ngoại lệ, '
                'và sinh viên chỉ thấy "Lỗi kết nối" — không biết mình đã được '
                'ghi nhận hay chưa.',
          );
        });

        test('không ép dùng sinh trắc học', () {
          final nguon = _doc(tep);
          expect(
            RegExp(r'biometricOnly:\s*true').hasMatch(nguon),
            isFalse,
            reason: '$tep ép `biometricOnly: true`.\n'
                'Máy không có vân tay hay khuôn mặt sẽ ném lỗi, và sinh viên '
                'không điểm danh được bằng bất kỳ cách nào. Dùng '
                '`canCheckBiometrics` để lùi về khoá màn hình khi cần.',
          );
        });

        test('lấy vị trí có hạn chờ', () {
          final nguon = _doc(tep);
          if (!nguon.contains('getCurrentPosition')) return; // đường này không dùng GPS

          expect(
            nguon.contains('.timeout('),
            isTrue,
            reason: '$tep gọi getCurrentPosition mà không đặt hạn chờ.\n'
                'Trong phòng học kín, GPS có thể tìm mãi không ra và màn hình '
                'đứng im vô hạn.',
          );
        });
      });
    });

    test('cả hai đường gọi cùng một endpoint', () {
      for (final tep in _duongDiemDanh.keys) {
        expect(
          _doc(tep).contains('/api/attendance/submit'),
          isTrue,
          reason: '$tep phải gửi tới /api/attendance/submit như đường kia',
        );
      }
    });
  });
}
