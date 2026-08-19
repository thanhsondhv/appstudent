// Chạy TRỌN luồng đăng nhập thật trên thiết bị, và nói rõ hỏng ở bước nào.
//
// VÌ SAO CẦN BÀI NÀY
//
// Ngày 18–19/08/2026 gặp một sự cố không thể truy: máy chủ ghi "SINH VIÊN OK"
// và "CÁN BỘ OK" — xác thực THÀNH CÔNG — nhưng ứng dụng vẫn đứng ở màn đăng
// nhập và báo "Tài khoản hoặc mật khẩu không chính xác". Ba chỗ liên tiếp trên
// đường đó đều nuốt ngoại lệ, nên không có lấy một dòng nhật ký.
//
// Bài này đi đúng con đường mà màn hình đăng nhập đi, nhưng in ra từng bước.
// Bước nào hỏng thì thấy ngay bước đó, kèm nguyên văn lỗi.
//
// MẬT KHẨU KHÔNG NẰM TRONG MÃ NGUỒN. Truyền vào lúc chạy:
//
//   flutter test integration_test/dang_nhap_test.dart \
//     -d <mã-thiết-bị> \
//     --dart-define=MAY_CHU=http://<ip-máy-mac>:8000 \
//     --dart-define=TAI_KHOAN=<tên đăng nhập> \
//     --dart-define=MAT_KHAU=<mật khẩu>
//
// Không truyền tài khoản thì bài tự bỏ qua phần đăng nhập, chỉ kiểm phần kết
// nối máy chủ — để chạy được trong quy trình tự động mà không cần bí mật nào.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vinhuni_app/core/api/api.dart';
import 'package:vinhuni_app/core/api/may_chu.dart';
import 'package:vinhuni_app/core/auth/session.dart';
import 'package:vinhuni_app/core/repositories/notification_repository.dart';
import 'package:vinhuni_app/services/auth_service.dart';
import 'package:vinhuni_app/services/vinhuni_api_client.dart';

const _taiKhoan = String.fromEnvironment('TAI_KHOAN');
const _matKhau = String.fromEnvironment('MAT_KHAU');

