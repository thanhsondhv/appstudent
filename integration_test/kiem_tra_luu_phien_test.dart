// Kiểm tra việc lưu phiên đăng nhập TRÊN THIẾT BỊ THẬT (máy ảo hoặc điện thoại).
//
// Vì sao cần chạy trên thiết bị: Session ghi token vào Keychain (iOS) hoặc
// EncryptedSharedPreferences (Android). Hai kho này không tồn tại trong môi
// trường `flutter test` thông thường, nên lỗi ở đây chỉ lộ ra khi chạy thật.
//
// Bài này sinh ra từ một sự cố ngày 18/08/2026: máy chủ ghi "ĐĂNG NHẬP OK"
// nhưng ứng dụng vẫn đứng ở màn đăng nhập và báo "sai mật khẩu". Nguyên nhân
// nằm ở bước lưu phiên, không phải ở xác thực — mà không có cách nào biết được
// vì lỗi bị nuốt trong khối catch chung.
//
// Chạy:
//   flutter test integration_test/kiem_tra_luu_phien_test.dart -d <mã-thiết-bị>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:vinhuni_app/core/auth/session.dart';
import 'package:vinhuni_app/core/auth/user_role.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const kho = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('kho mã hoá ghi và đọc lại được', (_) async {
    // Nếu phép thử này hỏng thì Keychain/EncryptedSharedPreferences không dùng
    // được trên thiết bị — mọi thứ bên dưới sẽ hỏng theo.
    await kho.write(key: 'thu_nghiem', value: 'gia-tri-thu');
    expect(await kho.read(key: 'thu_nghiem'), 'gia-tri-thu');
    await kho.delete(key: 'thu_nghiem');
  });

  testWidgets('Session.save lưu đủ thông tin phiên của SINH VIÊN', (_) async {
    await Session.save({
      'student_id': '205714023110061',
      'user_code': '205714023110061',
      'full_name': 'NGUYỄN VĂN A',
      'user_role': 'SinhVien',
      'role': 'SinhVien',
      'faculty': 'Khoa Công nghệ thông tin',
      'department': 'Trường Đại học Vinh',
      'access_token': 'token-thu-nghiem-sinh-vien',
      'firebase_chat_token': 'token-chat-thu-nghiem',
    });

    expect(await Session.userCode, '205714023110061');
    expect(await Session.fullName, 'NGUYỄN VĂN A');
    expect(await Session.isLoggedIn, isTrue);
    expect(await Session.role, UserRole.sinhVien);

    // Đây là điểm mấu chốt: thiếu token thì mọi lời gọi API sau đó đi ra không
    // xác thực, máy chủ trả 401, và ứng dụng tự đăng xuất người dùng.
    expect(await Session.accessToken, 'token-thu-nghiem-sinh-vien',
        reason: 'Không đọc lại được token vừa lưu — người dùng sẽ bị đăng xuất ngay');
  });

  testWidgets('Session.save lưu đủ thông tin phiên của CÁN BỘ', (_) async {
    await Session.save({
      'user_code': '1679',
      'full_name': 'NGUYỄN THANH SƠN',
      'user_role': 'Admin',
      'access_token': 'token-thu-nghiem-can-bo',
    });

    expect(await Session.userCode, '1679');
    expect(await Session.role, UserRole.admin);
    expect(await Session.accessToken, 'token-thu-nghiem-can-bo');
  });

  testWidgets('Session.save không ném lỗi khi thiếu trường không bắt buộc', (_) async {
    // Máy chủ trả về bộ trường khác nhau tuỳ đường đăng nhập (mật khẩu, khuôn
    // mặt, Office 365). Thiếu một trường phụ KHÔNG được phép làm hỏng cả phiên.
    await Session.save({'user_code': '1679', 'access_token': 'chi-co-token'});
    expect(await Session.isLoggedIn, isTrue);
    expect(await Session.accessToken, 'chi-co-token');
  });

  testWidgets('Session.clear xoá sạch, không sót token', (_) async {
    await Session.save({
      'user_code': '1679',
      'access_token': 'token-can-xoa',
      'firebase_chat_token': 'chat-can-xoa',
    });
    await Session.clear();

    expect(await Session.isLoggedIn, isFalse);
    expect(await Session.accessToken, isNull,
        reason: 'Token còn sót lại sau khi đăng xuất là lỗi bảo mật');
    expect(await Session.firebaseChatToken, isNull);
  });
}
