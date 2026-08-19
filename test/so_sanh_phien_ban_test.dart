// So sánh số phiên bản — hàm quyết định 15 nghìn người có bị nhắc sai không.
//
// Bản cũ viết:
//
//     if (curParts[0] != latParts[0]) return true;
//
// So KHÁC NHAU rồi kết luận "có bản mới", kể cả khi bản đang cài MỚI HƠN. Đo
// thực tế ngày 19/08/2026: ứng dụng 1.3.5+21, máy chủ khai 1.3.3+20 — đã mới
// hơn hai bậc mà vẫn hiện hộp "Đã có phiên bản mới" mỗi lần mở, không bao giờ
// tắt được.
//
// Với người dùng, một lời nhắc sai lặp mãi sẽ khiến họ bỏ qua cả những lời
// nhắc thật — kể cả bản cập nhật bắt buộc vì lý do bảo mật. Đó là lý do bài
// này tồn tại.

import 'package:flutter_test/flutter_test.dart';

import 'package:vinhuni_app/core/utils/so_sanh_phien_ban.dart';

void main() {
  group('Có bản mới hơn không', () {
    test('bằng nhau thì KHÔNG nhắc', () {
      expect(coBanMoiHon('1.3.5+21', '1.3.5+21'), isFalse);
      expect(coBanMoiHon('2.0.0+1', '2.0.0+1'), isFalse);
    });

    test('bản đang cài MỚI HƠN thì KHÔNG nhắc', () {
      // Chính trường hợp đã gặp thật
      expect(coBanMoiHon('1.3.5+21', '1.3.3+20'), isFalse,
          reason: 'App 1.3.5+21 mới hơn 1.3.3+20 mà vẫn báo cập nhật');
      expect(coBanMoiHon('2.0.0+1', '1.9.9+99'), isFalse);
      expect(coBanMoiHon('1.10.0+5', '1.9.0+5'), isFalse);
    });

    test('máy chủ có bản mới hơn thì CÓ nhắc', () {
      expect(coBanMoiHon('1.3.3+20', '1.3.5+21'), isTrue);
      expect(coBanMoiHon('1.9.9+99', '2.0.0+1'), isTrue);
      expect(coBanMoiHon('1.3.5+21', '1.4.0+21'), isTrue);
    });

    test('số phiên bản bằng nhau thì xét số lần dựng', () {
      expect(coBanMoiHon('1.3.5+21', '1.3.5+22'), isTrue);
      expect(coBanMoiHon('1.3.5+22', '1.3.5+21'), isFalse);
    });

    test('so theo GIÁ TRỊ SỐ, không so theo chữ', () {
      // '10' < '9' nếu so chuỗi, nhưng 10 > 9 khi so số. Đây là chỗ rất dễ sai.
      expect(coBanMoiHon('1.9.0+1', '1.10.0+1'), isTrue,
          reason: '1.10.0 mới hơn 1.9.0');
      expect(coBanMoiHon('1.10.0+1', '1.9.0+1'), isFalse);
      expect(coBanMoiHon('1.3.5+9', '1.3.5+10'), isTrue);
    });

    test('thiếu số lần dựng vẫn so được', () {
      expect(coBanMoiHon('1.3.5', '1.3.6'), isTrue);
      expect(coBanMoiHon('1.3.6', '1.3.5'), isFalse);
      expect(coBanMoiHon('1.3.5', '1.3.5'), isFalse);
    });

    test('số phần khác nhau thì phần thiếu coi như 0', () {
      expect(coBanMoiHon('1.3', '1.3.0'), isFalse);
      expect(coBanMoiHon('1.3', '1.3.1'), isTrue);
      expect(coBanMoiHon('1.3.1', '1.3'), isFalse);
    });

    test('chuỗi lạ thì KHÔNG nhắc — nhắc nhầm phiền hơn bỏ sót', () {
      expect(coBanMoiHon('1.3.5+21', ''), isFalse);
      expect(coBanMoiHon('1.3.5+21', 'khong-phai-so'), isFalse);
      expect(coBanMoiHon('', ''), isFalse);
    });

    test('chịu được khoảng trắng thừa và tiền tố chữ', () {
      expect(coBanMoiHon(' 1.3.5+21 ', ' 1.3.5+21 '), isFalse);
      expect(coBanMoiHon('v1.3.5+21', 'v1.3.6+21'), isTrue);
    });
  });

  group('Tách chuỗi phiên bản', () {
    test('tách đúng phần số và phần lần dựng', () {
      final r = tachPhienBan('1.3.5+21');
      expect(r.so, [1, 3, 5]);
      expect(r.lanDung, 21);
    });

    test('không có dấu cộng thì lần dựng là 0', () {
      expect(tachPhienBan('2.0.1').lanDung, 0);
    });
  });
}
