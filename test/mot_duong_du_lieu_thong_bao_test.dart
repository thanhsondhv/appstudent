// Giữ cho phần thông báo chỉ có MỘT đường dữ liệu.
//
// VÌ SAO CẦN BÀI NÀY
//
// Trong hai ngày liên tiếp, cùng một loại lỗi xuất hiện hai lần và mỗi lần đều
// mất công truy lâu:
//
//   • Chức năng xoá: NotificationRepository.an() báo máy chủ đúng, nhưng màn
//     hình lại tự ghi thẳng xuống SQLite. Tin xoá rồi vẫn quay lại ở lần tải
//     sau, người dùng xoá mãi không hết.
//   • Dọn tin đã biến mất: viết trong kho dữ liệu, nhưng màn hình gọi
//     NotificationService nên mã đó không bao giờ chạy.
//
// Gốc rễ giống nhau: HAI lớp cùng làm một việc, màn hình chỉ đi một đường, và
// cải tiến viết vào đường kia thành vô hình. Loại lỗi này không lộ ra khi đọc
// mã — chỉ lộ khi chạy thật và thấy hành vi không đổi.
//
// Bài này đọc mã nguồn và bắt lỗi đó ngay tại chỗ.
//
// Chạy:  flutter test test/mot_duong_du_lieu_thong_bao_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Các tệp giao diện — nơi KHÔNG được tự đụng vào tầng dữ liệu.
const _manHinh = [
  'lib/views/thongbao_screen.dart',
  'lib/views/thongbao_chitiet_screen.dart',
];

/// Việc chỉ được làm ở đúng một nơi, kèm nơi đó là ở đâu.
const _chiMotNoi = <String, String>{
  'getOfflineNotifs': 'NotificationRepository',
  'insertNotification': 'NotificationRepository',
  'softDeleteNotification': 'NotificationRepository',
  'donTinDaBienMat': 'NotificationRepository',
  'updateReadStatus': 'NotificationRepository',
  'markAllAsRead': 'NotificationRepository',
};

String _doc(String duongDan) => File(duongDan).readAsStringSync();

/// Bỏ phần chú thích để không bắt nhầm những dòng chỉ NHẮC TỚI tên hàm.
String _boChuThich(String nguon) => nguon
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .where((d) => !d.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('Phần thông báo chỉ có một đường dữ liệu', () {
    test('màn hình không tự gọi thẳng xuống cơ sở dữ liệu', () {
      for (final tep in _manHinh) {
        if (!File(tep).existsSync()) continue;
        final nguon = _boChuThich(_doc(tep));

        for (final entry in _chiMotNoi.entries) {
          expect(
            nguon.contains('DatabaseHelper.instance.${entry.key}'),
            isFalse,
            reason: '$tep gọi thẳng DatabaseHelper.${entry.key}.\n'
                'Việc này phải đi qua ${entry.value} — nếu không, mọi cải tiến '
                'viết trong kho dữ liệu (báo máy chủ, dọn tin đã biến mất, hàng '
                'đợi đồng bộ) sẽ không chạy cho màn hình này. Đã xảy ra hai lần.',
          );
        }
      }
    });

    test('chỉ có một chỗ gọi /api/get-notifs', () {
      final thuMuc = Directory('lib');
      final phamPhai = <String>[];

      for (final tep in thuMuc.listSync(recursive: true)) {
        if (tep is! File || !tep.path.endsWith('.dart')) continue;
        if (tep.path.endsWith('notification_repository.dart')) continue;

        final nguon = _boChuThich(tep.readAsStringSync());
        if (nguon.contains('/api/get-notifs')) phamPhai.add(tep.path);
      }

      expect(
        phamPhai,
        isEmpty,
        reason: 'Những tệp sau tự gọi /api/get-notifs thay vì đi qua '
            'NotificationRepository: ${phamPhai.join(", ")}.\n'
            'Mỗi lời gọi riêng là một đường dữ liệu riêng, và bản sửa cho đường '
            'này sẽ không áp cho đường kia.',
      );
    });

    test('chỉ có một cách đếm số tin chưa đọc', () {
      // Từng có BA cách: getUnreadCount, câu truy vấn riêng trong
      // refreshAppIconBadge (thiếu điều kiện đã xoá), và đếm trong danh sách đã
      // tải. Cách thứ hai làm tin đã xoá vẫn tính vào con số ngoài biểu tượng.
      final thuMuc = Directory('lib');
      final phamPhai = <String>[];

      for (final tep in thuMuc.listSync(recursive: true)) {
        if (tep is! File || !tep.path.endsWith('.dart')) continue;
        if (tep.path.endsWith('database_helper.dart')) continue;

        final nguon = _boChuThich(tep.readAsStringSync());
        if (RegExp(r'FROM\s+notifications', caseSensitive: false).hasMatch(nguon)) {
          phamPhai.add(tep.path);
        }
      }

      expect(
        phamPhai,
        isEmpty,
        reason: 'Những tệp sau tự viết câu truy vấn lên bảng notifications: '
            '${phamPhai.join(", ")}.\n'
            'Mọi truy vấn phải nằm trong DatabaseHelper — câu viết riêng rất dễ '
            'quên điều kiện, ví dụ `is_deleted_local = 0`.',
      );
    });

    test('NotificationService không tự cài đặt lại việc tải danh sách', () {
      const tep = 'lib/services/notification_service.dart';
      final nguon = _boChuThich(_doc(tep));

      expect(
        nguon.contains('NotificationRepository.instance.dongBoVoiMayChu'),
        isTrue,
        reason: '$tep phải chuyển tiếp sang NotificationRepository, '
            'không tự tải danh sách lần nữa.',
      );
    });
  });
}
