// Kiểm thử phần logic thuần — không cần thiết bị, không cần mạng.
//
// Tệp này trước đây là mẫu mặc định của Flutter ("Counter increments smoke
// test") và luôn hỏng vì ứng dụng không hề có màn hình đếm số nào. Một phép
// thử luôn đỏ còn tệ hơn không có phép thử: người ta quen với màu đỏ rồi bỏ
// qua cả những lỗi thật.
//
// Thay bằng hai chỗ đã từng sinh lỗi thật.

import 'package:flutter_test/flutter_test.dart';

import 'package:vinhuni_app/core/auth/user_role.dart';
import 'package:vinhuni_app/core/utils/rut_gon_html.dart';

void main() {
  group('Diễn giải vai trò người dùng', () {
    // Máy chủ trả vai trò dưới nhiều dạng khác nhau tuỳ endpoint. Trước
    // 18/08/2026 ứng dụng có BA cách kiểm tra vai trò khác nhau, nên cùng một
    // người có thể được coi là cán bộ ở màn này và sinh viên ở màn khác.

    test('nhận ra cán bộ qua mọi cách viết đang tồn tại', () {
      for (final chuoi in ['CanBo', 'canbo', 'CB', 'cb', 'CAN_BO', 'can bo',
                           'GiangVien', 'gv', 'staff', 'Lecturer']) {
        expect(UserRole.parse(chuoi), UserRole.canBo, reason: 'với "$chuoi"');
      }
    });

    test('nhận ra quản trị và cố vấn', () {
      for (final chuoi in ['Admin', 'ad', 'QuanTri', 'super_admin']) {
        expect(UserRole.parse(chuoi), UserRole.admin, reason: 'với "$chuoi"');
      }
      for (final chuoi in ['CoVan', 'cv', 'co_van', 'advisor']) {
        expect(UserRole.parse(chuoi), UserRole.coVan, reason: 'với "$chuoi"');
      }
    });

    test('vai trò lạ thì về quyền THẤP NHẤT, không phải cao nhất', () {
      // Điểm mấu chốt về bảo mật: đoán sai theo hướng cho thêm quyền là mở cửa
      // dữ liệu của người khác. Sai theo hướng ít quyền chỉ gây bất tiện.
      for (final chuoi in [null, '', '   ', 'khong_biet', 'xyz', '???']) {
        expect(UserRole.parse(chuoi), UserRole.sinhVien, reason: 'với "$chuoi"');
      }
    });

    test('biến thể có hậu tố vẫn nhận ra đúng', () {
      expect(UserRole.parse('CanBo_Khoa_CNTT'), UserRole.canBo);
      expect(UserRole.parse('Admin-He-Thong'), UserRole.admin);
    });

    test('quyền cán bộ gồm cả cố vấn và quản trị', () {
      expect(UserRole.canBo.isStaff, isTrue);
      expect(UserRole.coVan.isStaff, isTrue);
      expect(UserRole.admin.isStaff, isTrue);
      expect(UserRole.sinhVien.isStaff, isFalse);
      expect(UserRole.sinhVien.isStudent, isTrue);
    });

    test('ghi xuống máy luôn ở dạng chuẩn, đọc lại ra đúng vai trò cũ', () {
      for (final vaiTro in UserRole.values) {
        expect(UserRole.parse(vaiTro.wireValue), vaiTro,
            reason: 'ghi rồi đọc lại ${vaiTro.name}');
      }
    });
  });

  group('Rút gọn HTML cho phần tóm tắt', () {
    // Nội dung thông báo do nhiều người soạn trên trình soạn thảo web, nên lẫn
    // đủ loại thẻ. Phần tóm tắt trong danh sách từng hiện nguyên thẻ HTML.

    test('bỏ thẻ, giữ lại chữ', () {
      expect(rutGonHtml('<p>Xin chào <b>sinh viên</b></p>'),
          'Xin chào sinh viên');
    });

    test('đổi thực thể HTML về ký tự thật', () {
      expect(rutGonHtml('Điểm &gt; 5 &amp; &lt; 8'), 'Điểm > 5 & < 8');
      expect(rutGonHtml('a&nbsp;b'), 'a b');
    });

    test('gộp khoảng trắng thừa do xuống dòng trong HTML', () {
      expect(rutGonHtml('<div>Dòng một</div>\n\n   <div>Dòng hai</div>'),
          'Dòng một Dòng hai');
    });

    test('chịu được thẻ bị CẮT DỞ giữa chừng', () {
      // Máy chủ cắt nội dung theo số ký tự nên thẻ cuối thường đứt đôi. Bản đầu
      // để lọt phần đuôi này ra màn hình.
      expect(rutGonHtml('Nội dung <div class="abc'), 'Nội dung');
      expect(rutGonHtml('Xong <img src="dai-ngoang'), 'Xong');
    });

    test('rỗng hoặc null thì trả chuỗi rỗng, không ném lỗi', () {
      expect(rutGonHtml(null), '');
      expect(rutGonHtml(''), '');
      expect(rutGonHtml('<p></p>'), '');
    });

    test('cắt theo giới hạn và thêm dấu ba chấm', () {
      final kq = rutGonHtml('<p>Một câu khá dài để kiểm tra việc cắt</p>',
          gioiHan: 10);
      expect(kq.length, lessThanOrEqualTo(13)); // 10 chữ + '...'
      expect(kq, startsWith('Một câu'));
    });

    test('không cắt khi nội dung ngắn hơn giới hạn', () {
      expect(rutGonHtml('<p>Ngắn</p>', gioiHan: 100), 'Ngắn');
    });
  });
}
