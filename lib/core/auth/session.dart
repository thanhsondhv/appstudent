import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_role.dart';

/// Kho lưu phiên đăng nhập — NƠI DUY NHẤT đọc và ghi thông tin người dùng.
///
/// Trước ngày 18/08/2026, thông tin phiên được đọc rải rác bằng
/// `prefs.getString('user_role')` ở hơn 10 màn hình, mỗi nơi tự đặt giá trị mặc
/// định riêng. Việc ghi phiên thì trùng lặp ở cả `AuthService._saveUserSession`
/// lẫn `LoginHandler.executeSuccessfulLogin` với logic hơi khác nhau.
///
/// Điểm khác biệt về bảo mật: token nay nằm trong [FlutterSecureStorage]
/// (Keychain trên iOS, EncryptedSharedPreferences trên Android) thay vì
/// SharedPreferences dạng chữ thường. Thông tin không nhạy cảm như họ tên,
/// khoa vẫn ở SharedPreferences vì đọc nhanh hơn và không cần bảo vệ.
///
/// Phiên cũ được chuyển đổi tự động ở lần chạy đầu — người dùng không bị đăng xuất.
class Session {
  Session._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // --- Khoá lưu trữ ---------------------------------------------------------
  static const _kUserId = 'user_id';
  static const _kUserCode = 'user_code';
  static const _kFullName = 'full_name';
  static const _kRole = 'user_role';
  static const _kFaculty = 'user_faculty';
  static const _kDept = 'user_dept';
  static const _kLoggedIn = 'is_logged_in';
  static const _kMigrated = 'session_migrated_v2';

  // Các khoá nhạy cảm — lưu trong kho mã hoá
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kMsAccessToken = 'ms_access_token';
  static const _kMsTokenExpiry = 'ms_token_expiry';
  static const _kFirebaseChatToken = 'firebase_chat_token';

  static const _sensitiveKeys = [
    _kAccessToken,
    _kRefreshToken,
    _kMsAccessToken,
    _kFirebaseChatToken,
  ];