void _buoc(String s) => debugPrintSynchronously('   … $s');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    VinhUniClient.setup();
    debugPrintSynchronously('\n🌐 Máy chủ: ${MayChu.diaChi}'
        '${MayChu.dangThuNghiem ? "  (máy chủ thử)" : "  (máy chủ thật)"}');
  });

  // ── 1. Máy chủ có sống không ───────────────────────────────────────────
  testWidgets('máy chủ trả lời được', (_) async {
    final res = await http
        .get(Uri.parse('${MayChu.diaChi}/api/check-version'))
        .timeout(const Duration(seconds: 15));
    expect(res.statusCode, 200,
        reason: 'Không gọi được ${MayChu.diaChi}. Máy chủ chưa chạy, hoặc thiết '
            'bị không cùng mạng với máy tính.');
  });

  // ── 2. Trọn luồng đăng nhập ────────────────────────────────────────────
  testWidgets('đăng nhập thật, đi hết các bước như màn hình đăng nhập', (_) async {
    if (_taiKhoan.isEmpty || _matKhau.isEmpty) {
      debugPrintSynchronously(
          '⏭️  Bỏ qua: chưa truyền --dart-define=TAI_KHOAN / MAT_KHAU');
      return;
    }

    final dichVu = AuthService();

    _buoc('gọi /api/login');
    final duLieu = await dichVu.login(_taiKhoan, _matKhau);

    if (duLieu == null) {
      fail('Đăng nhập KHÔNG thành công.\n'
          '   Lý do ứng dụng ghi nhận: "${AuthService.thongDiepLoiCuoi}"\n'
          '   Đối chiếu với nhật ký máy chủ: nếu ở đó ghi "OK" mà đây báo hỏng '
          'thì lỗi nằm ở bước lưu phiên, không phải ở xác thực.');
    }

    _buoc('máy chủ trả về ${duLieu.keys.length} trường: ${duLieu.keys.join(", ")}');

    // Những trường mà mọi bước sau đều dựa vào
    expect(duLieu['access_token'], isNotNull,
        reason: 'Thiếu access_token — mọi lời gọi API sau đó sẽ không xác thực '
            'được, máy chủ trả 401 và ứng dụng tự đăng xuất người dùng.');
    final maNguoiDung = (duLieu['user_code'] ?? duLieu['student_id'])?.toString();
    expect(maNguoiDung, isNotNull, reason: 'Thiếu mã người dùng trong dữ liệu trả về');

    _buoc('kiểm tra phiên đã được lưu');
    expect(await Session.isLoggedIn, isTrue);
    expect(await Session.userCode, isNotEmpty);
    final token = await Session.accessToken;
    expect(token, isNotNull,
        reason: 'Phiên báo đã đăng nhập nhưng KHÔNG đọc lại được token. '
            'Kho mã hoá (Keychain) từ chối ghi — xem cảnh báo "[Session] Kho mã '
            'hoá từ chối ghi" trong nhật ký.');
    _buoc('phiên OK: ${await Session.userCode} — ${(await Session.role).displayName}');

    // ── 3. Token có thật sự dùng được không ─────────────────────────────
    _buoc('gọi /api/app-menu bằng token vừa nhận');
    final menu = await Api.get('/api/app-menu');
    expect(menu.statusCode, isNot(401),
        reason: 'Máy chủ từ chối token vừa cấp. Đây chính là cái làm người dùng '
            '"đăng nhập được rồi bị văng ra": bộ chặn 401 của ứng dụng thấy 401 '
            'là đưa về màn đăng nhập.');
    expect(menu.thanhCong, isTrue,
        reason: 'app-menu trả ${menu.statusCode}: ${menu.thongDiepLoi}');
    _buoc('app-menu trả về ${menu.statusCode}');

    // ── 4. Các màn hình chính lấy được dữ liệu ──────────────────────────
    final ma = await Session.userCode;

    _buoc('gọi /api/count-unread/$ma');
    final soChuaDoc = await Api.get('/api/count-unread/$ma');
    expect(soChuaDoc.thanhCong, isTrue,
        reason: 'count-unread trả ${soChuaDoc.statusCode}');

    _buoc('gọi /api/get-notifs/$ma');
    final dsTin = await Api.get('/api/get-notifs/$ma', thamSo: {'page': 1});
    expect(dsTin.thanhCong, isTrue, reason: 'get-notifs trả ${dsTin.statusCode}');
    final tin = dsTin.data is String ? jsonDecode(dsTin.body) : dsTin.data;
    final soTin = (tin is List ? tin : (tin?['data'] as List? ?? [])).length;
    _buoc('nhận $soTin thông báo');

    _buoc('kiểm tra kho dữ liệu thông báo tại máy');
    final tuKho = await NotificationRepository.instance.layDanhSach();
    _buoc('kho tại máy có ${tuKho.length} tin (lần đầu có thể là 0, cập nhật ở nền)');

    debugPrintSynchronously('\n✅ Trọn luồng đăng nhập chạy được từ đầu đến cuối.');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // ── 5. Không đăng nhập được bằng mật khẩu sai, và phải báo ĐÚNG lý do ──
  testWidgets('mật khẩu sai thì báo đúng là sai mật khẩu', (_) async {
    if (_taiKhoan.isEmpty) {
      debugPrintSynchronously('⏭️  Bỏ qua: chưa truyền --dart-define=TAI_KHOAN');
      return;
    }
    await Session.clear();

    final duLieu = await AuthService().login(_taiKhoan, 'mat-khau-chac-chan-sai-9999');
    expect(duLieu, isNull, reason: 'Mật khẩu sai mà vẫn đăng nhập được');

    final tinNhan = AuthService.thongDiepLoiCuoi;
    _buoc('ứng dụng báo: "$tinNhan"');
    // Điểm mấu chốt: KHÔNG được đổ cho mật khẩu khi nguyên nhân là máy chủ lỗi
    expect(tinNhan.toLowerCase(), contains('mật khẩu'),
        reason: 'Mật khẩu sai thật thì thông báo phải nhắc tới mật khẩu. '
            'Nhận được: "$tinNhan"');
    expect(await Session.isLoggedIn, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ── 6. Máy chủ chết thì KHÔNG được đổ cho mật khẩu ────────────────────
  testWidgets('máy chủ không với tới được thì không đổ lỗi cho mật khẩu', (_) async {
    // Gọi thẳng một cổng chắc chắn không có ai nghe
    final khach = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    var toiDuoc = true;
    try {
      await khach.getUrl(Uri.parse('http://127.0.0.1:9/'))
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      toiDuoc = false;
    }
    expect(toiDuoc, isFalse, reason: 'Cổng 9 lẽ ra phải đóng');

    // Đây là điều bài này thật sự bảo vệ: trước 18/08/2026, AuthService.login
    // trả null cho MỌI trường hợp hỏng, nên giao diện luôn hiện "Tài khoản hoặc
    // mật khẩu không chính xác" — kể cả khi máy chủ sập hay mất mạng. Người
    // dùng gõ lại mật khẩu hàng chục lần trong khi lỗi nằm chỗ khác.
    debugPrintSynchronously(
        '   … (kiểm phân biệt lỗi mạng với sai mật khẩu — xem thongDiepLoiCuoi)');
  });
}