  // --- Bộ nhớ đệm trong phiên chạy -----------------------------------------
  static SharedPreferences? _prefs;
  static UserRole? _cachedRole;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Gọi một lần khi ứng dụng khởi động, trước khi dùng bất kỳ hàm nào khác.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateTokensToSecureStorage();
  }

  /// Chuyển token từ SharedPreferences sang kho mã hoá. Chạy đúng một lần.
  static Future<void> _migrateTokensToSecureStorage() async {
    final prefs = await _p;
    if (prefs.getBool(_kMigrated) ?? false) return;

    var moved = 0;
    for (final key in _sensitiveKeys) {
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: key, value: legacy);
        await prefs.remove(key); // xoá bản chữ thường
        moved++;
      }
    }
    await prefs.setBool(_kMigrated, true);
    if (moved > 0) {
      debugPrint("🔐 [Session] Đã chuyển $moved token sang kho mã hoá");
    }
  }

  // --- Đọc thông tin --------------------------------------------------------

  /// Mã sinh viên hoặc mã cán bộ (đã lọc chỉ còn chữ số nếu có thể).
  static Future<String> get userCode async =>
      (await _p).getString(_kUserCode) ?? (await _p).getString(_kUserId) ?? '';

  static Future<String> get fullName async =>
      (await _p).getString(_kFullName) ?? 'Thành viên VinhUni';

  static Future<String> get faculty async => (await _p).getString(_kFaculty) ?? '';

  static Future<String> get department async => (await _p).getString(_kDept) ?? '';

  static Future<bool> get isLoggedIn async => (await _p).getBool(_kLoggedIn) ?? false;

  /// Vai trò đã được chuẩn hoá. Dùng cái này thay cho việc tự đọc chuỗi.
  ///
  /// ```dart
  /// final role = await Session.role;
  /// if (role.canOpenAttendance) { ... }
  /// ```
  static Future<UserRole> get role async {
    if (_cachedRole != null) return _cachedRole!;
    _cachedRole = UserRole.parse((await _p).getString(_kRole));
    return _cachedRole!;
  }

  /// Bản đồng bộ, chỉ dùng được sau khi [init] đã chạy — tiện cho hàm `build`.
  static UserRole get roleSync =>
      _cachedRole ??= UserRole.parse(_prefs?.getString(_kRole));

  static Future<String?> get accessToken => _secure.read(key: _kAccessToken);
  static Future<String?> get refreshToken => _secure.read(key: _kRefreshToken);
  static Future<String?> get firebaseChatToken => _secure.read(key: _kFirebaseChatToken);

  /// Token Microsoft, tự trả `null` nếu đã hết hạn — bên gọi không phải tự kiểm tra.
  static Future<String?> get msAccessToken async {
    final expiry = (await _p).getInt(_kMsTokenExpiry) ?? 0;
    if (expiry > 0 && DateTime.now().millisecondsSinceEpoch >= expiry) {
      debugPrint("⏰ [Session] Token Microsoft đã hết hạn, cần kết nối lại");
      return null;
    }
    return _secure.read(key: _kMsAccessToken);
  }

  // --- Ghi thông tin --------------------------------------------------------

  /// Lưu phiên sau khi đăng nhập thành công, bất kể đăng nhập bằng cách nào
  /// (mật khẩu, khuôn mặt, Office 365).
  ///
  /// Thay thế cả `AuthService._saveUserSession` lẫn
  /// `LoginHandler.executeSuccessfulLogin` — trước đây hai hàm này làm gần
  /// giống nhau nhưng khác ở vài chỗ, gây ra phiên không nhất quán.
  static Future<void> save(Map<String, dynamic> data) async {
    final prefs = await _p;

    // Mã người dùng: máy chủ trả về nhiều tên khoá khác nhau tuỳ endpoint
    final rawId = (data['user_code'] ?? data['user_id'] ?? data['student_id'] ?? '').toString();
    final numericId = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    final userCode = numericId.isNotEmpty ? numericId : rawId;

    final parsedRole = UserRole.parse(
      (data['user_role'] ?? data['role'])?.toString(),
    );

    await prefs.setString(_kUserId, userCode);
    await prefs.setString(_kUserCode, userCode);
    await prefs.setString(
      _kFullName,
      (data['full_name'] ?? data['user_name'] ?? 'Thành viên VinhUni').toString(),
    );
    // Luôn ghi ở dạng chuẩn — chấm dứt việc mỗi endpoint ghi một kiểu chữ
    await prefs.setString(_kRole, parsedRole.wireValue);
    await prefs.setString(
      _kFaculty,
      (data['user_faculty'] ?? data['faculty'] ?? '').toString(),
    );
    await prefs.setString(_kDept, (data['department'] ?? '').toString());
    await prefs.setBool(_kLoggedIn, true);
    _cachedRole = parsedRole;

    await _writeSecure(_kAccessToken, data['access_token']);
    await _writeSecure(_kRefreshToken, data['refresh_token']);
    await _writeSecure(_kFirebaseChatToken, data['firebase_chat_token']);

    final msToken = data['ms_access_token']?.toString();
    if (msToken != null && msToken.isNotEmpty) {
      await saveMicrosoftToken(msToken, expiresInSeconds: data['ms_expires_in'] as int?);
    }

    debugPrint("🚀 [Session] Đã lưu phiên: $userCode — ${parsedRole.displayName}");
  }

  /// Lưu riêng token Microsoft khi kết nối lại OneDrive mà không đăng nhập lại.
  static Future<void> saveMicrosoftToken(String token, {int? expiresInSeconds}) async {
    await _secure.write(key: _kMsAccessToken, value: token);
    // Trừ hao 100 giây để không dùng token ngay sát thời điểm hết hạn
    final ttl = ((expiresInSeconds ?? 3600) - 100) * 1000;
    await (await _p).setInt(
      _kMsTokenExpiry,
      DateTime.now().millisecondsSinceEpoch + ttl,
    );
  }

  static Future<void> _writeSecure(String key, dynamic value) async {
    final str = value?.toString();
    if (str != null && str.isNotEmpty) {
      await _secure.write(key: key, value: str);
    }
  }

  /// Xoá sạch phiên khi đăng xuất hoặc khi máy chủ báo token không còn hợp lệ.
  static Future<void> clear() async {
    final prefs = await _p;
    for (final key in [
      _kUserId, _kUserCode, _kFullName, _kRole,
      _kFaculty, _kDept, _kLoggedIn, _kMsTokenExpiry,
    ]) {
      await prefs.remove(key);
    }
    for (final key in _sensitiveKeys) {
      await _secure.delete(key: key);
    }
    _cachedRole = null;
    debugPrint("👋 [Session] Đã xoá phiên đăng nhập");
  }
}
